#!/usr/bin/env python3
"""Contrôles objectifs des captures de l'accueil, sans donnée personnelle.

Le contraste est mesuré sur les pixels de la PWA compilée : les glyphes blancs
sont détectés dans les trois zones de texte de l'en-tête, puis le fond local est
échantillonné dans un anneau à 4–8 px autour des lettres (hors anti-aliasing).
Le 99e percentile du fond est utilisé : on mesure donc le cas défavorable, pas
une moyenne flatteuse. Seuils : 4,5:1 pour les petits textes, 3:1 pour l'heure.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "apercu-accueil")
MESURES = json.loads((OUT / "mesures.json").read_text())


def luminance(rgb: np.ndarray) -> np.ndarray:
    s = rgb.astype(float) / 255.0
    lineaire = np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)
    return (
        0.2126 * lineaire[..., 0]
        + 0.7152 * lineaire[..., 1]
        + 0.0722 * lineaire[..., 2]
    )


def haut_entete(rgb: np.ndarray, dpr: float) -> int:
    """Repère le bord supérieur de la carte au centre de l'écran."""
    h, w, _ = rgb.shape
    x0, x1 = int(w * 0.42), int(w * 0.58)
    limite = min(h, int(55 * dpr))
    bande = rgb[:limite, x0:x1].astype(float)
    # Distance à la couleur de la page, puis premier bord franc durable.
    page = np.median(bande[: max(2, int(3 * dpr))], axis=(0, 1))
    distance = np.abs(bande - page).sum(axis=2).mean(axis=1)
    for y in range(max(2, int(4 * dpr)), limite - int(4 * dpr)):
        if distance[y] > 45 and np.mean(distance[y : y + max(2, int(3 * dpr))]) > 40:
            return y
    # Repli : plus forte transition verticale dans la même zone.
    transition = np.abs(np.diff(bande, axis=0)).sum(axis=2).mean(axis=1)
    return int(np.argmax(transition) + 1)


def dilater(mask: np.ndarray, rayon: int) -> np.ndarray:
    taille = max(3, rayon * 2 + 1)
    im = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
    return np.asarray(im.filter(ImageFilter.MaxFilter(taille))) > 0


def contraste_zone(
    rgb: np.ndarray,
    boite: tuple[float, float, float, float],
    dpr: float,
    seuil: float,
) -> dict:
    x0, y0, x1, y1 = [int(round(v * dpr)) for v in boite]
    zone = rgb[max(0, y0) : min(rgb.shape[0], y1), max(0, x0) : min(rgb.shape[1], x1)]
    if zone.size == 0:
        return {"ratio": 0, "seuil": seuil, "erreur": "zone vide"}
    mini = zone.min(axis=2)
    maxi = zone.max(axis=2)
    # Texte blanc/crème ; le voile garantit que la photo reste sous ce seuil.
    mask = (mini > 190) & ((maxi - mini) < 52)
    if int(mask.sum()) < 12:
        return {"ratio": 0, "seuil": seuil, "erreur": "glyphes non détectés"}
    if mask.mean() > 0.65:
        return {"ratio": 0, "seuil": seuil, "erreur": "zone presque entièrement blanche (rendu probablement absent)"}
    proche = dilater(mask, max(2, int(round(4 * dpr))))
    lointain = dilater(mask, max(4, int(round(8 * dpr))))
    anneau = lointain & ~proche & ~mask & (mini < 205)
    if int(anneau.sum()) < 20:
        return {"ratio": 0, "seuil": seuil, "erreur": "fond local insuffisant"}
    lum = luminance(zone)
    # Le 20e percentile du glyphe évite qu'un seul pixel blanc fausse la mesure.
    lg = float(np.percentile(lum[mask], 20))
    # Le 99e percentile du fond est volontairement conservateur.
    lf = float(np.percentile(lum[anneau], 99))
    ratio = (max(lg, lf) + 0.05) / (min(lg, lf) + 0.05)
    return {
        "ratio": round(ratio, 2),
        "seuil": seuil,
        "glyphesPx": int(mask.sum()),
        "fondPx": int(anneau.sum()),
        "ok": ratio + 1e-9 >= seuil,
    }


def analyser(scenario: dict) -> list[dict]:
    # La coque ordinateur déplace l'app ; les tests widget couvrent sa mise en
    # page, tandis que la mesure pixel ci-dessous vise les écrans pleine largeur.
    if not scenario.get("mobile") or not scenario.get("capture"):
        return []
    if not scenario["nom"].startswith(("reference-", "telephone-")):
        return []
    image = Image.open(OUT / scenario["capture"]).convert("RGB")
    rgb = np.asarray(image)
    dpr = float(scenario["dpr"])
    w = float(scenario["w"])
    x = 20.0
    largeur = w - 40.0
    top = haut_entete(rgb, dpr) / dpr
    resultats = []
    zones = [
        ("En-Check", (x + 19, top + 23, x + largeur * 0.32 + 19, top + 51), 4.5),
        ("heure", (x + largeur * 0.29, top + 14, x + largeur * 0.71, top + 50), 3.0),
        ("date", (x + 70, top + 48, x + largeur - 70, top + 69), 4.5),
    ]
    for nom, boite, seuil in zones:
        resultats.append(
            {
                "scenario": scenario["nom"],
                "element": nom,
                "enteteTopPt": round(top, 2),
                **contraste_zone(rgb, boite, dpr, seuil),
            }
        )
    return resultats


contrastes = []
for scenario in MESURES:
    contrastes.extend(analyser(scenario))

echecs = []
for scenario in MESURES:
    if scenario.get("debordementDomPx", 0) > 1:
        echecs.append(f"{scenario['nom']}: débordement DOM {scenario['debordementDomPx']} px")
    if not scenario.get("calme"):
        echecs.append(f"{scenario['nom']}: rendu jamais calme")
    for erreur in scenario.get("erreursJs", []):
        echecs.append(f"{scenario['nom']}: {erreur}")
    if scenario.get("erreurCapture"):
        echecs.append(f"{scenario['nom']}: {scenario['erreurCapture']}")
for c in contrastes:
    if not c.get("ok"):
        echecs.append(
            f"{c['scenario']} / {c['element']}: {c.get('ratio', 0)}:1 "
            f"(seuil {c['seuil']}:1){' — ' + c['erreur'] if c.get('erreur') else ''}"
        )

rapport = {
    "methode": "Pixels de la PWA compilée ; fond local 99e percentile, glyphe 20e percentile.",
    "captures": len(MESURES),
    "contrastes": contrastes,
    "echecs": echecs,
}
(OUT / "controle.json").write_text(json.dumps(rapport, ensure_ascii=False, indent=2))

lignes = [
    "# Contrôle de l'accueil compilé",
    "",
    f"- Captures : **{len(MESURES)}**",
    f"- Débordements DOM : **{sum(s.get('debordementDomPx', 0) > 1 for s in MESURES)}**",
    f"- Rendus non calmes : **{sum(not s.get('calme') for s in MESURES)}**",
    f"- Mesures de contraste d'en-tête : **{len(contrastes)}**",
    "",
    "| Capture | Premier frame | Débordement DOM |",
    "|---|---:|---:|",
]
for s in MESURES:
    lignes.append(
        f"| {s['nom']} | {s.get('premierFrameMs', '—')} ms | {s.get('debordementDomPx', '—')} px |"
    )
if contrastes:
    lignes += ["", "| En-tête | Élément | Contraste | Seuil |", "|---|---|---:|---:|"]
    for c in contrastes:
        lignes.append(
            f"| {c['scenario']} | {c['element']} | {c.get('ratio', 0)}:1 | {c['seuil']}:1 |"
        )
lignes += ["", "## Échecs", ""]
lignes += [f"- {e}" for e in echecs] if echecs else ["Aucun."]
(OUT / "rapport.md").write_text("\n".join(lignes) + "\n")
print("\n".join(lignes[:8]))
if echecs:
    print("ÉCHECS :\n- " + "\n- ".join(echecs))
    sys.exit(2)
print("Tous les contrôles sont verts.")

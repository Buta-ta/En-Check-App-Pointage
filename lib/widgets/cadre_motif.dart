// lib/widgets/cadre_motif.dart
// ═══════════════════════════════════════════════════════════
// 🖼️ CADRE MOTIF — les espaces latéraux de la fenêtre
// ═══════════════════════════════════════════════════════════
//
//  Sur grand écran, l'app est présentée comme un SMARTPHONE posé
//  sur le motif culturel actif (étoffe + vignette chaude).
//
//  - Gauche, en bas : « Motifs culturels du … — Peuple … »
//    (UNIQUEMENT dans l'espace latéral, jamais dans l'app).
//  - Droite, centré : le slogan d'En-Check.
//
//  Le cadre du téléphone s'amincit automatiquement quand la
//  fenêtre est courte : l'app garde au moins 780 px de hauteur
//  pour rester en mode « zéro scroll ».
// ═══════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/material.dart';

import '../services/motif_service.dart';

class CadreMotif extends StatelessWidget {
  const CadreMotif({super.key, required this.child});

  final Widget child;

  /// La colonne de l'app ne dépasse jamais cette largeur.
  static const double largeurApp = 620;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeur =
            constraints.maxWidth.isFinite ? constraints.maxWidth : largeurApp;
        final hauteur =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 900.0;
        final double cote = max(0.0, (largeur - largeurApp) / 2);
        final cadreVisible = cote > 8;

        // ── Contours du téléphone ────────────────────────────────
        // La coque + les marges ne doivent jamais priver l'app des
        // 780 px de hauteur qui garantissent le « zéro scroll ».
        double bezel = 0;
        double margeV = 0;
        if (cadreVisible) {
          if (hauteur >= 860) {
            bezel = 12;
            margeV = 28;
          } else {
            final double coteChrome = max(12.0, min(56.0, hauteur - 780)) / 2;
            bezel = max(4.0, min(12.0, coteChrome * 0.45));
            margeV = max(2.0, min(28.0, coteChrome - bezel));
          }
        }

        final double hauteurTelephone = max(320.0, hauteur - 2 * margeV);
        final double largeurTelephone = min(largeurApp + 2 * bezel, largeur);
        final double rayonEcran = max(16.0, bezel * 2.6);

        return Stack(
          children: [
            if (cadreVisible) ...[
              // Étoffe du motif actif, répétée verticalement sur la fenêtre.
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: MotifService.actif,
                  builder: (context, _) {
                    final motif = MotifService.actif.value;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(motif.asset),
                          fit: BoxFit.fitWidth,
                          repeat: ImageRepeat.repeatY,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Vignette : assombrit doucement vers les bords de la fenêtre.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: cote,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xB0120C06), Color(0x00120C06)],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: cote,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [Color(0xB0120C06), Color(0x00120C06)],
                    ),
                  ),
                ),
              ),
              // Message culturel — SEULEMENT dans l'espace latéral gauche.
              if (cote >= 200)
                Positioned(
                  left: 28,
                  bottom: 32,
                  width: cote - 56,
                  child: const _MessageCulturel(),
                ),
              // Slogan d'En-Check — dans l'espace latéral droit.
              if (cote >= 200)
                Positioned(
                  right: 28,
                  top: 0,
                  bottom: 0,
                  width: cote - 56,
                  child: const Center(child: _SloganEnCheck()),
                ),
            ],
            // Le téléphone posé sur l'étoffe (ou l'app pleine largeur
            // quand la fenêtre est trop étroite pour un cadre).
            Center(
              child: cadreVisible
                  ? _Telephone(
                      largeur: largeurTelephone,
                      hauteur: hauteurTelephone,
                      bezel: bezel,
                      rayonEcran: rayonEcran,
                      child: child,
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: largeurApp),
                      child: child,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 📱 Coque du téléphone : bordure mate, haut-parleur, caméra,
/// boutons latéraux et ombre douce (« posé sur le motif »).
class _Telephone extends StatelessWidget {
  const _Telephone({
    required this.largeur,
    required this.hauteur,
    required this.bezel,
    required this.rayonEcran,
    required this.child,
  });

  final double largeur;
  final double hauteur;
  final double bezel;
  final double rayonEcran;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double rayonCoque = rayonEcran + bezel * 1.8;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Boutons latéraux (volume à gauche, power à droite).
        if (bezel >= 8) ...[
          Positioned(
            left: -3,
            top: hauteur * 0.22,
            child: const _BoutonCoque(hauteur: 46),
          ),
          Positioned(
            left: -3,
            top: hauteur * 0.22 + 56,
            child: const _BoutonCoque(hauteur: 46),
          ),
          Positioned(
            right: -3,
            top: hauteur * 0.30,
            child: const _BoutonCoque(hauteur: 72),
          ),
        ],
        Container(
          width: largeur,
          height: hauteur,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(rayonCoque),
            border: Border.all(color: const Color(0x26FFFFFF), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 44,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 14,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Haut-parleur + caméra dans la bordure haute.
              if (bezel >= 10)
                Positioned(
                  top: (bezel - 7) / 2,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF202020),
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Color(0xFF2E2E2E)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 52,
                        height: 3,
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              // L'écran de l'app.
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(bezel),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(rayonEcran),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoutonCoque extends StatelessWidget {
  const _BoutonCoque({required this.hauteur});

  final double hauteur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: hauteur,
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// « Motifs culturels du Congo » + « Raphia — Peuple Kuba ».
class _MessageCulturel extends StatelessWidget {
  const _MessageCulturel();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MotifService.actif,
      builder: (context, _) {
        final motif = MotifService.actif.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 28, height: 2, color: motif.couleurAccent),
            const SizedBox(height: 10),
            Text(
              titreMotifsCulturels(motif.pays),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF4EFE2),
                letterSpacing: 0.2,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${motif.nom} — Peuple ${motif.peuple}',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color(0xB8F4EFE2),
                height: 1.35,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Le slogan d'En-Check, dans l'espace latéral droit.
class _SloganEnCheck extends StatelessWidget {
  const _SloganEnCheck();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MotifService.actif,
      builder: (context, _) {
        final motif = MotifService.actif.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(width: 28, height: 2, color: motif.couleurAccent),
            const SizedBox(height: 12),
            const Text(
              'En-Check',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF4EFE2),
                letterSpacing: 0.4,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gestion de pointage intelligente pour entreprises',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: Color(0xB8F4EFE2),
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ],
        );
      },
    );
  }
}

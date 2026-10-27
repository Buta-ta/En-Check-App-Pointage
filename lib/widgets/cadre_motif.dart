// lib/widgets/cadre_motif.dart
// ═══════════════════════════════════════════════════════════
// 🖼️ CADRE MOTIF — les espaces latéraux de la fenêtre
// ═══════════════════════════════════════════════════════════
//
//  Sur grand écran, l'app reste centrée (620 px) et les espaces
//  à gauche et à droite sont habillés avec le motif culturel actif,
//  assombris vers les bords de la fenêtre (vignette chaude).
//
//  Un petit message « Motifs culturels du … — Peuple … » s'affiche
//  UNIQUEMENT dans l'espace latéral (jamais dans l'app centrée).
//  Il suit le motif choisi dans Paramètres.
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
        final double cote = max(0.0, (largeur - largeurApp) / 2);
        final cadreVisible = cote > 8;

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
              // Petit message culturel — SEULEMENT dans l'espace latéral.
              if (cote >= 190)
                Positioned(
                  left: 28,
                  bottom: 32,
                  width: cote - 52,
                  child: const _MessageCulturel(),
                ),
            ],
            // L'app centrée, posée sur le cadre.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: largeurApp),
                child: cadreVisible
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: child,
                      )
                    : child,
              ),
            ),
          ],
        );
      },
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

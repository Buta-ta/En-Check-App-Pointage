// lib/widgets/frise_motif.dart
// ═══════════════════════════════════════════════════════════
// 🧵 FRISE MOTIF — le textile culturel en haut de l'accueil
// ═══════════════════════════════════════════════════════════
//
//  Affiche l'étoffe choisie par l'entreprise (Raphia par défaut) en
//  plein cadre, comme les bandes illustrées de l'app En-Check Admin.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../services/motif_service.dart';

class FriseMotif extends StatelessWidget {
  final MotifCulturel motif;
  final double hauteur;

  const FriseMotif({super.key, required this.motif, this.hauteur = 230});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: hauteur,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // L'étoffe elle-même (vraie image du textile).
          Image.asset(
            motif.asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: motif.couleurBouton),
          ),
          // Léger assombrissement en haut : le bouton ⚙️ reste lisible
          // sur toutes les étoffes, claires comme foncées.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withOpacity(0.28),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

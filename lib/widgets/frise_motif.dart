// lib/widgets/frise_motif.dart
// ═══════════════════════════════════════════════════════════
// 🧵 FRISE MOTIF — le textile culturel en haut de l'accueil
// ═══════════════════════════════════════════════════════════
//
//  Affiche l'étoffe choisie par l'entreprise (Adinkra par défaut) en
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
            // En frise fine, toute la hauteur des symboles reste visible
            // sur toute la largeur (maquette). Les grands visuels gardent
            // leur cadrage cover pour ne pas être déformés.
            fit: hauteur <= 40 ? BoxFit.fill : BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: motif.couleurBouton),
          ),
        ],
      ),
    );
  }
}

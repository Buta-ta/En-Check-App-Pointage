// lib/widgets/frise_motif.dart
// ═══════════════════════════════════════════════════════════
// 🧵 FRISE MOTIF — le textile culturel choisi dans Paramètres
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../services/motif_service.dart';

class FriseMotif extends StatelessWidget {
  final MotifCulturel motif;
  final double hauteur;

  /// Réglages réservés aux accents mats : les grandes illustrations gardent
  /// leurs valeurs par défaut et leur cadrage habituel.
  final double opacite;
  final double agrandissementHorizontal;
  final Color? fond;

  const FriseMotif({
    super.key,
    required this.motif,
    this.hauteur = 230,
    this.opacite = 1,
    this.agrandissementHorizontal = 1,
    this.fond,
  })  : assert(hauteur > 0),
        assert(opacite >= 0 && opacite <= 1),
        assert(agrandissementHorizontal >= 1);

  @override
  Widget build(BuildContext context) {
    final friseFine = hauteur <= 40;
    Widget image = Image.asset(
      motif.asset,
      // En frise fine, toute la hauteur des symboles reste visible. Les
      // grands visuels gardent leur cadrage cover pour ne pas être déformés.
      fit: friseFine ? BoxFit.fill : BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Container(color: motif.couleurBouton),
    );

    // Sur l'accueil, élargir légèrement les formes évite un filet trop dense.
    // L'échelle ne s'applique qu'à la frise explicitement configurée : les
    // autres écrans conservent exactement leur rendu précédent.
    if (friseFine && agrandissementHorizontal != 1) {
      image = Transform.scale(
        scaleX: agrandissementHorizontal,
        child: image,
      );
    }
    if (opacite < 1) image = Opacity(opacity: opacite, child: image);

    return SizedBox(
      height: hauteur,
      width: double.infinity,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fond != null) ColoredBox(color: fond!),
            image,
          ],
        ),
      ),
    );
  }
}

/// Un seul petit extrait de la MÊME étoffe, pour un espace vide de l'accueil.
/// Ce n'est ni une icône générique, ni un nouveau dessin, ni un logo.
class MotifSecondaire extends StatelessWidget {
  const MotifSecondaire({
    super.key,
    required this.motif,
    this.largeur = 42,
    this.hauteur = 22,
    this.opacite = 0.20,
  }) : assert(opacite >= 0 && opacite <= 1);

  final MotifCulturel motif;
  final double largeur;
  final double hauteur;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Opacity(
        opacity: opacite,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: largeur,
            height: hauteur,
            child: Image.asset(
              motif.asset,
              fit: BoxFit.cover,
              cacheWidth: 192,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) =>
                  ColoredBox(color: motif.couleurTint),
            ),
          ),
        ),
      ),
    );
  }
}

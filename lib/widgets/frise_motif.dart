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
  final Color? fond;

  /// Sur l'accueil, répète une rangée au bon ratio au lieu d'écraser toute
  /// la nappe dans quelques pixels. Aucun ScrollView n'est introduit.
  final bool tuilee;

  const FriseMotif({
    super.key,
    required this.motif,
    this.hauteur = 230,
    this.opacite = 1,
    this.fond,
    this.tuilee = false,
  })  : assert(hauteur > 0),
        assert(opacite >= 0 && opacite <= 1);

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (tuilee) {
      image = LayoutBuilder(
        builder: (context, contraintes) {
          final largeurTuile = hauteur * motif.friseRatio;
          final nombre = (contraintes.maxWidth / largeurTuile).ceil() + 1;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var i = 0; i < nombre; i++)
                Positioned(
                  left: i * largeurTuile,
                  top: 0,
                  bottom: 0,
                  width: largeurTuile,
                  child: Image.asset(
                    motif.friseAsset,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) =>
                        ColoredBox(color: motif.couleurBouton),
                  ),
                ),
            ],
          );
        },
      );
    } else {
      image = Image.asset(
        motif.asset,
        // Les autres écrans conservent exactement leur rendu précédent.
        fit: hauteur <= 40 ? BoxFit.fill : BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Container(color: motif.couleurBouton),
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

/// Petit pictogramme UI issu de la MÊME rangée que le bandeau. Le crop
/// centré contient un symbole identifiable ; ce n'est ni une icône générique,
/// ni un nouveau dessin, ni un logo.
class MotifUiIcon extends StatelessWidget {
  const MotifUiIcon({
    super.key,
    required this.motif,
    required this.fond,
    required this.bordure,
    this.taille = 32,
    this.opacite = 0.68,
  }) : assert(opacite >= 0 && opacite <= 1);

  final MotifCulturel motif;
  final Color fond;
  final Color bordure;
  final double taille;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(
          color: fond,
          border: Border.all(color: bordure),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Opacity(
            opacity: opacite,
            child: Image.asset(
              motif.friseAsset,
              fit: BoxFit.cover,
              cacheHeight: 128,
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


/// Symbole seul, sans pastille ni bordure, pour le petit accent de la
/// maquette Pause. Il provient du même crop que la frise et les autres UI.
class MotifSymbole extends StatelessWidget {
  const MotifSymbole({
    super.key,
    required this.motif,
    this.taille = 22,
    this.opacite = 0.72,
  }) : assert(opacite >= 0 && opacite <= 1);

  final MotifCulturel motif;
  final double taille;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Opacity(
        opacity: opacite,
        child: SizedBox(
          width: taille,
          height: taille,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.asset(
              motif.friseAsset,
              fit: BoxFit.cover,
              cacheHeight: 96,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

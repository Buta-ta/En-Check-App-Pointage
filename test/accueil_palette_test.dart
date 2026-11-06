import 'dart:math' as math;

import 'package:en_check/services/motif_service.dart';
import 'package:en_check/theme/accueil_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double canal(num v) {
    final s = v / 255;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * canal(c.red) +
      0.7152 * canal(c.green) +
      0.0722 * canal(c.blue);
}

double _contraste(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final clair = math.max(la, lb);
  final sombre = math.min(la, lb);
  return (clair + 0.05) / (sombre + 0.05);
}

void main() {
  test('Les accents des 4 motifs gardent un contraste WCAG AA', () {
    for (final motif in MotifCulturel.tous) {
      for (final sombre in [false, true]) {
        final p = AccueilPalette.pour(motif, sombre);
        final paires = <String, List<Color>>{
          'texte Départ / fond': [p.surPrimaire, p.primaire],
          'icône Départ / cercle': [p.iconePrimaire, p.cerclePrimaire],
          'icône Arrivée / cercle': [p.iconeDouce, p.cercleDoux],
          'texte Arrivée / fond': [p.texte, p.carteDouce],
          'lien / carte': [p.lien, p.surface],
          'navigation inactive': [p.navInactif, p.navFond],
          'navigation active': [p.navActif, p.navFond],
          'plaque entreprise': [p.plaqueTexte, p.plaque],
        };
        for (final entree in paires.entries) {
          final ratio = _contraste(entree.value[0], entree.value[1]);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${motif.id}, sombre=$sombre, ${entree.key}: '
                '${ratio.toStringAsFixed(2)}:1',
          );
        }
      }
    }
  });
}

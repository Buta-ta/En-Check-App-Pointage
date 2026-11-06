import 'dart:math' as math;

import 'package:en_check/services/motif_service.dart';
import 'package:en_check/theme/accueil_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  test('Les accents suivent le motif sans changer les fonds neutres', () {
    for (final sombre in [false, true]) {
      final reference = AccueilPalette.pour(MotifCulturel.adinkra, sombre);
      for (final motif in MotifCulturel.tous) {
        final p = AccueilPalette.pour(motif, sombre);
        expect(p.fond, reference.fond);
        expect(p.surface, reference.surface);
        expect(p.texte, reference.texte);
        if (motif != MotifCulturel.adinkra) {
          expect(p.primaire, isNot(reference.primaire),
              reason: '${motif.id}, sombre=$sombre');
          expect(p.lien, isNot(reference.lien),
              reason: '${motif.id}, sombre=$sombre');
        }
      }
    }
  });

  testWidgets('Le motif choisi met les accents à jour immédiatement',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final initial = MotifService.actif.value;
    addTearDown(() => MotifService.actif.value = initial);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<MotifCulturel>(
          valueListenable: MotifService.actif,
          builder: (context, motif, _) => ColoredBox(
            key: const Key('accent-test'),
            color: AccueilPalette.pour(motif, false).primaire,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    Color accent() => tester.widget<ColoredBox>(
          find.byKey(const Key('accent-test')),
        ).color;

    expect(accent(), AccueilPalette.pour(initial, false).primaire);
    final enregistrement = MotifService.enregistrer(MotifCulturel.zoulou);
    // La notification est synchrone, avant la fin de l'écriture disque.
    await tester.pump();
    expect(MotifService.actif.value, MotifCulturel.zoulou);
    expect(accent(), AccueilPalette.pour(MotifCulturel.zoulou, false).primaire);
    await enregistrement;
  });

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

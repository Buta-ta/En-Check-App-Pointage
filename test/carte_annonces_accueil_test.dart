import 'package:en_check/services/motif_service.dart';
import 'package:en_check/theme/accueil_palette.dart';
import 'package:en_check/widgets/carte_annonces_accueil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('l’icône annonce indique le nombre et ouvre les annonces',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BoutonAnnoncesAccueil(
              nombre: 2,
              palette: AccueilPalette.pour(MotifCulturel.adinkra, false),
              onPressed: () => opened = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Annonces'), findsOneWidget);
    await tester.tap(find.byTooltip('Annonces'));
    expect(opened, isTrue);
  });
}

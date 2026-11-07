import 'package:en_check/screens/identification_slide_page.dart';
import 'package:en_check/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Accueil annule le pointage et retourne à la route publique',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeService();
    var retoursAccueil = 0;
    var champsEffacesAvantRetour = false;
    late TextEditingController matriculeController;
    late TextEditingController pinController;
    late BuildContext racine;

    await tester.pumpWidget(ChangeNotifierProvider<ThemeService>.value(
      value: theme,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            racine = context;
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => IdentificationSlidePage(
                      titre: 'POINTAGE',
                      sceneAsset: 'assets/scenes/scene_pointage.jpg',
                      aide: 'Identifiez-vous pour pointer.',
                      entrepriseId: 'entreprise-recette',
                      matriculePrefix: 'TST',
                      maquettePointage: true,
                      onAccueil: () {
                        retoursAccueil++;
                        champsEffacesAvantRetour =
                            matriculeController.text.isEmpty &&
                                pinController.text.isEmpty;
                        Navigator.of(racine)
                            .popUntil((route) => route.isFirst);
                      },
                    ),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            );
          },
        ),
      ),
    ));

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('IDENTIFICATION DU POINTAGE'), findsOneWidget);
    expect(find.text('Matricule'), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    matriculeController = tester
        .widget<TextField>(find.byKey(const Key('identification-matricule')))
        .controller!;
    pinController = tester
        .widget<TextField>(find.byKey(const Key('identification-pin')))
        .controller!;
    await tester.enterText(
        find.byKey(const Key('identification-matricule')), '0002');
    await tester.enterText(
        find.byKey(const Key('identification-pin')), '1234');

    await tester.tap(find.byKey(const Key('pointage-accueil')));
    await tester.pumpAndSettle();
    expect(retoursAccueil, 1);
    expect(champsEffacesAvantRetour, isTrue);
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(find.text('IDENTIFICATION DU POINTAGE'), findsNothing);
    expect(tester.takeException(), isNull);

    theme.dispose();
  });
}

import 'package:en_check/screens/identification_slide_page.dart';
import 'package:en_check/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('La flèche annule le pointage et revient à l’accueil interne',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeService();
    addTearDown(theme.dispose);

    await tester.pumpWidget(ChangeNotifierProvider<ThemeService>.value(
      value: theme,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const IdentificationSlidePage(
                    titre: 'POINTAGE',
                    sceneAsset: 'assets/scenes/scene_pointage.jpg',
                    aide: 'Identifiez-vous pour pointer.',
                    entrepriseId: 'entreprise-recette',
                    matriculePrefix: 'TST',
                    maquettePointage: true,
                  ),
                ),
              ),
              child: const Text('Ouvrir accueil pointage'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Ouvrir accueil pointage'));
    await tester.pumpAndSettle();
    expect(find.text('IDENTIFICATION DU POINTAGE'), findsOneWidget);
    expect(find.text('Matricule'), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Accueil'), findsNothing);
    expect(find.text('Retour'), findsOneWidget);
    expect(find.byKey(const Key('pointage-scene-retour')), findsOneWidget);

    final themeButton = find.byKey(const Key('pointage-theme'));
    expect(themeButton, findsOneWidget);
    await tester.tap(themeButton);
    await tester.pumpAndSettle();
    expect(theme.isDarkMode, isTrue);
    await tester.tap(themeButton);
    await tester.pumpAndSettle();
    expect(theme.isDarkMode, isFalse);

    final matriculeController = tester
        .widget<TextField>(find.byKey(const Key('identification-matricule')))
        .controller!;
    final pinController = tester
        .widget<TextField>(find.byKey(const Key('identification-pin')))
        .controller!;
    await tester.enterText(
        find.byKey(const Key('identification-matricule')), '0002');
    await tester.enterText(
        find.byKey(const Key('identification-pin')), '1234');

    await tester.tap(find.byKey(const Key('pointage-scene-retour')));
    await tester.pumpAndSettle();
    expect(matriculeController.text, isEmpty);
    expect(pinController.text, isEmpty);
    expect(find.text('Ouvrir accueil pointage'), findsOneWidget);
    expect(find.text('IDENTIFICATION DU POINTAGE'), findsNothing);
    expect(find.text('Commencer'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

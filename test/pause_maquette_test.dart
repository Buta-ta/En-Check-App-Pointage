import 'package:en_check/screens/identification_slide_page.dart';
import 'package:en_check/services/motif_service.dart';
import 'package:en_check/services/theme_service.dart';
import 'package:en_check/theme/accueil_palette.dart';
import 'package:en_check/widgets/frise_motif.dart';
import 'package:en_check/widgets/slide_valider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeService> _pomperIdentification(
  WidgetTester tester,
  Size taille, {
  bool pause = true,
  bool sombre = false,
  double texte = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  SharedPreferences.setMockInitialValues({'apparence_sombre_v2': sombre});
  final initial = MotifService.actif.value;
  MotifService.actif.value = MotifCulturel.adinkra;
  addTearDown(() => MotifService.actif.value = initial);
  final service = ThemeService();
  addTearDown(service.dispose);
  await tester.binding.setSurfaceSize(taille);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: service,
      child: Consumer<ThemeService>(
        builder: (context, theme, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            fontFamily: 'Inter',
            scaffoldBackgroundColor: const Color(0xFFF5F2E9),
            cardColor: const Color(0xFFFFFBF5),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'Inter',
            scaffoldBackgroundColor: const Color(0xFF121312),
            cardColor: const Color(0xFF2D2418),
          ),
          themeMode: theme.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: taille,
              textScaler: TextScaler.linear(texte),
              viewInsets: viewInsets,
            ),
            child: IdentificationSlidePage(
              titre: pause ? 'Pause' : 'POINTAGE',
              sceneAsset: pause
                  ? 'assets/scenes/scene_pause.jpg'
                  : 'assets/scenes/scene_pointage.jpg',
              aide: pause
                  ? 'Pour démarrer ou reprendre une pause'
                  : 'Identifiez-vous pour pointer.',
              entrepriseId: 'entreprise-de-test',
              matriculePrefix: 'ENN',
              maquettePause: pause,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('La maquette Pause tient à 360×640 et 412×869', (tester) async {
    for (final taille in [const Size(360, 640), const Size(412, 869)]) {
      await _pomperIdentification(tester, taille);
      expect(tester.takeException(), isNull, reason: '$taille');
      for (final cle in [
        'pause-scene',
        'pause-frise',
        'pause-carte-identification',
        'pause-glisser-valider',
        'pause-motif-symbole',
        'pause-retour',
        'pause-pied',
      ]) {
        expect(find.byKey(Key(cle)), findsOneWidget, reason: '$taille / $cle');
      }

      final frise = tester.widget<FriseMotif>(find.byKey(
        const Key('pause-frise'),
      ));
      expect(frise.hauteur, 40);
      expect(frise.tuilee, isTrue);

      final carte = tester.getRect(
        find.byKey(const Key('pause-carte-identification')),
      );
      final retour = tester.getRect(find.byKey(const Key('pause-retour')));
      expect(carte.left, greaterThanOrEqualTo(0));
      expect(carte.right, lessThanOrEqualTo(taille.width));
      expect(carte.bottom, lessThanOrEqualTo(retour.top + 0.5),
          reason: '$taille : la carte ne doit pas passer sous le pied');

      final champs = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(champs, hasLength(2));
      expect(champs.first.decoration?.prefixText, isNull);
      final prefixe = champs.first.decoration?.prefix;
      expect(prefixe, isA<Text>());
      expect((prefixe! as Text).data, 'ENN-');
      expect(champs.first.keyboardType, TextInputType.number);
      expect(champs.last.obscureText, isTrue);

      final palette = AccueilPalette.pour(MotifCulturel.adinkra, false);
      final glisseur = tester.widget<SlideValider>(
        find.byKey(const Key('pause-glisser-valider')),
      );
      expect(glisseur.fond, palette.primaire);
      expect(glisseur.texte, palette.surPrimaire);
      expect(glisseur.bouton, palette.cerclePrimaire);
      expect(glisseur.icone, palette.iconePrimaire);
    }
  });

  testWidgets('Pause utilise une seule commande de thème, toujours fonctionnelle',
      (tester) async {
    final service = await _pomperIdentification(
      tester,
      const Size(360, 640),
    );
    final bouton = find.byKey(const Key('pause-theme'));
    expect(bouton, findsOneWidget);
    expect(
      find.descendant(of: bouton, matching: find.byIcon(Icons.dark_mode)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.light_mode), findsNothing);

    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(service.isDarkMode, isTrue);
    expect(
      find.descendant(of: bouton, matching: find.byIcon(Icons.light_mode)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Petit écran et clavier : les champs restent utilisables',
      (tester) async {
    await _pomperIdentification(
      tester,
      const Size(320, 568),
      texte: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byKey(const Key('pause-glisser-valider')), findsOneWidget);

    await _pomperIdentification(
      tester,
      const Size(360, 640),
      viewInsets: const EdgeInsets.only(bottom: 280),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('pause-scene')), findsNothing);
    expect(find.byKey(const Key('pause-frise')), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byKey(const Key('pause-glisser-valider')), findsOneWidget);
  });

  testWidgets('Le pointage garde son ancienne variante visuelle', (tester) async {
    await _pomperIdentification(
      tester,
      const Size(412, 869),
      pause: false,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('pause-scene')), findsNothing);
    expect(find.byKey(const Key('pause-carte-identification')), findsNothing);
    expect(find.byKey(const Key('pause-theme')), findsNothing);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    final champPointage = tester.widget<TextField>(find.byType(TextField).first);
    expect(champPointage.decoration?.prefixText, 'ENN-');
    expect(champPointage.decoration?.prefix, isNull);
    final glisseur = tester.widget<SlideValider>(find.byType(SlideValider));
    expect(glisseur.fond, isNull);
    expect(glisseur.bouton, isNull);
    expect(glisseur.icone, isNull);
  });
}

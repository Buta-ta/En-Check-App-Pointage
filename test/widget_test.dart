import 'package:en_check/widgets/accueil_maquette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bloc(String texte, Color couleur) {
  return ColoredBox(
    color: couleur,
    child: Center(
      child: Text(
        texte,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, height: 24 / 18),
      ),
    ),
  );
}

Future<void> _verifier(
  WidgetTester tester,
  Size taille, {
  double texte = 1,
  bool modes = true,
  bool annonces = false,
  bool alerte = false,
}) async {
  await tester.binding.setSurfaceSize(taille);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Inter'),
      home: MediaQuery(
        data: MediaQueryData(
          size: taille,
          textScaler: TextScaler.linear(texte),
        ),
        child: Scaffold(
          body: AccueilMaquette(
            entete: _bloc('En-Check\n9:19', const Color(0xFF3A686D)),
            salutation: _bloc('Mboté\nchez votre entreprise', Colors.white),
            cartesAction: _bloc(
              'Je commence mon service\nJe quitte mon poste',
              const Color(0xFFF6F4ED),
            ),
            aujourdhui: _bloc(
              "AUJOURD'HUI\nPrêt pour les pointages",
              Colors.white,
            ),
            autresModes: modes ? _bloc('Autres modes', Colors.white) : null,
            annonces:
                annonces ? _bloc('Annonces\nUne annonce', Colors.white) : null,
            alerteBorne: alerte ? _bloc('Borne à activer', Colors.amber) : null,
            navigation: const KeyedSubtree(
              key: Key('navigation-test'),
              child: ColoredBox(
                color: Color(0xFFF9F7F0),
                child: Center(child: Text('Accueil  Pause  Historique')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull, reason: '$taille, texte $texte');
  expect(find.byType(SingleChildScrollView), findsNothing);
  expect(find.byType(ListView), findsNothing);

  final navigation = tester.getRect(find.byKey(const Key('navigation-test')));
  expect(navigation.bottom, lessThanOrEqualTo(taille.height + 0.5));
  expect(navigation.top, greaterThanOrEqualTo(0));

  final cles = [
    'accueil-entete',
    'accueil-salutation',
    if (alerte) 'accueil-alerte',
    'accueil-actions',
    'accueil-aujourdhui',
    if (modes) 'accueil-autres',
    if (annonces) 'accueil-annonces',
  ];
  Rect? precedent;
  for (final cle in cles) {
    final rect = tester.getRect(find.byKey(Key(cle)));
    expect(rect.top, greaterThanOrEqualTo(-0.5), reason: cle);
    expect(rect.bottom, lessThanOrEqualTo(navigation.top + 0.5), reason: cle);
    expect(rect.left, greaterThanOrEqualTo(-0.5), reason: cle);
    expect(rect.right, lessThanOrEqualTo(taille.width + 0.5), reason: cle);
    if (precedent != null) {
      expect(rect.top + 0.5, greaterThanOrEqualTo(precedent.bottom),
          reason: '$cle chevauche le bloc précédent');
    }
    precedent = rect;
  }
}

void main() {
  testWidgets('Accueil maquette : zéro défilement et aucun bloc coupé',
      (tester) async {
    await _verifier(tester, const Size(412, 869));
    await _verifier(tester, const Size(360, 640));
    await _verifier(tester, const Size(360, 640), texte: 1.3);
    await _verifier(tester, const Size(390, 844), modes: false);
    await _verifier(tester, const Size(800, 1280));
    await _verifier(tester, const Size(1366, 768));
    await _verifier(tester, const Size(320, 568),
        texte: 1.3, annonces: true, alerte: true);
    await _verifier(tester, const Size(360, 480),
        texte: 1.3, annonces: true, alerte: true);
  });
}

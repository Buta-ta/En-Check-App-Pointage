import 'package:en_check/widgets/carrousel_annonces_accueil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sans annonce, la photo locale reste dans un cadre 16:9',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: CarrouselAnnoncesAccueil(
              entrepriseId: 'enterprise-a',
              annonces: [],
            ),
          ),
        ),
      ),
    ));

    final cadre = tester.getSize(find.byType(AspectRatio));
    expect(cadre.width / cadre.height, closeTo(16 / 9, 0.001));
    expect(find.byKey(const ValueKey('photo-locale-accueil')), findsOneWidget);
    expect(find.bySemanticsLabel('Photo d’accueil En-Check'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

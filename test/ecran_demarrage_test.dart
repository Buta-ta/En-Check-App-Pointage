import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:en_check/widgets/ecran_demarrage.dart';

void main() {
  testWidgets('affiche la marque et le statut de chargement prolongé', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: EcranDemarrage(chargementLong: true),
    ));

    expect(find.text('En-Check'), findsOneWidget);
    expect(find.text('Chargement…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reste lisible avec la réduction des animations activée', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: EcranDemarrage(),
      ),
    ));

    expect(find.text('En-Check'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('le splash superposé ne bloque pas l’action de l’application', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: ElevatedButton(
              onPressed: () => pressed = true,
              child: const Text('Action accueil'),
            ),
          ),
          const EcranDemarrage(superpose: true),
        ],
      ),
    ));

    await tester.tap(find.text('Action accueil'));
    expect(pressed, isTrue);
  });

  testWidgets('s adapte à une fenêtre étroite', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: EcranDemarrage()));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('En-Check'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

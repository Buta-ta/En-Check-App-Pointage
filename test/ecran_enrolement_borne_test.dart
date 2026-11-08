import 'package:en_check/widgets/ecran_enrolement_borne.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('le retour à l’accueil est toujours visible et fonctionnel',
      (tester) async {
    var retourDemande = false;
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: EcranEnrolementBorne(
          nomEmploye: 'Aminata Kone',
          matricule: 'EN-104',
          index: 0,
          total: 3,
          onRetourAccueil: () => retourDemande = true,
          onCommencer: () {},
        ),
      ),
    );

    final erreurRendu = tester.takeException();
    expect(erreurRendu, isNull, reason: 'Erreur pendant le rendu: $erreurRendu');
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Enrôler un employé'), findsOneWidget);
    expect(find.text('Aminata Kone'), findsOneWidget);
    expect(find.text('Employé 1 sur 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retour-accueil-enrolement')));
    expect(retourDemande, isTrue);
  });

  testWidgets('le bouton pour passer au pointage reste optionnel',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EcranEnrolementBorne(
          nomEmploye: 'Aminata Kone',
          matricule: 'EN-104',
          index: 1,
          total: 3,
          onRetourAccueil: () {},
          onCommencer: () {},
          onPasser: () {},
        ),
      ),
    );

    expect(find.text('Terminer pour l’instant et aller au pointage'),
        findsOneWidget);
  });
}

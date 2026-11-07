import 'package:en_check/widgets/ma_journee_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _employeTest = <String, dynamic>{
  'id': 'employe-fictif-recette',
  'first_name': 'Test',
  'last_name': 'Recette',
};

Future<void> _ouvrirDialog(
  WidgetTester tester, {
  String prefixe = 'ENN',
  required Future<ResultatVerificationJournee> Function(String, String) verifier,
  required void Function(Map<String, dynamic>?) apresFermeture,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final resultat = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => MaJourneeDialog(
                  prefixeEntreprise: prefixe,
                  verifier: verifier,
                ),
              );
              apresFermeture(resultat);
            },
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('placeholders vides, PIN masqué, focus clavier et actions accessibles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? matriculeVerifie;
    String? pinVerifie;
    Map<String, dynamic>? resultatDialog;

    await _ouvrirDialog(
      tester,
      verifier: (matricule, pin) async {
        matriculeVerifie = matricule;
        pinVerifie = pin;
        return const ResultatVerificationJournee.reussite(_employeTest);
      },
      apresFermeture: (resultat) => resultatDialog = resultat,
    );

    expect(find.text('MA JOURNÉE'), findsOneWidget);
    expect(find.text(
      'Saisissez votre matricule et votre PIN pour consulter vos pointages du jour. Aucun pointage ne sera enregistré.',
    ), findsOneWidget);
    expect(find.text('Ex. 0002'), findsOneWidget);
    expect(find.text('Ex. 1234'), findsOneWidget);
    expect(find.text('ENN-'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('ma-journee-matricule'))).controller!.text, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('ma-journee-pin'))).controller!.text, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('ma-journee-matricule'))).focusNode!.hasFocus, isFalse);
    expect(tester.widget<TextField>(find.byKey(const Key('ma-journee-pin'))).obscureText, isTrue);
    expect(find.text('ANNULER'), findsOneWidget);
    expect(find.text('CONSULTER'), findsOneWidget);

    final matricule = find.byKey(const Key('ma-journee-matricule'));
    final pin = find.byKey(const Key('ma-journee-pin'));
    final champMatricule = tester.widget<TextField>(matricule);
    expect(champMatricule.keyboardType, TextInputType.text);
    expect(champMatricule.textCapitalization, TextCapitalization.characters);
    expect(champMatricule.autocorrect, isFalse);
    expect(champMatricule.textInputAction, TextInputAction.next);

    await tester.tap(matricule);
    await tester.enterText(matricule, '0002');
    await tester.enterText(matricule, '');
    expect(find.text('ENN-'), findsOneWidget);
    await tester.enterText(matricule, '0002');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(tester.widget<TextField>(pin).focusNode!.hasFocus, isTrue);

    final champPin = tester.widget<TextField>(pin);
    expect(champPin.keyboardType, TextInputType.number);
    expect(champPin.textInputAction, TextInputAction.done);
    await tester.enterText(pin, '1234');
    // Le finder Flutter inspecte la valeur interne d'EditableText même quand
    // obscureText est actif : on vérifie donc le mode masqué du champ lui-même.
    expect(tester.widget<TextField>(pin).obscureText, isTrue);

    // Simule le clavier ouvert sur un petit téléphone : les deux actions
    // restent au-dessus de la zone occupée par le clavier.
    // viewInsets est exprimé en pixels physiques par TestFlutterView.
    const hauteurClavierLogique = 280.0;
    tester.view.viewInsets = FakeViewPadding(
      bottom: hauteurClavierLogique * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();
    final limiteClavier = tester.view.physicalSize.height /
            tester.view.devicePixelRatio -
        hauteurClavierLogique;
    expect(tester.getRect(find.text('ANNULER')).bottom, lessThanOrEqualTo(limiteClavier));
    expect(tester.getRect(find.byKey(const Key('ma-journee-consulter'))).bottom,
        lessThanOrEqualTo(limiteClavier));

    // L'action Terminé du clavier, comme Entrée sur un clavier physique,
    // consulte sans créer de pointage.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(matriculeVerifie, 'ENN-0002');
    expect(pinVerifie, '1234');
    expect(resultatDialog?['id'], 'employe-fictif-recette');
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('le préfixe de l’entreprise active reste fixe et entre dans le matricule',
      (tester) async {
    String? matriculeVerifie;
    await _ouvrirDialog(
      tester,
      prefixe: 'ACME-',
      verifier: (matricule, _) async {
        matriculeVerifie = matricule;
        return const ResultatVerificationJournee.reussite(_employeTest);
      },
      apresFermeture: (_) {},
    );

    final champ = find.byKey(const Key('ma-journee-matricule'));
    expect(find.text('ACME-'), findsOneWidget);
    expect(find.text('Ex. 0002'), findsOneWidget);
    await tester.enterText(champ, '0042');
    await tester.enterText(find.byKey(const Key('ma-journee-pin')), '5678');
    await tester.tap(find.byKey(const Key('ma-journee-consulter')));
    await tester.pumpAndSettle();
    expect(matriculeVerifie, 'ACME-0042');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ANNULER ferme la modale, efface les saisies et ne vérifie pas',
      (tester) async {
    var nombreVerifications = 0;
    Map<String, dynamic>? resultatDialog = _employeTest;
    late TextEditingController matriculeController;
    late TextEditingController pinController;

    await _ouvrirDialog(
      tester,
      verifier: (_, __) async {
        nombreVerifications++;
        return const ResultatVerificationJournee.reussite(_employeTest);
      },
      apresFermeture: (resultat) => resultatDialog = resultat,
    );

    matriculeController = tester
        .widget<TextField>(find.byKey(const Key('ma-journee-matricule')))
        .controller!;
    pinController = tester
        .widget<TextField>(find.byKey(const Key('ma-journee-pin')))
        .controller!;
    await tester.enterText(find.byKey(const Key('ma-journee-matricule')), '0002');
    await tester.enterText(find.byKey(const Key('ma-journee-pin')), '1234');
    await tester.tap(find.text('ANNULER'));
    await tester.pumpAndSettle();
    expect(nombreVerifications, 0);
    expect(matriculeController.text, isEmpty);
    expect(pinController.text, isEmpty);
    expect(resultatDialog, isNull);
    expect(find.text('MA JOURNÉE'), findsNothing);
  });
}

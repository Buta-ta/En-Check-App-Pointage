import 'package:en_check/services/motif_service.dart';
import 'package:en_check/widgets/panneau_motif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Apparence présente le motif sans provenance non vérifiée',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final motifInitial = MotifService.actif.value;
    MotifService.actif.value = MotifCulturel.adinkra;
    addTearDown(() => MotifService.actif.value = motifInitial);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => ouvrirPanneauMotif(context),
            child: const Text('Ouvrir Apparence'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Ouvrir Apparence'));
    await tester.pumpAndSettle();

    expect(find.text('Apparence'), findsOneWidget);
    expect(find.text('Motif d’interface'), findsOneWidget);
    expect(find.text('Motif textile géométrique'), findsOneWidget);
    expect(find.byKey(const Key('apparence-a-propos-motif')), findsOneWidget);

    await tester.tap(find.byKey(const Key('apparence-a-propos-motif')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('À propos du motif'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Aucune tradition ni provenance géographique'),
        findsOneWidget);
    expect(find.textContaining('Ghana'), findsNothing);
    expect(find.textContaining('À documenter'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

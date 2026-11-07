import 'package:en_check/services/motif_service.dart';
import 'package:en_check/widgets/panneau_motif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Apparence et À propos identifient le peuple et le pays du motif',
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
    expect(find.text('Motif d’interface'), findsNWidgets(2));
    expect(find.text('Adinkra'), findsWidgets);
    expect(find.textContaining('Akan (notamment Asante)'), findsWidgets);
    expect(find.textContaining('Ghana'), findsWidgets);
    expect(find.byKey(const Key('apparence-a-propos-motif')), findsOneWidget);

    await tester.tap(find.byKey(const Key('apparence-a-propos-motif')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('À propos du motif Adinkra'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Peuple : Akan (notamment Asante)'),
        findsOneWidget);
    expect(find.textContaining('Pays : Ghana'), findsOneWidget);
    expect(find.textContaining('interprétation graphique inspirée'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('le panneau met à jour la provenance du motif sélectionné',
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
    await tester.tap(find.text('Bogolan').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Bamana (Bambara)'), findsWidgets);
    expect(find.textContaining('Mali'), findsWidgets);

    await tester.tap(find.byKey(const Key('apparence-a-propos-motif')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Peuple : Bamana (Bambara)'), findsOneWidget);
    expect(find.textContaining('Pays : Mali'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

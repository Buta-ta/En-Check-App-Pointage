import 'dart:io';

import 'package:en_check/screens/historique_screen.dart';
import 'package:en_check/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Box<dynamic> pointagesPending;
  late Directory repertoire;

  setUpAll(() async {
    repertoire = await Directory.systemTemp.createTemp('en-check-historique-');
    Hive.init(repertoire.path);
    pointagesPending = await Hive.openBox<dynamic>('pointages_pending');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await repertoire.exists()) await repertoire.delete(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ConnectivityService.setOnlineForTest(false);
    await pointagesPending.clear();
  });

  testWidgets('affiche une seule ligne chronologique par événement et filtre le jour choisi',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final maintenant = DateTime.now();
    final debut = DateTime(maintenant.year, maintenant.month, maintenant.day, 8);
    await pointagesPending.add({
      'employee_id': 'employe-test-historique',
      'enterprise_id': 'entreprise-test-historique',
      'check_type': 'in',
      'check_time': debut.toIso8601String(),
      'client_ref': 'capture-test-entree',
    });
    await pointagesPending.add({
      'employee_id': 'employe-test-historique',
      'enterprise_id': 'entreprise-test-historique',
      'check_type': 'out',
      'check_time': debut.add(const Duration(hours: 1)).toIso8601String(),
      'client_ref': 'capture-test-sortie',
    });
    await pointagesPending.add({
      'employee_id': 'employe-test-historique',
      'enterprise_id': 'entreprise-test-historique',
      'check_type': 'in',
      'check_time': 'date-invalide',
      'client_ref': 'capture-test-date-inconnue',
    });

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Inter'),
      home: const HistoriqueScreen(employee: {
        'id': 'employe-test-historique',
        'enterprise_id': 'entreprise-test-historique',
        'first_name': 'Employé',
        'last_name': 'Test',
        'matricule': 'TEST-0001',
      }),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historique-evenement-0')), findsOneWidget);
    expect(find.byKey(const Key('historique-evenement-1')), findsOneWidget);
    expect(find.byKey(const Key('historique-evenement-inconnu-0')), findsOneWidget);
    expect(find.byKey(const Key('historique-evenements-date-inconnue')), findsOneWidget);
    expect(find.text('Entrée'), findsNWidgets(2));
    expect(find.text('Sortie'), findsOneWidget);
    expect(find.textContaining('Service en cours depuis'), findsNothing);
    expect(find.text('En attente de synchronisation'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('historique-bouton-calendrier')));
    await tester.pumpAndSettle();
    final hier = DateTime(maintenant.year, maintenant.month, maintenant.day - 1);
    final celluleHier = find.descendant(
      of: find.byType(CalendarDatePicker),
      matching: find.text('${hier.day}'),
    ).last;
    expect(celluleHier, findsOneWidget);
    await tester.tap(celluleHier);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CHOISIR'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aucun pointage le'), findsOneWidget);
    expect(find.byTooltip("Revenir à aujourd'hui"), findsOneWidget);

    await tester.tap(find.byTooltip("Revenir à aujourd'hui"));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('historique-evenement-0')), findsOneWidget);
    expect(find.byKey(const Key('historique-evenement-1')), findsOneWidget);
  });
}

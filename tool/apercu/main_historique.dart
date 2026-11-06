import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:en_check/screens/historique_screen.dart';
import 'package:en_check/services/motif_service.dart';

/// Point d'entrée isolé de recette visuelle : données fictives, hors-ligne,
/// sans accès Supabase. N'est jamais utilisé par l'application distribuée.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final pointages = await Hive.openBox<dynamic>('pointages_pending');
  await pointages.clear();

  const employeeId = 'preview-employee-0001';
  const enterpriseId = 'preview-enterprise-0001';
  final maintenant = DateTime.now();
  final entree = DateTime(maintenant.year, maintenant.month, maintenant.day, 8, 12);
  await pointages.add({
    'employee_id': employeeId,
    'enterprise_id': enterpriseId,
    'check_type': 'in',
    'check_time': entree.toIso8601String(),
    'client_ref': 'preview-entry-001',
  });
  await pointages.add({
    'employee_id': employeeId,
    'enterprise_id': enterpriseId,
    'check_type': 'out',
    'check_time': entree.add(const Duration(hours: 3, minutes: 16)).toIso8601String(),
    'client_ref': 'preview-exit-001',
  });
  await pointages.add({
    'employee_id': employeeId,
    'enterprise_id': enterpriseId,
    'check_type': 'in',
    'check_time': entree.add(const Duration(hours: 4, minutes: 2)).toIso8601String(),
    'client_ref': 'preview-entry-002',
  });

  final preferences = await SharedPreferences.getInstance();
  await preferences.setString('enterprise_name', 'Atelier de démonstration');
  await MotifService.charger();

  runApp(const _ApercuHistorique());
}

class _ApercuHistorique extends StatelessWidget {
  const _ApercuHistorique();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          fontFamily: 'Inter',
          scaffoldBackgroundColor: const Color(0xFFF5F2EA),
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF22474D),
            surface: Color(0xFFF8F7F2),
          ),
        ),
        home: const HistoriqueScreen(employee: {
          'id': 'preview-employee-0001',
          'enterprise_id': 'preview-enterprise-0001',
          'first_name': 'Employé',
          'last_name': 'Démonstration',
          'matricule': 'DEMO-0042',
          'position': 'Équipe de recette',
          'department': 'Atelier de démonstration',
        }),
      );
}

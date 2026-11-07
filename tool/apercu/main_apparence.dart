import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:en_check/services/motif_service.dart';
import 'package:en_check/widgets/panneau_motif.dart';

/// Recette Android locale : panneau Apparence, sans réseau ni données réelles.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('checklist_motif_choisi', true);
  await prefs.setBool('checklist_premier_pointage', true);
  await MotifService.charger();
  runApp(const _ApercuApparence());
}

class _ApercuApparence extends StatelessWidget {
  const _ApercuApparence();

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
        home: const _EcranApparence(),
      );
}

class _EcranApparence extends StatefulWidget {
  const _EcranApparence();

  @override
  State<_EcranApparence> createState() => _EcranApparenceState();
}

class _EcranApparenceState extends State<_EcranApparence> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ouvrirPanneauMotif(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Recette locale — Apparence')),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:en_check/screens/identification_slide_page.dart';
import 'package:en_check/screens/public_start_screen.dart';
import 'package:en_check/services/motif_service.dart';
import 'package:en_check/services/theme_service.dart';

/// Recette Android locale : l'écran d'entrée et son parcours d'identification
/// sont fictifs, sans Supabase et sans enregistrement de pointage.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MotifService.charger();
  runApp(ChangeNotifierProvider(
    create: (_) => ThemeService(),
    child: const _ApercuEntree(),
  ));
}

class _ApercuEntree extends StatelessWidget {
  const _ApercuEntree();

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
        home: Builder(
          builder: (racine) => PublicStartScreen(
            onCommencer: () => Navigator.of(racine).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => IdentificationSlidePage(
                  titre: 'POINTAGE',
                  sceneAsset: 'assets/scenes/scene_pointage.jpg',
                  aide: 'Identifiez-vous pour pointer.',
                  entrepriseId: 'entreprise-fictive-recette',
                  matriculePrefix: 'TST',
                  maquettePointage: true,
                  onAccueil: () => Navigator.of(racine)
                      .popUntil((route) => route.isFirst),
                ),
              ),
            ),
          ),
        ),
      );
}

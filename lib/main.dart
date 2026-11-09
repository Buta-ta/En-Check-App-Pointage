import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/pointage_screen.dart';
import 'screens/public_start_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/public_start_service.dart';
import 'services/supabase_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/face_recognition_service_provider.dart';
import 'services/trusted_punch_service.dart';
import 'widgets/cadre_motif.dart';
import 'widgets/ecran_demarrage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Le premier rendu Flutter arrive avant Hive, Supabase et Connectivity :
  // aucune initialisation asynchrone ne laisse désormais l'écran système blanc.
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: const _BootstrapApp(),
    ),
  );
}

Future<void> _initialiserServices() async {
  await Hive.initFlutter();
  for (final box in <String>[
    'pointages_pending', 'employees_cache', 'enterprises_cache',
    'employee_schedules_cache', 'face_embeddings', 'face_config',
    'face_enrollment_status',
  ]) {
    await Hive.openBox(box);
  }

  await TrustedPunchService.initialiser();
  await SupabaseService.initialize();
  try {
    await ConnectivityService.initialize();
  } catch (error) {
    // Le plugin de connectivité est indicatif : son indisponibilité ne doit
    // pas empêcher le pointage, qui peut fonctionner hors-ligne.
    print('⚠️ État réseau non disponible au démarrage: $error');
  }
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late Future<void> _services;
  bool _chargementLong = false;

  @override
  void initState() {
    super.initState();
    _services = _initialiserServices();
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted && !_servicesEstPret) setState(() => _chargementLong = true);
    });
  }

  bool _servicesEstPret = false;

  void _relancer() {
    setState(() {
      _servicesEstPret = false;
      _chargementLong = false;
      _services = _initialiserServices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeService>(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: theme.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: FutureBuilder<void>(
        future: _services,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErreurDemarrage(onRetry: _relancer);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return EcranDemarrage(chargementLong: _chargementLong);
          }
          if (!_servicesEstPret) {
            _servicesEstPret = true;
            // Ces traitements restent non bloquants et le pointage apparaît
            // dès que les services locaux essentiels sont initialisés.
            FaceRecognitionService.initialiser().then((success) {
              print(success
                  ? '✅ FaceRecognitionService prêt'
                  : '⚠️ FaceRecognitionService non disponible');
            }).catchError((Object e) {
              print('⚠️ FaceRecognitionService non disponible: $e');
            });
            TrustedPunchService.contacterServeur();
            SyncService.synchroniserAutomatique().catchError((Object e) {
              print('❌ Synchronisation de démarrage échouée: $e');
            });
          }
          return const EnCheckApp();
        },
      ),
    );
  }
}

class _ErreurDemarrage extends StatelessWidget {
  const _ErreurDemarrage({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/logo_encheck.png', width: 100, height: 100),
          const SizedBox(height: 20),
          const Text('Le démarrage a rencontré un problème.', textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ]),
      ),
    ),
  );
}

class EnCheckApp extends StatefulWidget {
  const EnCheckApp({super.key});

  @override
  State<EnCheckApp> createState() => _EnCheckAppState();
}

class _EnCheckAppState extends State<EnCheckApp> {
  bool _isLoading = true;
  bool _hasEnterprise = false;
  bool _afficherEcranCommencer = false;

  @override
  void initState() {
    super.initState();
    _verifierConfiguration();
  }

  Future<void> _verifierConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final enterpriseId = prefs.getString('enterprise_id');
    final hasEnterprise = enterpriseId != null && enterpriseId.isNotEmpty;
    final afficherCommencer = enterpriseId != null &&
        enterpriseId.isNotEmpty &&
        !await PublicStartService.estDejaUtilise(enterpriseId);

    if (!mounted) return;
    setState(() {
      _hasEnterprise = hasEnterprise;
      _afficherEcranCommencer = afficherCommencer;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: const EcranDemarrage(chargementLong: true),
      );
    }

    return MaterialApp(
      title: 'En-Check',
      debugShowCheckedModeBanner: false,
      routes: {
        '/pointage': (_) => const PointageScreen(),
        '/welcome': (_) => const WelcomeScreen(),
      },
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          CadreMotif(child: child ?? const SizedBox.shrink()),
      home: !_hasEnterprise
          ? const WelcomeScreen()
          : _afficherEcranCommencer
              ? const PublicStartScreen()
              : const PointageScreen(),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: 'Inter',
      primarySwatch: Colors.amber,
      scaffoldBackgroundColor: const Color(0xFFF5F2E9),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF3D2B1F),
        foregroundColor: Color(0xFFFFFBF5),
      ),
      cardColor: const Color(0xFFFFFBF5),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF8B6914),
        secondary: Color(0xFFD4AF37),
        surface: Color(0xFFFFFBF5),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      primarySwatch: Colors.amber,
      scaffoldBackgroundColor: const Color(0xFF121312),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2D2418),
        foregroundColor: Color(0xFFFFFBF5),
      ),
      cardColor: const Color(0xFF2D2418),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFD4AF37),
        secondary: Color(0xFFE5C158),
        surface: Color(0xFF2D2418),
      ),
    );
  }
}
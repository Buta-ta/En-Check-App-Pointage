import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/pointage_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/supabase_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/face_recognition_service_provider.dart';
import 'services/trusted_punch_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ INIT HIVE
  await Hive.initFlutter();

  // Boîtes existantes
  await Hive.openBox('pointages_pending');
  await Hive.openBox('employees_cache');
  await Hive.openBox('enterprises_cache');
  await Hive.openBox('employee_schedules_cache');

  // 🤖 Nouvelles boîtes reconnaissance faciale
  await Hive.openBox('face_embeddings');
  await Hive.openBox('face_config');
  await Hive.openBox('face_enrollment_status');

  // 🕐 LIVRAISON 09 : horloge de confiance (identifiant d'appareil + ancrage)
  await TrustedPunchService.initialiser();

  await SupabaseService.initialize();

  await ConnectivityService.initialize();

  // Initialiser le service de reconnaissance faciale en arrière-plan
  FaceRecognitionService.initialiser().then((success) {
    if (success) {
      print('✅ FaceRecognitionService prêt');
    } else {
      print('⚠️ FaceRecognitionService non disponible');
    }
  });

  // 🕐 LIVRAISON 09 : prendre l'heure du serveur dès qu'on le peut.
  //    Plus l'ancrage est frais, plus les pointages hors-ligne sont datés juste.
  TrustedPunchService.contacterServeur();

  // L'interface démarre TOUT DE SUITE.
  //
  // La synchronisation passait ici, avec un `await`, avant runApp() : le
  // premier pixel n'apparaissait donc qu'après le téléchargement de toutes
  // les entreprises actives puis de tous leurs employés. Sur une tablette de
  // pharmacie en 4G, c'était un écran blanc de plusieurs secondes — d'autant
  // que ce volume ne concerne pas l'appareil, qui n'a besoin que de sa propre
  // entreprise.
  //
  // On affiche d'abord, on synchronise ensuite. EnCheckApp a déjà son propre
  // état de chargement, et chaque écran recharge ses données de son côté :
  // rien n'attend la fin de la synchronisation pour s'afficher.
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: const EnCheckApp(),
    ),
  );

  // Synchronisation automatique au démarrage — en arrière-plan.
  // `.catchError` parce qu'une Future non attendue qui lève perd son erreur.
  SyncService.synchroniserAutomatique().catchError((Object e) {
    print('❌ Synchronisation de démarrage échouée: $e');
  });
}

class EnCheckApp extends StatefulWidget {
  const EnCheckApp({super.key});

  @override
  State<EnCheckApp> createState() => _EnCheckAppState();
}

class _EnCheckAppState extends State<EnCheckApp> {
  bool _isLoading = true;
  bool _hasEnterprise = false;

  @override
  void initState() {
    super.initState();
    _verifierConfiguration();
  }

  Future<void> _verifierConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final enterpriseId = prefs.getString('enterprise_id');

    setState(() {
      _hasEnterprise = enterpriseId != null;
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
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'En-Check',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: _hasEnterprise ? const PointageScreen() : const WelcomeScreen(),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: 'Poppins',
      primarySwatch: Colors.amber,
      scaffoldBackgroundColor: const Color(0xFFF6EFE3),
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
      fontFamily: 'Poppins',
      primarySwatch: Colors.amber,
      scaffoldBackgroundColor: const Color(0xFF1C1814),
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
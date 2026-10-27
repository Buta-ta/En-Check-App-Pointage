// lib/services/appareil_service.dart
// ═══════════════════════════════════════════════════════════
// 📱 MODE DE L'APPAREIL — choisi à l'accueil
// ═══════════════════════════════════════════════════════════
//
//  • Mode privé  (défaut) : téléphone personnel, usage normal.
//  • Mode kiosque         : cet appareil est une borne (tablette partagée).
//      → après connexion, l'écran de pointage se comporte en mode borne
//        (bandeau 🖥 Borne, etc.), même sans bail `bk1_` ni config serveur.
//
//  Le choix est enregistré sur l'appareil (shared_preferences).
// ═══════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';

class AppareilService {
  static const String _cle = 'mode_appareil';

  static const String prive = 'prive';
  static const String kiosque = 'kiosque';

  /// Mode courant de l'appareil — « privé » par défaut.
  static Future<String> mode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cle) ?? prive;
  }

  static Future<void> definirMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, mode);
  }

  static Future<bool> estKiosque() async {
    return (await mode()) == kiosque;
  }
}

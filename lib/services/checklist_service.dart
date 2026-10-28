// lib/services/checklist_service.dart
// ═══════════════════════════════════════════════════════════
// 🧭 CHECKLIST DE DÉMARRAGE + TUTORIEL
// ═══════════════════════════════════════════════════════════
//
//  Première ouverture de l'app : le tutoriel en 3 écrans joue
//  une seule fois par appareil. Ensuite, la petite checklist
//  « Démarrage » guide le client (motif choisi + premier
//  pointage) puis disparaît toute seule.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChecklistService {
  static const String _cleTutoriel = 'tutoriel_vue_v1';
  static const String _cleMotif = 'checklist_motif_choisi';
  static const String _clePointage = 'checklist_premier_pointage';

  /// Les widgets écoutent ces notificateurs pour se repeindre.
  static final ValueNotifier<bool> motifChoisi = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> premierPointage = ValueNotifier<bool>(false);

  /// Vrai quand les 3 étapes sont faites (l'entreprise est déjà configurée).
  static bool get complete => motifChoisi.value && premierPointage.value;

  /// À charger au démarrage de l'écran principal.
  static Future<void> charger() async {
    final prefs = await SharedPreferences.getInstance();
    motifChoisi.value = prefs.getBool(_cleMotif) ?? false;
    premierPointage.value = prefs.getBool(_clePointage) ?? false;
  }

  static Future<void> marquerMotifChoisi() async {
    motifChoisi.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cleMotif, true);
  }

  static Future<void> marquerPremierPointage() async {
    premierPointage.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clePointage, true);
  }

  /// Le tutoriel n'a-t-il pas encore joué sur cet appareil ?
  static Future<bool> tutorielDejaVu() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cleTutoriel) ?? false;
  }

  static Future<void> marquerTutorielVu() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cleTutoriel, true);
  }
}

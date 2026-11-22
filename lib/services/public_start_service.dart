import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise, sur cet appareil, que l'écran « Commencer » a été utilisé pour
/// une entreprise donnée. Les identifiants d'entreprise ne sont pas secrets.
class PublicStartService {
  static const String _prefixeCle = 'public_start_utilise_v1_';

  static String _cle(String entrepriseId) => '$_prefixeCle$entrepriseId';

  static Future<bool> estDejaUtilise(String entrepriseId) async {
    if (entrepriseId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cle(entrepriseId)) ?? false;
  }

  static Future<void> marquerUtilise(String? entrepriseId) async {
    if (entrepriseId == null || entrepriseId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cle(entrepriseId), true);
  }
}

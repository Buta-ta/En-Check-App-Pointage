// lib/services/souhaits_service.dart
// ═══════════════════════════════════════════════════════════
// 🌍 SOUHAITS — le message de bienvenue dans la langue du pays
// ═══════════════════════════════════════════════════════════
//
//  Le pays vient de `enterprises.country_code` (ISO-3, ex. BEN, COG, SEN).
//  Chaque pays a son souhait dans sa langue nationale ; « Bienvenue »
//  sert de repli. On enrichit la liste au fil des pays rencontrés.
// ═══════════════════════════════════════════════════════════

class SouhaitsService {
  /// Souhait par code pays (ISO-3 ET ISO-2 acceptés, sans accents).
  static const Map<String, String> _parPays = {
    // Bénin — fon
    'BEN': 'Mi kwabo',
    'BJ': 'Mi kwabo',
    // Congo-Brazzaville & RDC — lingala
    'COG': 'Mboté',
    'CG': 'Mboté',
    'COD': 'Mboté',
    'CD': 'Mboté',
    // Sénégal — wolof
    'SEN': 'Dalal ak jamm',
    'SN': 'Dalal ak jamm',
    // Côte d'Ivoire — baoulé/akan
    'CIV': 'Akwaba',
    'CI': 'Akwaba',
    // Togo — éwé
    'TGO': 'Woezor',
    'TG': 'Woezor',
    // Cameroun
    'CMR': 'Karibu',
    'CM': 'Karibu',
    // Mali — bambara
    'MLI': 'I ni ce',
    'ML': 'I ni ce',
    // Burkina Faso — mooré
    'BFA': 'Wendkoom',
    'BF': 'Wendkoom',
    // Gabon — fang
    'GAB': 'M\'bolo',
    'GA': 'M\'bolo',
  };

  /// Le souhait à afficher pour un pays (repli : « Bienvenue »).
  static String souhait(String? pays) {
    if (pays == null) return 'Bienvenue';
    final normalise = pays
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '');
    if (normalise.isEmpty) return 'Bienvenue';
    return _parPays[normalise] ?? 'Bienvenue';
  }
}

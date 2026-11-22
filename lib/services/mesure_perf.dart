// lib/services/mesure_perf.dart
// ═══════════════════════════════════════════════════════════════════════════
//  ⏱  MESURE DE VITESSE — LOT 1 (22/11/2026)
// ═══════════════════════════════════════════════════════════════════════════
//
//  Le problème : « quand le pointage est validé, le modal se ferme vite mais
//  le retour à l'accueil est lent ». La conception validée le 22/11 impose :
//
//      • retour optimiste — budget < 0,5 s entre le geste et l'accueil ;
//      • MESURE p50/p95 — toute performance est signalée honnêtement,
//        jamais une estimation présentée comme une mesure.
//
//  Ce service range donc les durées réellement observées sur CETTE tablette,
//  dans une boîte Hive locale (les dernières 100 par nom, pour rester léger),
//  et en calcule p50/p95/max. Rien n'est envoyé nulle part : le fondateur lit
//  les chiffres via le diagnostic caché de l'accueil (appui long sur la carte
//  « AUJOURD'HUI »), et les journaux de l'application les impriment aussi.
//
//  RÈGLE D'HONNÊTETÉ : aucune valeur n'est jamais inventée, complétée ou
//  lissée. Pas de mesure = « pas encore de mesure ».
// ═══════════════════════════════════════════════════════════════════════════

import 'package:hive_flutter/hive_flutter.dart';

class MesurePerf {
  MesurePerf._(); // classe utilitaire : pas d'instance

  static const String _boxName = 'encheck_mesures_perf';

  /// Les dernières durées conservées par nom de mesure. Au-delà, les plus
  /// anciennes sont oubliées : la boîte reste petite, p50/p95 restent
  /// représentatifs des usages récents.
  static const int _maxParMesure = 100;

  /// Le budget du « retour à l'accueil » fixé par la conception validée.
  static const int budgetRetourAccueilMs = 500;

  static Future<Box> _boite() => Hive.openBox(_boxName);

  /// Enregistre une durée observée, en millisecondes. Jamais d'exception :
  /// une mesure n'a jamais le droit de casser un pointage.
  static Future<void> enregistrer(String nom, int millisecondes) async {
    try {
      if (millisecondes < 0) return;
      final box = await _boite();
      final brut = box.get(nom);
      final liste = <int>[
        if (brut is List) ...brut.whereType<int>(),
        millisecondes,
      ];
      while (liste.length > _maxParMesure) {
        liste.removeAt(0);
      }
      await box.put(nom, liste);
      print('⏱ $nom : $millisecondes ms');
    } catch (e) {
      print('⚠️ MesurePerf.enregistrer : $e');
    }
  }

  /// Le résumé d'une mesure : `{n, p50, p95, max, dernier}` ou `null` si
  /// aucune durée n'a encore été observée.
  static Future<Map<String, dynamic>?> resume(String nom) async {
    try {
      final box = await _boite();
      final brut = box.get(nom);
      if (brut is! List) return null;
      final valeurs = brut.whereType<int>().toList()..sort();
      if (valeurs.isEmpty) return null;

      int percentile(double p) {
        final index = ((valeurs.length - 1) * p).round();
        return valeurs[index.clamp(0, valeurs.length - 1)];
      }

      return {
        'nom': nom,
        'n': valeurs.length,
        'p50': percentile(0.50),
        'p95': percentile(0.95),
        'max': valeurs.last,
        'dernier': valeurs.last,
      };
    } catch (e) {
      print('⚠️ MesurePerf.resume : $e');
      return null;
    }
  }

  /// Tous les résumés connus, dans l'ordre alphabétique des noms.
  static Future<List<Map<String, dynamic>>> tousLesResumes() async {
    final box = await _boite();
    final noms = box.keys.map((k) => k.toString()).toList()..sort();
    final sorties = <Map<String, dynamic>>[];
    for (final nom in noms) {
      final r = await resume(nom);
      if (r != null) sorties.add(r);
    }
    return sorties;
  }

  /// Oublie toutes les mesures (bouton du diagnostic).
  static Future<void> reinitialiser() async {
    try {
      final box = await _boite();
      await box.clear();
    } catch (e) {
      print('⚠️ MesurePerf.reinitialiser : $e');
    }
  }
}

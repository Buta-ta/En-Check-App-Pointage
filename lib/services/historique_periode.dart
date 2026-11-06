import 'heure_pointage.dart';

/// Règles de sélection d'une date dans l'historique employé.
///
/// L'écran employé expose uniquement la fenêtre de sept jours déjà visible
/// dans le parcours existant (aujourd'hui et les six jours précédents).
/// Cette classe ne filtre ni ne modifie les données : elle borne seulement
/// le sélecteur de date.
class HistoriquePeriode {
  HistoriquePeriode._();

  static DateTime jour(DateTime date) => DateTime(date.year, date.month, date.day);

  static DateTime premierJourAutorise(DateTime maintenant) =>
      jour(maintenant).subtract(const Duration(days: 6));

  static bool autorise(DateTime date, DateTime maintenant) {
    final jourChoisi = jour(date);
    final aujourdHui = jour(maintenant);
    return !jourChoisi.isBefore(premierJourAutorise(aujourdHui)) &&
        !jourChoisi.isAfter(aujourdHui);
  }

  /// Filtre et trie uniquement les pointages du jour sélectionné, sans écrire
  /// ni dédupliquer les enregistrements source.
  static List<Map<String, dynamic>> pointagesDuJour(
      List<Map<String, dynamic>> pointages, DateTime date) {
    final cle = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return pointages
        .where((pointage) => HeurePointage.jourDePointage(pointage) == cle)
        .toList()
      ..sort(HeurePointage.parInstantCroissant);
  }

  /// Accepte le matricule complet ou son suffixe, sans utiliser la valeur
  /// d'exemple du champ comme donnée. Le préfixe vient de l'entreprise active.
  static String matriculeComplet(String saisie, String prefixe) {
    final propre = saisie.trim().toUpperCase();
    final prefixePropre = prefixe.trim().toUpperCase();
    if (prefixePropre.isEmpty || propre.startsWith('$prefixePropre-')) {
      return propre;
    }
    return '$prefixePropre-$propre';
  }
}

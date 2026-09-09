// ═══════════════════════════════════════════════════════════════════════════
//  🕐 HEURE DES POINTAGES — LIVRAISON 19 (fuseau, phase 2 : l'application)
// ═══════════════════════════════════════════════════════════════════════════
//
//  LE PROBLÈME RÉSOLU ICI
//
//  Un pointage voyage sous DEUX formes d'heure, et l'application les
//  mélangeait comme si c'était la même chose :
//
//    1. L'HEURE DU SERVEUR — « 2026-09-27T07:30:00+00:00 ». Elle est en UTC :
//       à Cotonou (UTC+1), un pointage de 08:30 s'écrit 07:30.
//    2. L'HEURE DU TÉLÉPHONE, pour un pointage encore en file d'attente —
//       « 2026-09-27T08:30:00.000 », sans « Z » ni décalage : c'est une heure
//       murale, déjà à l'heure locale de la tablette.
//
//  Dart ne les traite pas pareil : une chaîne AVEC décalage donne un instant
//  absolu (le monde entier est d'accord sur ce moment), une chaîne SANS
//  décalage est lue telle quelle, comme heure locale. Résultat, avant cette
//  livraison, l'application lisait une ligne du serveur en heure UTC :
//
//    • l'écran affichait « 07:30 » pour un pointage de 08:30 (1 h d'écart à
//      Cotonou et à Yaoundé, 2 h à Kigali, 0 h à Dakar — donc invisible au
//      Sénégal, ce qui a longtemps masqué le problème) ;
//    • la journée se découpait sur minuit UTC : un pointage de 00:30 heure
//      locale était rangé dans la veille, et le total d'heures de la journée
//      partait avec lui (les équipes de nuit étaient les premières touchées) ;
//    • à l'approche de minuit, un pointage de la soirée pouvait être étiqueté
//      « Hier » alors qu'il datait de quelques minutes.
//
//  CE QUI N'ÉTAIT PAS CASSÉ — et qu'on ne prétend donc pas « réparer »
//  ────────────────────────────────────────────────────────────────────────
//  Dart compare des INSTANTS et non des heures murales : les tris, l'écart
//  entre une entrée et une sortie et la recherche du dernier pointage étaient
//  déjà justes. Mais chacun le refaisait à sa façon, à cinq endroits
//  différents, et deux d'entre eux étaient fragiles :
//
//    • « le même pointage, à moins de 2 secondes près » : la tablette peut
//      avoir une horloge décalée de quelques secondes, alors que le serveur
//      date le pointage avec SA propre mesure (ancre + délai). Deux secondes,
//      c'était court — le doublon pouvait réapparaître après synchronisation ;
//    • un horodatage illisible faisait planter la lecture au lieu d'être
//      signalé.
//
//  Tout passe désormais par ce fichier : une seule règle, un seul endroit.
//
//  LA RÈGLE, DÉSORMAIS
//
//      • on COMPARE toujours des INSTANTS (UTC)   → instant(), parInstant…
//      • on AFFICHE toujours l'HEURE LOCALE       → heureDePointage()
//
//  ⭐ LIVRAISON 22 — L'HEURE DE L'ENTREPRISE
//  ─────────────────────────────────────────
//  L'application n'affiche plus forcément l'heure de la TABLETTE : dès que le
//  serveur a annoncé le fuseau officiel de l'entreprise (`enterprises.timezone`,
//  livraison 04), c'est CETTE heure qui est affichée partout — historique,
//  horloge de l'écran de pointage, découpage des journées.
//
//  Pourquoi c'est indispensable : une tablette réglée sur un autre fuseau
//  (appareil d'occasion, réglage d'usine, heure d'été européenne, Ramadan
//  marocain, poste déplacé) affichait une heure fausse sans que personne ne
//  s'en aperçoive.
//
//  Le décalage vient du SERVEUR, jamais d'un calcul local : c'est le seul qui
//  connaisse les règles de changement d'heure de chaque pays. Il est mémorisé,
//  donc il fonctionne aussi hors-ligne et après un redémarrage de l'application.
//
//  Et si la tablette n'est pas sur le bon fuseau, on le DIT à l'utilisateur, en
//  clair : « cette tablette avance de 1 h sur l'heure de l'entreprise ».
//
//  Ce fichier reste LE SEUL endroit où la conversion se fait : aucune autre
//  ligne de l'application ne convertit une heure.
// ═══════════════════════════════════════════════════════════════════════════

class HeurePointage {
  HeurePointage._(); // classe utilitaire : pas d'instance

  /// Deux pointages du même employé, du même type, séparés de moins de
  /// X secondes, sont LE MÊME pointage (utilisé seulement quand la référence
  /// d'origine `client_ref` n'est pas disponible des deux côtés).
  static const int toleranceDoublonSecondes = 5;

  /// Clé de journée utilisée quand l'horodatage est illisible.
  static const String jourInconnu = '0000-00-00';

  // ═══════════════════════════════════════════════════════════════════════
  //  LE FUSEAU DE L'ENTREPRISE — livraison 22
  // ═══════════════════════════════════════════════════════════════════════
  //  Renseigné par TrustedPunchService à partir de la réponse du serveur :
  //  c'est le seul à connaître les règles de changement d'heure.

  static String? _nomFuseauEntreprise;   // « Africa/Douala »
  static int?    _decalageEntreprise;    // +3600 : heure d'été comprise

  /// Règle le fuseau de l'entreprise (appelé par TrustedPunchService).
  ///
  ///   • décalage connu  → l'application affiche l'heure de L'ENTREPRISE,
  ///     où que soit installée la tablette ;
  ///   • décalage nul    → retour à l'heure de la tablette : c'est exactement
  ///     le comportement d'avant la livraison 22, sans aucune erreur.
  static void reglerFuseauEntreprise({String? nom, int? decalageSecondes}) {
    _decalageEntreprise = decalageSecondes;
    _nomFuseauEntreprise = decalageSecondes == null
        ? null
        : (nom != null && nom.trim().isNotEmpty ? nom.trim() : null);
  }

  /// L'application suit-elle le fuseau de l'entreprise ?
  static bool get suitLEntreprise => _decalageEntreprise != null;

  /// Le fuseau utilisé pour l'affichage, en clair (pour l'écran).
  static String get fuseauUtilise => _decalageEntreprise == null
      ? 'la tablette'
      : (_nomFuseauEntreprise ?? "l'entreprise");

  /// L'heure MURALE de l'entreprise pour un instant donné.
  ///
  /// ⚠️ Renvoie un `DateTime` dont les CHAMPS (heure, minute, jour) sont ceux
  /// de l'entreprise : on l'AFFICHE, on ne le compare jamais. Toute
  /// comparaison passe par [instant].
  /// Sans fuseau connu → l'heure locale de la tablette, comme avant la 22.
  static DateTime? heureLocale(DateTime? instant) {
    if (instant == null) return null;
    final d = _decalageEntreprise;
    if (d == null) return instant.toLocal();
    return instant.toUtc().add(Duration(seconds: d));
  }

  /// L'heure qu'il est MAINTENANT, du point de vue de l'entreprise.
  static DateTime maintenant() => heureLocale(DateTime.now().toUtc())!;

  /// L'écart entre le réglage de la tablette et le fuseau de l'entreprise.
  /// `null` tant que le fuseau de l'entreprise n'est pas connu.
  static int? get ecartAvecLaTabletteSecondes {
    final d = _decalageEntreprise;
    if (d == null) return null;
    return DateTime.now().timeZoneOffset.inSeconds - d;
  }

  /// La phrase à montrer quand la tablette n'est pas sur le bon fuseau.
  ///
  /// Renvoie `null` tant que tout va bien — et en dessous d'une minute d'écart,
  /// pour ne pas inquiéter pour rien.
  static String? avisEcartTablette() {
    final e = ecartAvecLaTabletteSecondes;
    if (e == null || e.abs() < 60) return null;
    final sens = e > 0 ? 'avance' : 'retarde';
    return '⚠️ Cette tablette $sens de ${dureeLisible(e.abs())} sur l\'heure '
        "de l'entreprise ($fuseauUtilise) — l'écran affiche l'heure de "
        "l'entreprise.";
  }

  /// « 1 h », « 1 h 30 », « 45 min », « 12 s » : un écart, dit simplement.
  static String dureeLisible(int secondes) {
    final s = secondes.abs();
    if (s < 60) return '$s s';
    if (s < 3600) return '${s ~/ 60} min';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return m == 0 ? '$h h' : '$h h $m';
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  L'INSTANT RÉEL — la seule chose sur laquelle on compare
  // ═══════════════════════════════════════════════════════════════════════

  /// L'instant réel d'un pointage.
  ///
  ///   1. `instant_utc` — posé à la mise en file d'attente (heure de l'ancre
  ///      serveur + délai mesuré au chronomètre monotone, livraison 09). C'est
  ///      la valeur la plus sûre : elle ne dépend d'AUCUN réglage du téléphone ;
  ///   2. sinon `check_time`, lu correctement : c'est la présence du décalage
  ///      (« Z », « +01:00 ») qui décide, pas l'apparence de la chaîne.
  ///
  /// Renvoie `null` si rien n'est lisible — jamais d'exception.
  static DateTime? instant(Map<String, dynamic> pointage) {
    final derive = pointage['instant_utc'];
    if (derive is String && derive.trim().isNotEmpty) {
      final d = DateTime.tryParse(derive.trim());
      if (d != null) return d.toUtc();
    }
    return instantDe(pointage['check_time']);
  }

  /// Convertit une chaîne ISO-8601 en instant absolu (UTC).
  /// Renvoie `null` si la chaîne est absente ou illisible.
  static DateTime? instantDe(Object? valeur) {
    if (valeur is! String) return null;
    final texte = valeur.trim();
    if (texte.isEmpty) return null;
    final d = DateTime.tryParse(texte);
    return d == null ? null : d.toUtc();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  L'AFFICHAGE — toujours l'heure locale de la tablette
  // ═══════════════════════════════════════════════════════════════════════

  /// « HH:MM:SS » à montrer à l'employé.
  static String heureDePointage(Map<String, dynamic> pointage) =>
      heureDe(instant(pointage));

  /// « HH:MM:SS » pour un instant déjà converti (`null` → « --:--:-- »).
  static String heureDe(DateTime? instant) {
    if (instant == null) return '--:--:--';
    final h = heureLocale(instant)!;
    return '${deux(h.hour)}:${deux(h.minute)}:${deux(h.second)}';
  }

  /// La journée à laquelle un pointage appartient, au format « AAAA-MM-JJ ».
  ///
  /// ⭐ Le découpage se fait sur minuit LOCAL — un pointage de 00:30 appartient
  /// bien à sa propre journée, et non à la veille comme avant.
  static String jourDePointage(Map<String, dynamic> pointage) {
    final d = instant(pointage);
    if (d == null) return jourInconnu;
    final l = heureLocale(d)!;
    return '${l.year.toString().padLeft(4, '0')}-${deux(l.month)}-${deux(l.day)}';
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LES TRI ET LES DOUBLONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Tri du plus ANCIEN au plus récent (rejeu d'une file d'attente).
  /// Une date illisible passe en dernier — elle n'est jamais « maintenant ».
  static int parInstantCroissant(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ia = instant(a);
    final ib = instant(b);
    if (ia == null && ib == null) return 0;
    if (ia == null) return 1;
    if (ib == null) return -1;
    return ia.compareTo(ib);
  }

  /// Tri du plus RÉCENT au plus ancien (affichage de l'historique).
  static int parInstantDecroissant(Map<String, dynamic> a, Map<String, dynamic> b) =>
      parInstantCroissant(b, a);

  /// Deux lignes désignent-elles LE MÊME pointage ?
  ///
  ///   1. `client_ref` tranche quand les deux côtés la portent : c'est la
  ///      référence créée au moment du pointage, une égalité exacte ;
  ///   2. sinon : même type, et même instant à quelques secondes près.
  static bool memePointage(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a['check_type'] != b['check_type']) return false;

    final refA = a['client_ref'];
    final refB = b['client_ref'];
    if (refA is String && refA.isNotEmpty && refB is String && refB.isNotEmpty) {
      return refA == refB;
    }

    final ia = instant(a);
    final ib = instant(b);
    if (ia == null || ib == null) return false;
    return ia.difference(ib).inSeconds.abs() <= toleranceDoublonSecondes;
  }

  /// « 7 » → « 07 ».
  static String deux(int valeur) => valeur.toString().padLeft(2, '0');
}

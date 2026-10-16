// ═══════════════════════════════════════════════════════════════════════════
//  🕐 HORLOGE DE CONFIANCE — LIVRAISON 09
// ═══════════════════════════════════════════════════════════════════════════
//
//  LE PROBLÈME RÉSOLU ICI
//
//  Avant, l'application envoyait l'heure de son propre téléphone :
//
//      'check_time': DateTime.now().toIso8601String()
//
//  Un employé pouvait donc reculer l'horloge de son téléphone et antidater
//  son pointage. Toute la valeur probante du système s'effondrait.
//
//  PRINCIPE
//
//  L'application ne CHOISIT plus l'heure. Elle DÉCLARE seulement :
//      « ce pointage a eu lieu X secondes après ma dernière ancre serveur »
//  et le serveur décide de la date réelle.
//
//  COMMENT LE TÉLÉPHONE PEUT-IL PROUVER X SANS ÊTRE CRU SUR PAROLE ?
//
//  Grâce à un CHRONOMÈTRE MONOTONE (Stopwatch), qui ne recule jamais — même
//  quand l'utilisateur change l'heure du système. On l'ancre sur l'heure du
//  serveur à chaque contact réussi, puis on mesure l'écart en secondes.
//
//  ⚠️ HONNÊTETÉ SUR LES LIMITES
//
//  Ce chronomètre redémarre à zéro quand l'application redémarre. Dans ce
//  cas, `ecouleSecondes()` renvoie null et le pointage est daté MAINTENANT —
//  jamais dans le passé. C'est prudent, mais cela reste une approximation.
//
//  L'ANCRE — POURQUOI ELLE EST INDISPENSABLE
//
//  Une tablette sans réseau accumule plusieurs pointages : 08:00, 12:00,
//  14:00, 18:00. Tous sont mesurés depuis la MÊME ancre (08:00 du matin,
//  dernier contact réussi). Si l'application n'annonçait que le délai, le
//  serveur — qui avance sa propre base à chaque appel — daterait le 2ᵉ, le
//  3ᵉ et le 4ᵉ pointage à l'heure de la synchronisation.
//
//  L'application envoie donc l'ancre AVEC le délai. Le serveur borne cette
//  ancre à la fenêtre hors-ligne, exactement comme il borne le délai.
//
//  CE QUI RESTE IMPOSSIBLE, CÔTÉ SERVEUR :
//    • antidater au-delà de la fenêtre hors-ligne (7 jours) ;
//    • dater un pointage dans le futur ;
//    • contourner la fonction (l'écriture directe dans la table est refusée).
//  Et tout ce qui sort de l'ordinaire est SIGNALÉ et VISIBLE dans les
//  rapports (colonne `suspect`) plutôt que refusé en silence.
//
// ═══════════════════════════════════════════════════════════════════════════

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'heure_pointage.dart';        // ⭐ LIVRAISON 22

class TrustedPunchService {
  TrustedPunchService._(); // classe utilitaire : pas d'instance

  // ─── stockage local ───────────────────────────────────────────────────
  static const String _boxName     = 'encheck_device';
  static const String _kDeviceId   = 'device_id';
  static const String _kAnchorUtc  = 'anchor_server_utc';
  static const String _kAnchorMono = 'anchor_mono_ms';
  // ⭐ LIVRAISON 12 — le jeton de session. Rangé dans la MÊME boîte que
  //    l'identifiant d'appareil : aucune dépendance nouvelle.
  static const String _kJeton      = 'session_jeton';
  // ⭐ LIVRAISON 22 — le fuseau de l'entreprise, appris du serveur : il est
  //    mémorisé pour que l'affichage reste juste après un redémarrage, et
  //    même sans réseau.
  static const String _kFuseauNom   = 'fuseau_entreprise_nom';
  static const String _kFuseauDecal = 'fuseau_entreprise_decalage_s';

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Chronomètre MONOTONE. Il ne recule jamais, même si l'utilisateur change
  /// l'heure du téléphone. C'est le cœur du dispositif.
  static final Stopwatch _mono = Stopwatch()..start();

  static Box?         _box;
  static String?      _deviceId;
  static DateTime?    _anchorUtc;     // heure serveur au moment de l'ancrage
  static int?         _anchorMonoMs;  // valeur du chronomètre à cet instant
  static DateTime?    _dernierContact;
  static String?      _jeton;         // ⭐ LIVRAISON 12 : le jeton de session
  static bool         _pret = false;

  // ═══════════════════════════════════════════════════════════════════════
  //  GARDE-FOU « DATE FUTURE » (fiche arbitrage 2/3, P2)
  // ═══════════════════════════════════════════════════════════════════════
  /// Marge de dérive d'horloge tolérée, en minutes.
  ///
  /// Un pointage dont l'heure projetée dépasse « maintenant + cette marge »
  /// est refusé (`reason: 'horloge_futur'`). La source de vérité reste le
  /// serveur : réglage `garde_fou_futur_minutes` dans
  /// `encheck_reglages_pointage` (défaut : 5) + trigger SQL sur
  /// `attendances`. Ce n'est ici qu'un refus anticipé, côté appareil.
  static const int margeDeriveHorlogeMinutes = 5;

  // ═══════════════════════════════════════════════════════════════════════
  //  ÉTAT (utile pour l'affichage et le diagnostic)
  // ═══════════════════════════════════════════════════════════════════════

  static bool get estPret   => _pret;
  static bool get ancree    => _anchorUtc != null && _anchorMonoMs != null;

  /// ⭐ L'ANCRE : l'heure SERVEUR sur laquelle `ecouleSecondes()` se base.
  ///
  /// Elle doit être transmise au serveur avec chaque pointage. Sans elle,
  /// le serveur ne saurait pas dater correctement le 2ᵉ et le 3ᵉ pointage
  /// d'une file hors-ligne (il avance sa propre base à chaque appel).
  static DateTime? get ancreUtc => _anchorUtc;
  static DateTime? get dernierContact => _dernierContact;

  /// Depuis combien de temps n'avons-nous pas parlé au serveur ?
  static Duration? get ageAncre {
    if (_anchorUtc == null) return null;
    return DateTime.now().toUtc().difference(_anchorUtc!);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  INITIALISATION — à appeler dans main() après Hive.initFlutter()
  // ═══════════════════════════════════════════════════════════════════════

  static Future<void> initialiser() async {
    if (_pret) return;
    try {
      final box = await Hive.openBox(_boxName);
      _box = box;

      // identifiant stable de l'appareil (généré une seule fois)
      _deviceId = box.get(_kDeviceId) as String?;
      if (_deviceId == null || _deviceId!.isEmpty) {
        _deviceId = const Uuid().v4();
        await box.put(_kDeviceId, _deviceId);
      }

      // ⭐ LIVRAISON 12 — le jeton de session survit aux redémarrages : l'employé
      //    n'a pas à se reconnecter à chaque lancement, et un pointage mis en file
      //    hors-ligne sait encore qui il est.
      _jeton = box.get(_kJeton) as String?;

      // ⭐ LIVRAISON 22 — le fuseau de l'entreprise repris du disque : l'écran
      //    affiche la bonne heure dès la première seconde, sans attendre le
      //    réseau, et le décalage reste juste hors-ligne.
      final fuseauDec = box.get(_kFuseauDecal) as int?;
      if (fuseauDec != null) {
        HeurePointage.reglerFuseauEntreprise(
            nom: box.get(_kFuseauNom) as String?, decalageSecondes: fuseauDec);
      }

      // rechargement de l'ancrage
      final a = box.get(_kAnchorUtc)  as String?;
      final m = box.get(_kAnchorMono) as int?;
      if (a != null && m != null) {
        final utc = DateTime.tryParse(a);
        // si le chronomètre est reparti de zéro (redémarrage de l'app),
        // l'ancrage sauvegardé n'a plus de sens → on l'oublie proprement.
        if (utc != null && _mono.elapsedMilliseconds >= m) {
          _anchorUtc    = utc.toUtc();
          _anchorMonoMs = m;
        } else {
          await box.delete(_kAnchorUtc);
          await box.delete(_kAnchorMono);
        }
      }

      _pret = true;
      print('🕐 Horloge de confiance prête — appareil $_deviceId '
            '(ancrée : ${ancree ? "oui" : "non"})');
    } catch (e) {
      print('⚠️ TrustedPunchService.initialiser : $e');
    }
  }

  /// Identifiant de cet appareil — c'est lui que le serveur surveille.
  static Future<String> deviceId() async {
    if (!_pret) await initialiser();
    return _deviceId ?? 'inconnu';
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ⭐ LIVRAISON 12 — LE JETON DE SESSION
  //
  //  À la connexion, le serveur remet un jeton de 256 bits, lié à CET appareil.
  //  Le pointage le présente, et c'est lui qui fixe l'identité. Sans lui,
  //  connaître l'identifiant d'un employé suffisait à pointer à sa place —
  //  or l'identifiant d'un employé n'est pas un secret.
  // ═══════════════════════════════════════════════════════════════════════

  /// Le jeton en mémoire, tel qu'il sera joint au prochain pointage.
  /// `null` = pas connecté (le serveur accepte encore, en mode « tolerant »).
  static String? get jeton => _jeton;

  /// Range le jeton remis par le serveur à la connexion.
  /// Passe `null` ou une chaîne vide pour l'effacer (déconnexion).
  static Future<void> enregistrerJeton(String? jeton) async {
    _jeton = (jeton == null || jeton.isEmpty) ? null : jeton;
    try {
      if (!_pret) await initialiser();
      final box = _box ?? await Hive.openBox(_boxName);
      if (_jeton == null) {
        await box.delete(_kJeton);
        print('🔑 Session fermée : le jeton a été oublié.');
      } else {
        await box.put(_kJeton, _jeton);
        print('🔑 Jeton de session rangé (${_jeton!.length} caractères).');
      }
    } catch (e) {
      print('⚠️ enregistrerJeton : $e');
    }
  }

  /// Efface le jeton — à appeler à la déconnexion.
  static Future<void> oublierJeton() => enregistrerJeton(null);

  // ═══════════════════════════════════════════════════════════════════════
  //  LA MESURE : depuis combien de secondes ?
  // ═══════════════════════════════════════════════════════════════════════

  /// Secondes écoulées depuis le dernier contact avec le serveur.
  ///
  /// Renvoie `null` quand l'application ne peut pas le savoir de façon fiable
  /// (pas encore ancrée, ou application redémarrée). Dans ce cas le serveur
  /// date le pointage à MAINTENANT — jamais dans le passé.
  static int? ecouleSecondes() {
    if (_anchorMonoMs == null) return null;
    final ecart = _mono.elapsedMilliseconds - _anchorMonoMs!;
    if (ecart < 0) return null;   // redémarrage détecté → on ne sait plus
    return ecart ~/ 1000;
  }

  static Future<void> _ancrer(DateTime serverUtc) async {
    _anchorUtc     = serverUtc.toUtc();
    _anchorMonoMs  = _mono.elapsedMilliseconds;
    _dernierContact = DateTime.now().toUtc();
    try {
      final box = _box ?? await Hive.openBox(_boxName);
      _box = box;
      await box.put(_kAnchorUtc,  _anchorUtc!.toIso8601String());
      await box.put(_kAnchorMono, _anchorMonoMs);
    } catch (e) {
      print('⚠️ ancrage non sauvegardé : $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  PARLER AU SERVEUR POUR PRENDRE L'HEURE
  //  À appeler au démarrage, au retour du réseau, et avant un pointage en ligne.
  // ═══════════════════════════════════════════════════════════════════════

  static Future<DateTime?> contacterServeur({String? enterpriseId}) async {
    if (!_pret) await initialiser();
    try {
      final res = await _sb.rpc('encheck_server_time', params: {
        'p_device_id': await deviceId(),
        // ⭐ LIVRAISON 22 — quand l'entreprise est connue, le serveur renvoie
        //    AUSSI son fuseau officiel et le décalage en vigueur (heure d'été
        //    comprise). Au démarrage l'entreprise n'est pas encore lue : on
        //    envoie null et on garde simplement ce qu'on savait déjà — jamais
        //    d'effacement sur un appel sans entreprise.
        'p_enterprise_id': enterpriseId,
      });
      if (res is Map && res['ok'] == true && res['server_time'] is String) {
        final utc = DateTime.parse(res['server_time'] as String).toUtc();
        await _ancrer(utc);

        // ⭐ LIVRAISON 22
        if (enterpriseId != null && res.containsKey('enterprise_offset_seconds')) {
          final brut = res['enterprise_offset_seconds'];
          final dec  = brut is num ? brut.toInt() : null;
          final nom  = res['enterprise_timezone'] is String
              ? res['enterprise_timezone'] as String
              : null;
          HeurePointage.reglerFuseauEntreprise(nom: nom, decalageSecondes: dec);
          await _memoriserFuseau(nom, dec);
        }
        return utc;
      }
    } catch (e) {
      print('⚠️ encheck_server_time indisponible : $e');
    }
    return null;
  }

  /// ⭐ LIVRAISON 22 — mémorise le fuseau appris du serveur (ou l'oublie
  /// proprement si le serveur dit qu'il ne sait pas lire celui de l'entreprise).
  static Future<void> _memoriserFuseau(String? nom, int? decalageSecondes) async {
    try {
      final box = _box ?? await Hive.openBox(_boxName);
      _box = box;
      if (decalageSecondes == null) {
        await box.delete(_kFuseauDecal);
        await box.delete(_kFuseauNom);
      } else {
        await box.put(_kFuseauDecal, decalageSecondes);
        if (nom == null || nom.isEmpty) {
          await box.delete(_kFuseauNom);
        } else {
          await box.put(_kFuseauNom, nom);
        }
      }
    } catch (e) {
      print('⚠️ fuseau de l\'entreprise non sauvegardé : $e');
    }
  }

  /// Vérifie que le serveur est équipé (livraison 09 appliquée).
  /// Utile pour tester AVANT de déployer auprès des employés.
  static Future<bool> verifierDisponibilite() async {
    try {
      final r = await contacterServeur();
      return r != null;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LE POINTAGE — le seul chemin d'écriture
  // ═══════════════════════════════════════════════════════════════════════

  /// Enregistre un pointage en laissant LE SERVEUR décider de l'heure.
  ///
  /// [clientRef]     : référence unique du pointage. Envoyer deux fois la même
  ///                   référence ne crée qu'UNE ligne (anti-doublon après une
  ///                   coupure réseau). Si null, une référence est générée.
  /// [delaiSecondes] : secondes écoulées depuis le pointage. À fournir
  ///                   UNIQUEMENT pour un pointage hors-ligne rejoué plus tard.
  ///                   (⚠️ surtout pas un paramètre nommé « ecouleSecondes » :
  ///                   il masquerait la méthode du même nom et Dart refuserait
  ///                   de compiler.)
  ///
  /// Retourne la réponse du serveur, par exemple :
  ///   {ok: true, attendance_id: '…', check_time: '…', suspect: false, …}
  ///   {ok: false, reason: 'employe_inconnu_ou_inactif'}
  ///
  /// ⭐ FICHE ARBITRAGE 2/3, P2 — GARDE-FOU « DATE FUTURE » : un pointage dont
  ///    l'heure projetée (ancre + délai) dépasse « maintenant + 5 min » est
  ///    REFUSÉ ici avec `reason: 'horloge_futur'`, avant même d'appeler le
  ///    serveur. Le serveur garde la sienne (trigger SQL + réglage
  ///    `garde_fou_futur_minutes`) : défense en profondeur.
  static Future<Map<String, dynamic>> pointer({
    required String  employeeId,
    required String  enterpriseId,
    required String  checkType,
    String           method         = 'pin',
    String?          clientRef,
    int?             delaiSecondes,
    DateTime?        ancreUtc,
    bool             heureInconnue  = false,
    double?          latitude,
    double?          longitude,
    double?          gpsAccuracy,
    String?          geofenceId,
    int?             distanceMeters,
    bool?            isWithinZone,
    double?          faceScore,
    bool?            faceVerified,
    bool?            livenessPasse,
    int?             faceAttempts,
    // ⭐ LIVRAISON 12 — jeton imposé. Le rejeu d'une file hors-ligne doit
    //    présenter le jeton AVEC lequel le pointage a été fait, et non celui du
    //    moment : sur une tablette partagée, un autre employé a pu se connecter
    //    entre-temps. `null` = on prend le jeton courant.
    String?          jetonImpose,
  }) async {
    if (!_pret) await initialiser();

    // référence unique : garantit qu'un renvoi ne crée pas de doublon
    final ref = clientRef ?? const Uuid().v4();

    // la mesure est prise MAINTENANT (au moment du pointage), pas plus tard
    final mesure = ecouleSecondes();

    // ⭐ LE COUPLE (délai, ancre) VA TOUJOURS ENSEMBLE — c'est la règle d'or.
    //    Le délai seul ne veut rien dire : « il y a 1 h » PAR RAPPORT À QUAND ?
    //
    //    • délai fourni par l'appelant (rejeu d'une file hors-ligne)
    //         → l'ancre est celle que la file a mémorisée au moment du pointage ;
    //    • sinon, la mesure instantanée
    //         → l'ancre est celle du dernier contact avec le serveur.
    //
    //    Si aucune mesure n'est disponible (application redémarrée), on
    //    n'envoie NI délai NI ancre : le serveur date le pointage à
    //    MAINTENANT, jamais dans le passé.
    //    Si l'appelant sait que l'heure n'a PAS pu être mesurée (pointage mis
    //    en file avant un redémarrage de l'application), il le dit
    //    explicitement : on ne fabrique alors AUCUNE mesure. Le serveur datera
    //    le pointage à MAINTENANT et le signalera — plus honnête qu'une
    //    approximation silencieuse.
    final delaiEffectif = heureInconnue ? null : (delaiSecondes ?? mesure);
    final ancreEffectif  = delaiEffectif == null ? null : (ancreUtc ?? _anchorUtc);

    // ⭐ FICHE ARBITRAGE 2/3, P2 — LE GARDE-FOU « DATE FUTURE ».
    //    L'heure que le serveur va dater est « ancre + délai » (ou
    //    MAINTENANT si aucune mesure n'est disponible). Elle ne doit JAMAIS
    //    se retrouver dans le futur au-delà de la marge de dérive : un
    //    boîtier mal réglé ou une file corrompue ne doit pas écrire le
    //    pointage de demain (cas Hippo : une sortie écrite au 17/10).
    //    On ne projette que si l'ancre ET le délai sont connus — sinon le
    //    serveur datera à MAINTENANT, qui n'est jamais dans le futur.
    if (delaiEffectif != null && ancreEffectif != null) {
      final projection =
          ancreEffectif.add(Duration(seconds: delaiEffectif));
      final limite = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: margeDeriveHorlogeMinutes));
      if (projection.isAfter(limite)) {
        print('❌ horloge_futur : heure projetée '
            '${projection.toIso8601String()} au-delà de '
            '+$margeDeriveHorlogeMinutes min — pointage refusé.');
        return {
          'ok': false,
          'reason': 'horloge_futur',
          'check_time_projete': projection.toIso8601String(),
        };
      }
    }

    try {
      final res = await _sb.rpc('encheck_punch', params: {
        'p_device_id':       await deviceId(),
        'p_employee_id':     employeeId,
        'p_enterprise_id':   enterpriseId,
        'p_check_type':      checkType,
        'p_method':          method,
        'p_client_ref':      ref,
        // ⚠️ si l'appelant a fourni un délai (rejeu hors-ligne), il prime ;
        //    sinon on utilise la mesure prise à l'instant du pointage
        'p_elapsed_seconds': delaiEffectif,
        // ⭐ la base de temps de la mesure ci-dessus (cf. règle d'or plus haut)
        'p_anchor_utc':      ancreEffectif?.toIso8601String(),
        // heure du téléphone : envoyée POUR AUDIT seulement, jamais utilisée
        // telle quelle. Le serveur mesure l'écart et le signale.
        'p_device_time':     DateTime.now().toUtc().toIso8601String(),
        'p_latitude':        latitude,
        'p_longitude':       longitude,
        'p_gps_accuracy':    gpsAccuracy,
        'p_geofence_id':     geofenceId,
        'p_distance_meters': distanceMeters,
        'p_is_within_zone':  isWithinZone,
        'p_face_score':      faceScore,
        'p_face_verified':   faceVerified,
        'p_liveness_passed': livenessPasse,
        'p_face_attempts':   faceAttempts,
        // ⭐ LIVRAISON 12 — le jeton de session. C'est LUI qui fixe l'identité du
        //    pointage côté serveur : les identifiants déclarés plus haut ne sont
        //    plus que VÉRIFIÉS contre lui.
        //    `null` tant que l'employé ne s'est pas connecté — le serveur accepte
        //    alors le pointage en mode « tolerant ».
        'p_jeton':           jetonImpose ?? _jeton,
      });

      if (res is Map) {
        final map = Map<String, dynamic>.from(res);

        // ⭐ à CHAQUE réponse du serveur, on ré-ancre le chronomètre :
        //    l'ancrage reste ainsi toujours frais, et le prochain pointage
        //    hors-ligne sera daté avec précision.
        if (map['received_at'] is String) {
          final utc = DateTime.tryParse(map['received_at'] as String);
          if (utc != null) await _ancrer(utc);
        }

        if (map['suspect'] == true) {
          print('⚠️ pointage marqué SUSPECT : ${map['suspect_reason']}');
        }
        return map;
      }

      return {'ok': false, 'reason': 'reponse_inattendue'};
    } on PostgrestException catch (e) {
      // 404 = la livraison 09 n'est pas encore appliquée sur ce serveur
      print('❌ encheck_punch : ${e.message} (code ${e.code})');
      // ⭐ FICHE ARBITRAGE 2/3, P2 — le trigger SQL « date future » refuse le
      //    pointage avec un message explicite : on le traduit pour ce qu'il
      //    est, au lieu du générique « serveur_non_equipe ».
      if (e.message.contains('horloge_futur') ||
          e.message.contains('futur')) {
        return {'ok': false, 'reason': 'horloge_futur', 'detail': e.message};
      }
      return {'ok': false, 'reason': 'serveur_non_equipe', 'detail': e.message};
    } catch (e) {
      // panne réseau : le pointage sera mis en file locale et rejoué plus tard
      print('❌ encheck_punch (réseau) : $e');
      return {'ok': false, 'reason': 'reseau', 'detail': e.toString()};
    }
  }

  /// Référence à transmettre à la file d'attente pour un rejeu ultérieur.
  static String nouvelleReference() => const Uuid().v4();

  /// Réinitialise l'ancrage (bouton de dépannage / changement d'appareil).
  static Future<void> oublierAncrage() async {
    _anchorUtc     = null;
    _anchorMonoMs  = null;
    _dernierContact = null;
    try {
      final box = _box ?? await Hive.openBox(_boxName);
      await box.delete(_kAnchorUtc);
      await box.delete(_kAnchorMono);
    } catch (_) {}
  }
}

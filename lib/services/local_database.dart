import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'security_service.dart';
import 'connectivity_service.dart';
import 'trusted_punch_service.dart';
import 'supabase_service.dart';

class LocalDatabase {

  // ═══════════════════════════════════════════════════════════
  // 💾 SAUVEGARDER UN POINTAGE EN ATTENTE
  // ═══════════════════════════════════════════════════════════
  static Future<int> sauvegarderPointagePending({
    required String employeeId,
    required String enterpriseId,
    required String checkType,
    String method = 'pin',
  }) async {
    var box = Hive.box('pointages_pending');

    final maintenant = DateTime.now();
    final checkTime = maintenant.toIso8601String();

    // ⭐ LIVRAISON 09 — on capture MAINTENANT deux informations décisives :
    //
    //   delai_secondes : combien de secondes se sont écoulées depuis le
    //                    dernier contact avec le serveur. Mesuré par un
    //                    chronomètre monotone, donc il ne peut PAS être
    //                    faussé en changeant l'heure du téléphone.
    //                    C'est ce chiffre — et non l'heure du téléphone —
    //                    que le serveur utilisera pour dater le pointage.
    //
    //   client_ref     : référence unique. Si l'appareil renvoie deux fois
    //                    le même pointage après une coupure réseau, le
    //                    serveur n'en crée qu'un seul.
    //
    // ⚠️ À capturer ICI, au moment du pointage — pas au moment de la synchro.
    final int? delai = TrustedPunchService.ecouleSecondes();
    final String reference = TrustedPunchService.nouvelleReference();

    // ⭐ L'ANCRE — à capturer ICI, au même instant que le délai.
    //    Le délai seul est inexploitable : « il y a 1 h » par rapport à quand ?
    //    Une tablette hors-ligne peut accumuler plusieurs pointages (matin,
    //    midi, soir) ; tous doivent se référer à la MÊME base de temps, sinon
    //    le serveur les daterait tous à l'heure de la synchronisation.
    final DateTime? ancre = TrustedPunchService.ancreUtc;

    // ⭐ LIVRAISON 19 — L'INSTANT RÉEL du pointage, calculé UNE fois pour
    //    toutes : heure de l'ancre serveur + délai mesuré au chronomètre
    //    monotone. C'est lui qui servira à comparer et à classer ce pointage
    //    (l'heure murale ci-dessous reste utile pour l'affichage hors-ligne).
    final DateTime? instantUtc = (ancre != null && delai != null)
        ? ancre.add(Duration(seconds: delai)).toUtc()
        : null;

    final data = {
      'employee_id': employeeId,
      'enterprise_id': enterpriseId,
      'check_type': checkType,
      'check_time': checkTime,        // heure du téléphone : AFFICHAGE LOCAL seulement
      'method': method,
      'created_at': checkTime,
      'delai_secondes': delai,        // ⭐ la vraie mesure, pour le serveur
      'ancre_utc': (ancre == null ? null : ancre.toIso8601String()),
                                      // ⭐ la base de temps de cette mesure
      'instant_utc': (instantUtc == null ? null : instantUtc.toIso8601String()),
                                      // ⭐ LIVRAISON 19 : l'instant réel, pour
                                      //    comparer sans se tromper d'heure
      'client_ref': reference,        // ⭐ anti-doublon
      // ⭐ LIVRAISON 12 — le jeton AVEC lequel ce pointage a été fait. Sans lui,
      //    le rejeu utiliserait le jeton du moment : sur une tablette
      //    partagée, le pointage d'A serait rejoué sous l'identité de B.
      'jeton': TrustedPunchService.jeton,
    };

    // Hive retourne la clé (ID) auto-incrémentée
    int id = await box.add(data);
    print('💾 Pointage en attente : $checkTime '
          '(délai mesuré : ${delai ?? "inconnu"}s, '
          'ancre : ${ancre == null ? "inconnue" : ancre.toIso8601String()}, '
          'réf. $reference)');
    return id;
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 RÉCUPÉRER TOUS LES POINTAGES PENDING
  // ═══════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getPointagesPending() async {
    var box = Hive.box('pointages_pending');
    List<Map<String, dynamic>> results = [];

    // On inclut la clé Hive comme 'id' pour la compatibilité
    for (var i = 0; i < box.length; i++) {
      var key = box.keyAt(i);
      var value = Map<String, dynamic>.from(box.getAt(i));
      value['id'] = key;
      results.add(value);
    }

    // Tri par date
    // ⭐ LIVRAISON 19 — sur l'INSTANT RÉEL (ancre serveur + délai mesuré), donc
    //    insensible au réglage du téléphone et comparable aux lignes du serveur.
    results.sort(HeurePointage.parInstantCroissant);
    return results;
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 RÉCUPÉRER LES POINTAGES PENDING D'UN EMPLOYÉ
  // ═══════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getPointagesPendingParEmploye(String employeeId) async {
    var box = Hive.box('pointages_pending');
    List<Map<String, dynamic>> results = [];

    for (var i = 0; i < box.length; i++) {
      var val = Map<String, dynamic>.from(box.getAt(i));
      if (val['employee_id'] == employeeId) {
        val['id'] = box.keyAt(i);
        results.add(val);
      }
    }

    // Tri descendant (plus récent en premier)
    // ⭐ LIVRAISON 19 — instant réel, comme ci-dessus.
    results.sort(HeurePointage.parInstantDecroissant);
    return results;
  }

  // ═══════════════════════════════════════════════════════════
  // 🗑️ SUPPRIMER UN POINTAGE PENDING
  // ═══════════════════════════════════════════════════════════
  static Future<void> supprimerPointagePending(int id) async {
    var box = Hive.box('pointages_pending');
    await box.delete(id);
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 OBTENIR LE DERNIER POINTAGE LOCAL
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> dernierPointageLocal(String employeeId) async {
    var list = await getPointagesPendingParEmploye(employeeId);
    if (list.isNotEmpty) {
      return list.first; // Déjà trié plus récent en premier
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 OBTENIR LE VRAI DERNIER POINTAGE (FUSION)
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> dernierPointageCombine(String employeeId) async {
    Map<String, dynamic>? localPointage;
    Map<String, dynamic>? supabasePointage;

    try { localPointage = await dernierPointageLocal(employeeId); } catch (e) { print('⚠️ Erreur Hive locale: $e'); }

    if (ConnectivityService.isOnline) {
      try { supabasePointage = await SupabaseService.dernierPointage(employeeId); } catch (e) { print('⚠️ Erreur Supabase: $e'); }
    }

    if (localPointage == null && supabasePointage == null) return null;
    if (localPointage != null && supabasePointage == null) return localPointage;
    if (localPointage == null && supabasePointage != null) return supabasePointage;

    try {
      // ⭐ LIVRAISON 19 — comparaison sur l'INSTANT RÉEL, par le même fichier
      //    que l'affichage et les tris (services/heure_pointage.dart) : une
      //    seule règle de comparaison dans toute l'application, et un refus
      //    net de comparer deux horodatages illisibles au lieu de choisir au
      //    hasard. C'est ici que se décide le type du pointage suivant
      //    (entrée ou sortie), donc l'endroit mérite d'être explicite.
      final dateLocal = HeurePointage.instant(localPointage!);
      final dateSupabase = HeurePointage.instant(supabasePointage!);
      if (dateLocal == null) return supabasePointage;
      if (dateSupabase == null) return localPointage;
      return dateLocal.isAfter(dateSupabase) ? localPointage : supabasePointage;
    } catch (e) {
      return localPointage;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🏢 CACHER LES ENTREPRISES
  // ═══════════════════════════════════════════════════════════
  static Future<void> cacherEntreprises(List<Map<String, dynamic>> entreprises) async {
    var box = Hive.box('enterprises_cache');
    await box.clear(); // On vide avant de remettre

    for (var entreprise in entreprises) {
      await box.put(entreprise['id'], entreprise);
    }
  }

  static Future<List<Map<String, dynamic>>> getEntreprisesCache() async {
    var box = Hive.box('enterprises_cache');
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 👥 CACHER LES EMPLOYÉS
  // ═══════════════════════════════════════════════════════════
  static Future<void> cacherEmployees(List<Map<String, dynamic>> employees) async {
  // ═══════════════════════════════════════════════════════════
    // ⭐ LIVRAISON 13 — LA BOÎTE DES VÉRIFICATEURS LOCAUX
    // ═══════════════════════════════════════════════════════════

    static const String _boxAuth = 'encheck_auth_local';

    /// Range le vérificateur de CET appareil, fabriqué à partir du secret qui
    /// vient d'être PROUVÉ auprès du serveur (connexion réussie).
    static Future<void> memoriserVerificateur(String employeeId, String secret,
        {bool parQr = false}) async {
      try {
        final box = await Hive.openBox(_boxAuth);
        final v = SecurityService.creerVerificateur(secret);
        await box.put((parQr ? 'qr:' : 'pin:') + employeeId, {
          'sel': v['sel'],
          'empreinte': v['empreinte'],
          'quand': DateTime.now().toIso8601String(),
        });
        // index : retrouver l'employé à partir du code scanné, sans ranger le code
        if (parQr) {
          await box.put('idx:' + SecurityService.indexer(secret), employeeId);
        }
      } catch (e) {
        print('⚠️ memoriserVerificateur : $e');
      }
    }

    /// Vérifie un secret SANS le serveur, contre le vérificateur de l'appareil.
    static Future<bool> verifierLocal(String employeeId, String secret,
        {bool parQr = false}) async {
      try {
        final box = await Hive.openBox(_boxAuth);
        final brut = box.get((parQr ? 'qr:' : 'pin:') + employeeId);
        if (brut == null) return false;
        final v = Map<String, dynamic>.from(brut);
        return SecurityService.verifierVerificateur(
            secret, v['sel'] as String?, v['empreinte'] as String?);
      } catch (e) {
        return false;
      }
    }
    var box = Hive.box('employees_cache');
    // On ne clear pas tout, on update ou ajoute
    for (var employee in employees) {
      await box.put(employee['id'], employee);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔐 VÉRIFIER UN EMPLOYÉ EN CACHE (AVEC PIN)
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> verifierEmployeeCache(
      String enterpriseId,
      String matricule,
      String pin,
      ) async {
    var box = Hive.box('employees_cache');

    try {
      // ⭐ LIVRAISON 13 — on cherche l'employé par son matricule, PUIS on
      //    vérifie le PIN contre le vérificateur de CET appareil. Plus aucune
      //    comparaison avec un hachage venu du serveur : il n'est même plus
      //    téléchargé (la 12b en a fermé la lecture).
      var found = box.values.firstWhere((e) {
        var emp = Map<String, dynamic>.from(e);
        return emp['enterprise_id'] == enterpriseId &&
            emp['matricule'] == matricule;
      });
      final emp = Map<String, dynamic>.from(found);

      if (!await verifierLocal(emp['id'] as String, pin)) {
        // Jamais connecté en ligne sur cet appareil : on ne peut pas le
        // reconnaître hors-ligne. L'écran proposera de se reconnecter.
        print('🔒 Hors-ligne : aucun vérificateur local pour ce PIN');
        return null;
      }
      return emp;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔐 VÉRIFIER UN EMPLOYÉ PAR QR CODE EN CACHE
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> verifierEmployeeParQR(
      String enterpriseId,
      String qrCode,
      ) async {
    // ⭐ LIVRAISON 13 — hors-ligne, le badge est reconnu par un index local
    //    (l'empreinte du code, jamais le code), puis vérifié. Le MATRICULE
    //    SEUL ne suffit plus : c'était le trou de la 11, resté ouvert ici.
    try {
      final box = await Hive.openBox(_boxAuth);
      final employeeId = box.get('idx:' + SecurityService.indexer(qrCode));
      if (employeeId is! String) return null;
      if (!await verifierLocal(employeeId, qrCode, parQr: true)) return null;

      var cache = Hive.box('employees_cache');
      var found = cache.values.firstWhere((e) {
        var emp = Map<String, dynamic>.from(e);
        return emp['id'] == employeeId && emp['enterprise_id'] == enterpriseId;
      });
      return Map<String, dynamic>.from(found);
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 💾 CACHER LES HORAIRES DES EMPLOYÉS
  // ═══════════════════════════════════════════════════════════
  static Future<void> cacherHoraires(List<Map<String, dynamic>> schedules) async {
    var box = Hive.box('employee_schedules_cache');
    for (var schedule in schedules) {
      await box.put(schedule['employee_id'], schedule);
    }
  }

  static Future<Map<String, dynamic>?> getHorairesCache(String employeeId) async {
    var box = Hive.box('employee_schedules_cache');
    var data = box.get(employeeId);
    if (data != null) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  static Future<int> compterPointagesPending() async {
    var box = Hive.box('pointages_pending');
    return box.length;
  }





  // ═══════════════════════════════════════════════════════════
  // 🤖 CACHE VECTEUR FACIAL (EMBEDDING)
  // ═══════════════════════════════════════════════════════════

  static Future<void> sauvegarderEmbedding({
    required String employeeId,
    required String enterpriseId,
    required List<double> embedding,
    required String enrollmentId,
  }) async {
    var box = Hive.box('face_embeddings');
    await box.put(employeeId, {
      'employee_id': employeeId,
      'enterprise_id': enterpriseId,
      'embedding': embedding,
      'enrollment_id': enrollmentId,
      'cached_at': DateTime.now().toIso8601String(),
    });
    print('💾 Embedding sauvegardé pour employé: $employeeId');
  }

  static Future<Map<String, dynamic>?> getEmbedding(String employeeId) async {
    var box = Hive.box('face_embeddings');
    var data = box.get(employeeId);
    if (data != null) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  static Future<void> supprimerEmbedding(String employeeId) async {
    var box = Hive.box('face_embeddings');
    await box.delete(employeeId);
  }

  static Future<List<Map<String, dynamic>>> getTousEmbeddings(
      String enterpriseId) async {
    var box = Hive.box('face_embeddings');
    return box.values
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['enterprise_id'] == enterpriseId)
        .toList();
  }

  // ═══════════════════════════════════════════════════════════
  // ⚙️ CACHE CONFIG RECONNAISSANCE FACIALE
  // ═══════════════════════════════════════════════════════════

  static Future<void> sauvegarderConfigFaciale(
      Map<String, dynamic> config) async {
    var box = Hive.box('face_config');
    await box.put('config', config);
  }

  static Future<Map<String, dynamic>?> getConfigFaciale() async {
    var box = Hive.box('face_config');
    var data = box.get('config');
    if (data != null) {
      return Map<String, dynamic>.from(data);
    }
    // Config par défaut si pas encore chargée
    return {
      'confidence_threshold': 0.80,
      'liveness_required': true,
      'admin_approval_required': true,
      'fallback_allowed': true,
      'max_attempts': 3,
      'kiosk_mode_enabled': false,
      'pointage_mode': 'free',
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 CACHE STATUT ENRÔLEMENT
  // ═══════════════════════════════════════════════════════════

  static Future<void> sauvegarderStatutEnrolement({
    required String employeeId,
    required String status, // 'pending', 'approved', 'rejected', 'none'
    String? enrollmentId,
  }) async {
    var box = Hive.box('face_enrollment_status');
    await box.put(employeeId, {
      'employee_id': employeeId,
      'status': status,
      'enrollment_id': enrollmentId,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<Map<String, dynamic>?> getStatutEnrolement(
      String employeeId) async {
    var box = Hive.box('face_enrollment_status');
    var data = box.get(employeeId);
    if (data != null) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }


  // ═══════════════════════════════════════════════════════════
// 🔍 CHERCHER EMPLOYÉ PAR MATRICULE (MODE TABLETTE)
// ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>?> getEmployeeParMatricule(
      String enterpriseId, String matricule) async {
    var box = Hive.box('employees_cache');
    try {
      var found = box.values.firstWhere((e) {
        var emp = Map<String, dynamic>.from(e);
        return emp['enterprise_id'] == enterpriseId &&
            emp['matricule'] == matricule;
      });
      return Map<String, dynamic>.from(found);
    } catch (e) {
      return null;
    }
  }


  static Future<Map<String, dynamic>?> getEmployeeParId(
      String employeeId) async {
    var box = Hive.box('employees_cache');
    var data = box.get(employeeId);
    if (data != null) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }
}
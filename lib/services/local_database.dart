import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'security_service.dart';
import 'connectivity_service.dart';
import 'trusted_punch_service.dart';
import 'supabase_service.dart';

class LocalDatabase {

  // ═══════════════════════════════════════════════════════════
  // 🔐 VÉRIFICATEURS LOCAUX
  // ═══════════════════════════════════════════════════════════
  static const String _boxAuth = 'encheck_auth_local';

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
      if (parQr) {
        await box.put('idx:' + SecurityService.indexer(secret), employeeId);
      }
    } catch (e) {
      print('⚠️ memoriserVerificateur : $e');
    }
  }

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
    final int? delai = TrustedPunchService.ecouleSecondes();
    final String reference = TrustedPunchService.nouvelleReference();
    final DateTime? ancre = TrustedPunchService.ancreUtc;
    final DateTime? instantUtc = (ancre != null && delai != null)
        ? ancre.add(Duration(seconds: delai)).toUtc()
        : null;

    final data = {
      'employee_id': employeeId,
      'enterprise_id': enterpriseId,
      'check_type': checkType,
      'check_time': checkTime,
      'method': method,
      'created_at': checkTime,
      'delai_secondes': delai,
      'ancre_utc': (ancre == null ? null : ancre.toIso8601String()),
      'instant_utc': (instantUtc == null ? null : instantUtc.toIso8601String()),
      'client_ref': reference,
      'jeton': TrustedPunchService.jeton,
    };

    int id = await box.add(data);
    print('💾 Pointage en attente : $checkTime (délai: ${delai ?? "inconnu"}s, réf: $reference)');
    return id;
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 RÉCUPÉRER TOUS LES POINTAGES PENDING
  // ═══
  static Future<List<Map<String, dynamic>>> getPointagesPending() async {
    var box = Hive.box('pointages_pending');
    List<Map<String, dynamic>> results = [];
    for (var i = 0; i < box.length; i++) {
      var key = box.keyAt(i);
      var value = Map<String, dynamic>.from(box.getAt(i));
      value['id'] = key;
      results.add(value);
    }
    results.sort((a, b) => (a['check_time'] as String).compareTo(b['check_time'] as String));
    return results;
  }

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
    results.sort((a, b) => (b['check_time'] as String).compareTo(a['check_time'] as String));
    return results;
  }

  static Future<void> supprimerPointagePending(int id) async {
    var box = Hive.box('pointages_pending');
    await box.delete(id);
  }

  static Future<Map<String, dynamic>?> dernierPointageLocal(String employeeId) async {
    var list = await getPointagesPendingParEmploye(employeeId);
    return list.isNotEmpty ? list.first : null;
  }

  // ═════════════════════════════════════════════════════════
  // 🔍 OBTENIR LE VRAI DERNIER POINTAGE (FUSION)
  // ══
  static Future<Map<String, dynamic>?> dernierPointageCombine(String employeeId) async {
    Map<String, dynamic>? localPointage;
    Map<String, dynamic>? supabasePointage;
    try { localPointage = await dernierPointageLocal(employeeId); } catch (e) {}
    if (ConnectivityService.isOnline) {
      try { supabasePointage = await SupabaseService.dernierPointage(employeeId); } catch (e) {}
    }
    if (localPointage == null && supabasePointage == null) return null;
    if (localPointage != null && supabasePointage == null) return localPointage;
    if (localPointage == null && supabasePointage != null) return supabasePointage;
    try {
      final dateLocal = DateTime.parse(localPointage!['check_time'] as String);
      final dateSupabase = DateTime.parse(supabasePointage!['check_time'] as String);
      return dateLocal.isAfter(dateSupabase) ? localPointage : supabasePointage;
    } catch (e) {
      return localPointage;
    }
  }

  // ══════════════════════════════════════════════════════
  // 🏢 CACHER LES ENTREPRISES
  // ══
  static Future<void> cacherEntreprises(List<Map<String, dynamic>> entreprises) async {
    var box = Hive.box('enterprises_cache');
    await box.clear();
    for (var entreprise in entreprises) {
      await box.put(entreprise['id'], entreprise);
    }
  }

  static Future<List<Map<String, dynamic>>> getEntreprisesCache() async {
    var box = Hive.box('enterprises_cache');
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ═══════════════════════════════════════════════
  // 👥 CACHER LES EMPLOYÉS
  // ══
  static Future<void> cacherEmployees(List<Map<String, dynamic>> employees) async {
    var box = Hive.box('employees_cache');
    for (var employee in employees) {
      await box.put(employee['id'], employee);
    }
  }

  static Future<List<Map<String, dynamic>>> getEmployeesCache() async {
    var box = Hive.box('employees_cache');
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 🪪 CONTRAT D'ACCÈS (25/10/2026) — compléter une fiche légère depuis une
  /// ligne d'enrôlement facial (si elle porte des champs d'identité).
  /// Ajout UNIQUEMENT : une clé déjà présente n'est jamais remplacée — une
  /// fiche mémorisée à la connexion prime toujours.
  static Future<void> completerIdentiteCache(Map<String, dynamic> ligne) async {
    try {
      final id = ligne['employee_id'];
      if (id is! String || id.isEmpty) return;
      var box = Hive.box('employees_cache');
      final brut = box.get(id);
      final fiche = brut != null
          ? Map<String, dynamic>.from(brut)
          : <String, dynamic>{};
      fiche.putIfAbsent('id', () => id);
      for (final cle in [
        'enterprise_id',
        'first_name',
        'last_name',
        'matricule',
        'photo_url',
        'is_active',
      ]) {
        if (ligne[cle] != null) fiche.putIfAbsent(cle, () => ligne[cle]);
      }
      await box.put(id, fiche);
    } catch (e) {
      print('⚠️ completerIdentiteCache : $e');
    }
  }

  // ═══════════════════════════════════════════════
  // 🔐 VÉRIFIER UN EMPLOYÉ EN CACHE (AVEC PIN)
  // ══
  static Future<Map<String, dynamic>?> verifierEmployeeCache(
      String enterpriseId, String matricule, String pin) async {
    var box = Hive.box('employees_cache');
    try {
      var found = box.values.firstWhere((e) {
        var emp = Map<String, dynamic>.from(e);
        return emp['enterprise_id'] == enterpriseId && emp['matricule'] == matricule;
      });
      final emp = Map<String, dynamic>.from(found);
      if (!await verifierLocal(emp['id'] as String, pin)) {
        return null;
      }
      return emp;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // 🔐 VÉRIFIER UN EMPLOYÉ PAR QR CODE EN CACHE
  // ══
  static Future<Map<String, dynamic>?> verifierEmployeeParQR(
      String enterpriseId, String qrCode) async {
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

  // ═══════════════════════════════════════
  // 💾 CACHER LES HORAIRES
  // ══
  static Future<void> cacherHoraires(List<Map<String, dynamic>> schedules) async {
    var box = Hive.box('employee_schedules_cache');
    for (var schedule in schedules) {
      await box.put(schedule['employee_id'], schedule);
    }
  }

  static Future<Map<String, dynamic>?> getHorairesCache(String employeeId) async {
    var box = Hive.box('employee_schedules_cache');
    var data = box.get(employeeId);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  // ═══════════════════════════════════════
  // 📊 COMPTER LES POINTAGES PENDING
  // ══
  static Future<int> compterPointagesPending() async {
    var box = Hive.box('pointages_pending');
    return box.length;
  }

  // ══════════════════════════════════════
  // 👤 CHERCHER EMPLOYÉ PAR MATRICULE
  // ══
  static Future<Map<String, dynamic>?> getEmployeeParMatricule(
      String enterpriseId, String matricule) async {
    var box = Hive.box('employees_cache');
    try {
      var found = box.values.firstWhere((e) {
        var emp = Map<String, dynamic>.from(e);
        return emp['enterprise_id'] == enterpriseId && emp['matricule'] == matricule;
      });
      return Map<String, dynamic>.from(found);
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getEmployeeParId(String employeeId) async {
    var box = Hive.box('employees_cache');
    var data = box.get(employeeId);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  // ═════════════════════════════════════
  // 🤖 CACHE VECTEUR FACIAL (EMBEDDING)
  // ═
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
  }

  static Future<Map<String, dynamic>?> getEmbedding(String employeeId) async {
    var box = Hive.box('face_embeddings');
    var data = box.get(employeeId);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  static Future<void> supprimerEmbedding(String employeeId) async {
    var box = Hive.box('face_embeddings');
    await box.delete(employeeId);
  }

  static Future<List<Map<String, dynamic>>> getTousEmbeddings(String enterpriseId) async {
    var box = Hive.box('face_embeddings');
    return box.values
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['enterprise_id'] == enterpriseId)
        .toList();
  }

  // ═══════════════════════════════
  // ⚙️ CACHE CONFIG RECONNAISSANCE FACIALE
  // ═
  static Future<void> sauvegarderConfigFaciale(Map<String, dynamic> config) async {
    var box = Hive.box('face_config');
    await box.put('config', config);
  }

  static Future<Map<String, dynamic>?> getConfigFaciale() async {
    var box = Hive.box('face_config');
    var data = box.get('config');
    if (data != null) {
      return Map<String, dynamic>.from(data);
    }
    return {
      'confidence_threshold': 0.80,
      'liveness_required': true,
      'admin_approval_required': true,
      'fallback_allowed': true,
      'max_attempts': 3,
      'kiosk_mode_enabled': false,
      'pointage_mode': null,
    };
  }

  // ══════════════════════════════
  // 📋 CACHE STATUT ENRÔLEMENT
  // ═
  static Future<void> sauvegarderStatutEnrolement({
    required String employeeId,
    required String status,
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

  static Future<Map<String, dynamic>?> getStatutEnrolement(String employeeId) async {
    var box = Hive.box('face_enrollment_status');
    var data = box.get(employeeId);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }
}
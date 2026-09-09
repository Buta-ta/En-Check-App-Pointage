import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'security_service.dart';
import 'connectivity_service.dart';
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

    final data = {
      'employee_id': employeeId,
      'enterprise_id': enterpriseId,
      'check_type': checkType,
      'check_time': checkTime,
      'method': method,
      'created_at': checkTime,
    };

    // Hive retourne la clé (ID) auto-incrémentée
    int id = await box.add(data);
    print('💾 Sauvegarde pointage PENDING (Hive): $checkTime (ID: $id)');
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
    results.sort((a, b) => a['check_time'].compareTo(b['check_time']));
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
    results.sort((a, b) => b['check_time'].compareTo(a['check_time']));
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
      final dateLocal = DateTime.parse(localPointage!['check_time']);
      final dateSupabase = DateTime.parse(supabasePointage!['check_time']);
      if (dateLocal.isAfter(dateSupabase)) return localPointage;
      else return supabasePointage;
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
    final pinHash = SecurityService.hasherPin(pin);

    try {
      var found = box.values.firstWhere((e) {
        var emp = Map<String, dynamic>.from(e);
        return emp['enterprise_id'] == enterpriseId &&
            emp['matricule'] == matricule &&
            emp['pin_hash'] == pinHash;
      });
      return Map<String, dynamic>.from(found);
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
    var box = Hive.box('employees_cache');

    try {
      var found = box.values.firstWhere((e) {
        var emp = Map<String, dynamic>.from(e);
        return emp['enterprise_id'] == enterpriseId &&
            (emp['qr_token'] == qrCode || emp['matricule'] == qrCode);
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
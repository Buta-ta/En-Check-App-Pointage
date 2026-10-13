import 'package:supabase_flutter/supabase_flutter.dart';
import 'security_service.dart';
import 'trusted_punch_service.dart';
import 'local_database.dart';
import 'dart:convert';
import 'dart:typed_data';

class SupabaseService {
  static const String supabaseUrl = 'https://cxggndvhwdolbtyezjde.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_QqawhPWeRKGvJOGXIopvJQ_gSkSCk0T';

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  // 🛠️ FONCTION UTILITAIRE POUR NORMALISER LES DONNÉES
  static Map<String, dynamic> _normaliserEmployee(Map<String, dynamic> data) {
    final cleanData = Map<String, dynamic>.from(data);
    if (cleanData.containsKey('employee_schedules')) {
      final schedule = cleanData['employee_schedules'];
      if (schedule is Map) {
        cleanData['employee_schedules'] = [schedule];
      } else if (schedule == null) {
        cleanData['employee_schedules'] = [];
      }
    }
    return cleanData;
  }

  // ═══════════════════════════════════════════════════════════
  // 🏢 RÉCUPÉRER LES ENTREPRISES
  // ═══════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getEntreprises() async {
    try {
      final response = await client
          .from('enterprises')
          .select()
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Erreur récupération entreprises: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 👥 RÉCUPÉRER LES EMPLOYÉS
  // ═══════════════════════════════════════════════════════════
  static Future<List<dynamic>> getEmployeesParEntreprise(String enterpriseId) async {
    try {
      final response = await client
          .from('employees_public')
          .select('*, employee_schedules(*, work_schedules(*))')
          .eq('enterprise_id', enterpriseId)
          .eq('is_active', true);
      final List<dynamic> rawList = response as List<dynamic>;
      return rawList.map((e) => _normaliserEmployee(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Erreur récupération employés: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔐 VÉRIFIER EMPLOYÉ (PIN)
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> verifierEmployee(
      String enterpriseId,
      String matricule,
      String pin,
      ) async {
    try {
      final reponse = await client.rpc('encheck_employee_login', params: {
        'p_enterprise_id': enterpriseId,
        'p_matricule': matricule,
        'p_pin': pin,
        'p_device_id': await TrustedPunchService.deviceId(),
      });

      final resultat = reponse is String
          ? jsonDecode(reponse) as Map<String, dynamic>
          : Map<String, dynamic>.from(reponse as Map);

      if (resultat['ok'] != true) {
        print('Connexion refuse: ' + resultat['raison'].toString());
        return null;
      }

      final empLocal = Map<String, dynamic>.from(resultat['employee'] as Map);
      await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, pin);
      await TrustedPunchService.enregistrerJeton(resultat['jeton'] as String?);
      return _normaliserEmployee(Map<String, dynamic>.from(resultat['employee'] as Map));
    } catch (e) {
      print('Erreur verification: ' + e.toString());
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📷 VÉRIFIER EMPLOYÉ (QR CODE)
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> verifierEmployeeParQR(
      String enterpriseId,
      String qrCode, {
        String? pin,
      }) async {
    try {
      final reponse = await client.rpc('encheck_employee_login_qr', params: {
        'p_enterprise_id': enterpriseId,
        'p_code': qrCode,
        if (pin != null) 'p_pin': pin,
        'p_device_id': await TrustedPunchService.deviceId(),
      });

      final resultat = reponse is String
          ? jsonDecode(reponse) as Map<String, dynamic>
          : Map<String, dynamic>.from(reponse as Map);

      if (resultat['ok'] != true) {
        print('Badge refuse: ' + resultat['raison'].toString());
        return null;
      }

      final empLocal = Map<String, dynamic>.from(resultat['employee'] as Map);
      await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, qrCode, parQr: true);
      if (pin != null && pin.isNotEmpty) {
        await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, pin);
      }
      await TrustedPunchService.enregistrerJeton(resultat['jeton'] as String?);
      return _normaliserEmployee(Map<String, dynamic>.from(resultat['employee'] as Map));
    } catch (e) {
      print('Erreur verification QR: ' + e.toString());
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ⏰ ENREGISTRER POINTAGE
  // ═══════════════════════════════════════════════════════════
  static Future<bool> enregistrerPointage({
    required String employeeId,
    required String enterpriseId,
    required String checkType,
    String method = 'pin',
    int? delaiSecondes,
    String? clientRef,
    DateTime? ancreUtc,
  }) async {
    try {
      final resultat = await TrustedPunchService.pointer(
        employeeId:    employeeId,
        enterpriseId:  enterpriseId,
        checkType:     checkType,
        method:        method,
        clientRef:     clientRef,
        delaiSecondes: delaiSecondes,
        ancreUtc:      ancreUtc,
      );
      return resultat['ok'] == true;
    } catch (e) {
      print('Erreur pointage Supabase: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ⏰ ENREGISTRER POINTAGE (AVEC RETOUR ID)
  // ═══════════════════════════════════════════════════════════
  static Future<String?> enregistrerPointageAvecId({
    required String employeeId,
    required String enterpriseId,
    required String checkType,
    String method = 'pin',
    int? delaiSecondes,
    String? clientRef,
    DateTime? ancreUtc,
  }) async {
    try {
      final resultat = await TrustedPunchService.pointer(
        employeeId:    employeeId,
        enterpriseId:  enterpriseId,
        checkType:     checkType,
        method:        method,
        clientRef:     clientRef,
        delaiSecondes: delaiSecondes,
        ancreUtc:      ancreUtc,
      );
      if (resultat['ok'] == true) return resultat['attendance_id'] as String?;
      return null;
    } catch (e) {
      print('Erreur pointage Supabase: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 HISTORIQUE POINTAGES
  // ═══════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getHistoriquePointages(
      String employeeId, {
        int limite = 50,
      }) async {
    try {
      final response = await client
          .from('attendances')
          .select()
          .eq('employee_id', employeeId)
          .order('check_time', ascending: false)
          .limit(limite);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Erreur historique: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 DERNIER POINTAGE
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> dernierPointage(String employeeId) async {
    try {
      final response = await client
          .from('attendances')
          .select()
          .eq('employee_id', employeeId)
          .order('check_time', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Erreur dernier pointage: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🤖 RECONNAISSANCE FACIALE — ENRÔLEMENT
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> creerEnrolement({
    required String employeeId,
    required String enterpriseId,
    required List<double> embedding,
    required String enrollmentPhotoUrl,
    required bool adminApprovalRequired,
  }) async {
    try {
      final status = adminApprovalRequired ? 'pending' : 'approved';
      final reponse = await client.rpc('encheck_visage_enroler', params: {
        'p_jeton': TrustedPunchService.jeton,
        'p_visage': embedding,
        'p_photo_url': enrollmentPhotoUrl,
        'p_statut': status,
      });
      if (reponse is Map && reponse['ok'] == true) {
        return Map<String, dynamic>.from(reponse);
      }
      print('⚠️ Enrôlement refusé par le serveur: ${reponse is Map ? reponse["reason"] : reponse}');
      return null;
    } catch (e) {
      print('❌ Erreur création enrôlement: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 RECONNAISSANCE FACIALE — ENRÔLEMENT ACTIF
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> getEnrolementActif(String employeeId) async {
    try {
      final reponse = await client.rpc('encheck_visage_lister', params: {
        'p_jeton': TrustedPunchService.jeton,
      });
      if (reponse is Map && reponse['ok'] == true) {
        final liste = (reponse['enrolements'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) =>
        e['employee_id'] == employeeId &&
            e['is_active'] == true &&
            e['status'] == 'approved')
            .toList();
        return liste.isEmpty ? null : liste.first;
      }
      print('⚠️ Enrôlement refusé par le serveur: ${reponse is Map ? reponse["reason"] : reponse}');
      return null;
    } catch (e) {
      print('❌ Erreur récupération enrôlement actif: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 RECONNAISSANCE FACIALE — STATUT ENRÔLEMENT
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> getStatutEnrolement(String employeeId) async {
    try {
      final reponse = await client.rpc('encheck_visage_lister', params: {
        'p_jeton': TrustedPunchService.jeton,
      });
      if (reponse is Map && reponse['ok'] == true) {
        final liste = (reponse['enrolements'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) => e['employee_id'] == employeeId && e['is_active'] == true)
            .toList();
        if (liste.isEmpty) return null;
        final e = liste.first;
        return {'id': e['id'], 'status': e['status'], 'created_at': e['created_at']};
      }
      print('⚠️ Statut enrôlement refusé par le serveur: ${reponse is Map ? reponse["reason"] : reponse}');
      return null;
    } catch (e) {
      print('❌ Erreur statut enrôlement: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ⚙️ RECONNAISSANCE FACIALE — CONFIGURATION
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> getConfigRecoFaciale(String enterpriseId) async {
    try {
      final reponse = await client.rpc('encheck_config_visage', params: {
        'p_jeton': TrustedPunchService.jeton,
      });
      if (reponse is Map && reponse['ok'] == true && reponse['config'] != null) {
        return Map<String, dynamic>.from(reponse['config'] as Map);
      }
      return {
        'confidence_threshold': 0.80,
        'liveness_required': true,
        'admin_approval_required': true,
        'fallback_allowed': true,
        'max_attempts': 3,
        'kiosk_mode_enabled': false,
        'pointage_mode': 'free',
      };
    } catch (e) {
      print('❌ Erreur config reco faciale: $e');
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
  }

  // ═══════════════════════════════════════════════════════════
  // 📸 RECONNAISSANCE FACIALE — UPLOAD PHOTO ENRÔLEMENT
  // ═══════════════════════════════════════════════════════════
  static Future<String?> uploadPhotoEnrolement({
    required List<int> photoBytes,
    required String enterpriseId,
    required String employeeId,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${enterpriseId}/${employeeId}_$timestamp.jpg';
      await client.storage
          .from('face-enrollments')
          .uploadBinary(
        fileName,
        Uint8List.fromList(photoBytes),
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      );
      final url = client.storage
          .from('face-enrollments')
          .getPublicUrl(fileName);
      return url;
    } catch (e) {
      print('❌ Erreur upload photo enrôlement: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📝 RECONNAISSANCE FACIALE — LOG TENTATIVE
  // ═══════════════════════════════════════════════════════════
  static Future<void> loggerTentativeFaciale({
    required String enterpriseId,
    String? employeeId,
    double? score,
    required bool matched,
    bool? livenessPassee,
    String? deviceId,
  }) async {
    try {
      await client.rpc('encheck_visage_journaliser', params: {
        'p_jeton': TrustedPunchService.jeton,
        'p_score': score,
        'p_matched': matched,
        'p_liveness_passe': livenessPassee,
        'p_device_id': deviceId,
      });
    } catch (e) {
      print('⚠️ Erreur log tentative faciale: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ⏰ ENREGISTRER POINTAGE AVEC DONNÉES FACIALES
  // ═══════════════════════════════════════════════════════════
  static Future<String?> enregistrerPointageFacial({
    required String employeeId,
    required String enterpriseId,
    required String checkType,
    required double faceScore,
    required bool livenessPassee,
    required int faceAttempts,
    String? geofenceId,
    double? locationLat,
    double? locationLng,
    double? gpsAccuracy,
    int? distanceMeters,
    bool? isWithinZone,
  }) async {
    try {
      final resultat = await TrustedPunchService.pointer(
        employeeId: employeeId,
        enterpriseId: enterpriseId,
        checkType: checkType,
        method: 'face',
        latitude: locationLat,
        longitude: locationLng,
        gpsAccuracy: gpsAccuracy,
        geofenceId: geofenceId,
        distanceMeters: distanceMeters,
        isWithinZone: isWithinZone,
        faceScore: faceScore,
        faceVerified: true,
        livenessPasse: livenessPassee,
        faceAttempts: faceAttempts,
      );
      if (resultat['ok'] == true) return resultat['attendance_id'] as String?;
      print('❌ Pointage facial refusé: ${resultat['reason']}');
      return null;
    } catch (e) {
      print('❌ Erreur pointage facial: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🤖 CHARGER TOUS LES EMBEDDINGS APPROUVÉS (MODE TABLETTE)
  // ═══════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getTousEnrolementsApprouves(
      String enterpriseId) async {
    try {
      final reponse = await client.rpc('encheck_visage_lister', params: {
        'p_jeton': TrustedPunchService.jeton,
      });
      if (reponse is Map && reponse['ok'] == true) {
        final tous = (reponse['enrolements'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) =>
        e['status'] == 'approved' &&
            e['is_active'] == true &&
            e['face_embedding'] != null)
            .toList();
        print('✅ ${tous.length} visage(s) de référence chargé(s) depuis le serveur');
        return tous;
      }
      print('⚠️ Visages refusés par le serveur: ${reponse is Map ? reponse['reason'] : reponse}');
      return [];
    } catch (e) {
      print('❌ Erreur chargement embeddings: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 👤 CHARGER UN EMPLOYÉ PAR ID
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> getEmployeeParId(String employeeId) async {
    try {
      final response = await client
          .from('employees_public')
          .select('*, enterprises(*), employee_schedules(*, work_schedules(*))')
          .eq('id', employeeId)
          .eq('is_active', true)
          .maybeSingle();
      if (response == null) return null;
      return _normaliserEmployee(response);
    } catch (e) {
      print('❌ Erreur chargement employé: $e');
      return null;
    }
  }
}

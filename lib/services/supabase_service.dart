import 'package:supabase_flutter/supabase_flutter.dart';
import 'security_service.dart';
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
          .from('employees')
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
      final pinHash = SecurityService.hasherPin(pin);

      final response = await client
          .from('employees')
          .select('*, enterprises(*), employee_schedules(*, work_schedules(*))')
          .eq('enterprise_id', enterpriseId)
          .eq('matricule', matricule)
          .eq('pin_hash', pinHash)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return null;
      return _normaliserEmployee(response);
    } catch (e) {
      print('Erreur vérification: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📷 VÉRIFIER EMPLOYÉ (QR CODE)
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> verifierEmployeeParQR(
      String enterpriseId,
      String qrCode,
      ) async {
    try {
      var response = await client
          .from('employees')
          .select('*, enterprises(*), employee_schedules(*, work_schedules(*))')
          .eq('enterprise_id', enterpriseId)
          .eq('qr_token', qrCode)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        response = await client
            .from('employees')
            .select('*, enterprises(*), employee_schedules(*, work_schedules(*))')
            .eq('enterprise_id', enterpriseId)
            .eq('matricule', qrCode)
            .eq('is_active', true)
            .maybeSingle();
      }

      if (response == null) return null;
      return _normaliserEmployee(response);
    } catch (e) {
      print('Erreur vérification QR: $e');
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
    String? checkTimeOverride,
  }) async {
    try {
      final checkTime = checkTimeOverride ?? DateTime.now().toIso8601String();

      await client.from('attendances').insert({
        'employee_id': employeeId,
        'enterprise_id': enterpriseId,
        'check_type': checkType,
        'method': method,
        'check_time': checkTime,
      });

      return true;
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
    String? checkTimeOverride,
  }) async {
    try {
      final checkTime = checkTimeOverride ?? DateTime.now().toIso8601String();

      final response = await client.from('attendances').insert({
        'employee_id': employeeId,
        'enterprise_id': enterpriseId,
        'check_type': checkType,
        'method': method,
        'check_time': checkTime,
      }).select('id').single();

      return response['id'] as String;
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

      final response = await client
          .from('face_enrollments')
          .insert({
        'employee_id': employeeId,
        'enterprise_id': enterpriseId,
        'face_embedding': embedding,
        'enrollment_photo_url': enrollmentPhotoUrl,
        'status': status,
        'is_active': true,
      })
          .select()
          .single();

      return response;
    } catch (e) {
      print('❌ Erreur création enrôlement: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getEnrolementActif(
      String employeeId) async {
    try {
      final response = await client
          .from('face_enrollments')
          .select()
          .eq('employee_id', employeeId)
          .eq('is_active', true)
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ Erreur récupération enrôlement: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getStatutEnrolement(
      String employeeId) async {
    try {
      final response = await client
          .from('face_enrollments')
          .select('id, status, created_at')
          .eq('employee_id', employeeId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ Erreur statut enrôlement: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ⚙️ RECONNAISSANCE FACIALE — CONFIGURATION
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getConfigRecoFaciale(
      String enterpriseId) async {
    try {
      final response = await client
          .from('face_recognition_config')
          .select()
          .eq('enterprise_id', enterpriseId)
          .maybeSingle();

      if (response != null) return response;

      // Config par défaut
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
      await client.from('face_recognition_logs').insert({
        'enterprise_id': enterpriseId,
        'employee_id': employeeId,
        'score': score,
        'matched': matched,
        'liveness_passed': livenessPassee,
        'device_id': deviceId,
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
      final Map<String, dynamic> data = {
        'employee_id': employeeId,
        'enterprise_id': enterpriseId,
        'check_type': checkType,
        'method': 'face',
        'check_time': DateTime.now().toIso8601String(),
        'face_score': faceScore,
        'face_verified': true,
        'liveness_passed': livenessPassee,
        'face_attempts': faceAttempts,
      };

      // Données GPS si disponibles
      if (locationLat != null) data['location_lat'] = locationLat;
      if (locationLng != null) data['location_lng'] = locationLng;
      if (gpsAccuracy != null) data['gps_accuracy'] = gpsAccuracy;
      if (geofenceId != null) data['geofence_id'] = geofenceId;
      if (distanceMeters != null) data['distance_meters'] = distanceMeters;
      if (isWithinZone != null) data['is_within_zone'] = isWithinZone;

      final response = await client
          .from('attendances')
          .insert(data)
          .select('id')
          .single();

      return response['id'] as String;
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
      final response = await client
          .from('face_enrollments')
          .select('id, employee_id, face_embedding')
          .eq('enterprise_id', enterpriseId)
          .eq('status', 'approved')
          .eq('is_active', true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Erreur chargement embeddings: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
// 👤 CHARGER UN EMPLOYÉ PAR ID
// ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>?> getEmployeeParId(
      String employeeId) async {
    try {
      final response = await client
          .from('employees')
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
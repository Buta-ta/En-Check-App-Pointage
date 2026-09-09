import 'package:supabase_flutter/supabase_flutter.dart';
import 'security_service.dart';
import 'trusted_punch_service.dart';
import 'local_database.dart';   // ⭐ LIVRAISON 13 : vérificateur hors-ligne
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
          // ⭐ LIVRAISON 13 — on lit la VUE PUBLIQUE, pas la table : elle expose
          //    tout sauf les hachages. La 12b a fermé `pin_hash` à la clé publique ;
          //    un `select('*')` sur la table échouerait donc.
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
  // ⭐ LIVRAISON 11 — LE PIN EST VÉRIFIÉ PAR LE SERVEUR.
  //
  // Avant : l'application hachait le PIN elle-même et envoyait le HACHAGE
  // comme mot de passe. Or le sel du hachage est écrit en dur dans
  // l'application et identique pour tous : un PIN de 4 chiffres se retrouvait
  // en 11 millisecondes. Un hachage lisible valait donc le PIN en clair.
  //
  // Maintenant : le PIN part tel quel, il ne circule que sur HTTPS vers la
  // seule fonction qui sait le comparer, la vérification a lieu dans la base
  // avec un sel unique par employé — et la réponse ne contient jamais
  // pin_hash, password_hash ni qr_token.
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
        // ⭐ LIVRAISON 12 : le jeton que le serveur va remettre sera lié à CET
        //    appareil. Rejouer ce jeton depuis un autre appareil est refusé.
        'p_device_id': await TrustedPunchService.deviceId(),
      });

      final resultat = reponse is String
          ? jsonDecode(reponse) as Map<String, dynamic>
          : Map<String, dynamic>.from(reponse as Map);

      if (resultat['ok'] != true) {
        // Motifs : identifiants_incorrects, trop_de_tentatives,
        // pin_non_configure, identifiants_manquants, entreprise_manquante.
        print('Connexion refuse: ' + resultat['raison'].toString());
        return null;
      }

      // ⭐ LIVRAISON 13 — le PIN vient d'être PROUVÉ par le serveur : c'est le
      //    bon moment pour fabriquer le vérificateur hors-ligne de CET appareil.
      //    Le hachage du serveur, lui, ne descend jamais ici.
      final empLocal = Map<String, dynamic>.from(resultat['employee'] as Map);
      await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, pin);

      // ⭐ LIVRAISON 12 — le serveur vient de remettre un jeton de session : c'est
      //    lui qui portera l'identité au moment du pointage. On le range dans la
      //    boîte locale, où il survivra aux redémarrages.
      await TrustedPunchService.enregistrerJeton(resultat['jeton'] as String?);

      return _normaliserEmployee(
          Map<String, dynamic>.from(resultat['employee'] as Map));
    } catch (e) {
      print('Erreur verification: ' + e.toString());
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📷 VÉRIFIER EMPLOYÉ (QR CODE)
  // ═══════════════════════════════════════════════════════════
  // ⭐ LIVRAISON 11 — LE BADGE PORTE UN VRAI SECRET.
  //
  // Avant : si le code scanné ne correspondait à aucun jeton, l'application
  // réessayait avec le MATRICULE SEUL et acceptait. Comme le QR imprimé
  // contenait justement le matricule, photographier un badge suffisait pour
  // pointer à la place de son collègue.
  //
  // Maintenant : le badge porte son jeton (qr_token), qui est un secret et
  // peut être remplacé. Un matricule seul est refusé — sauf si le PIN
  // accompagne (paramètre optionnel `pin`, à transmettre depuis l'écran).
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
        // ⭐ LIVRAISON 12 : le jeton sera lié à CET appareil.
        'p_device_id': await TrustedPunchService.deviceId(),
      });

      final resultat = reponse is String
          ? jsonDecode(reponse) as Map<String, dynamic>
          : Map<String, dynamic>.from(reponse as Map);

      if (resultat['ok'] != true) {
        // « pin_requis » : le code scanné est un matricule, pas un jeton de
        // badge. L'écran devrait alors demander le PIN et rappeler la méthode.
        print('Badge refuse: ' + resultat['raison'].toString());
        return null;
      }

      // ⭐ LIVRAISON 13 — le badge vient d'être PROUVÉ : on retient de quoi le
      //    reconnaître hors-ligne (l'empreinte du code, JAMAIS le code).
      final empLocal = Map<String, dynamic>.from(resultat['employee'] as Map);
      await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, qrCode,
          parQr: true);
      if (pin != null && pin.isNotEmpty) {
        await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, pin);
      }

      // ⭐ LIVRAISON 12 — le serveur vient de remettre un jeton de session : c'est
      //    lui qui portera l'identité au moment du pointage. On le range dans la
      //    boîte locale, où il survivra aux redémarrages.
      await TrustedPunchService.enregistrerJeton(resultat['jeton'] as String?);

      return _normaliserEmployee(
          Map<String, dynamic>.from(resultat['employee'] as Map));
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
      // ⭐ LIVRAISON 09 : c'est le SERVEUR qui fixe l'heure du pointage.
      //    Le téléphone ne peut plus que déclarer « il y a X secondes ».
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
      // ⭐ LIVRAISON 09 : heure décidée par le serveur
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

      // ⭐ LIVRAISON 14 — l'enrôlement passe par le SERVEUR, et c'est le JETON
      //    qui dit pour QUI on enrôle. Avant, `employee_id` était un simple
      //    paramètre : la clé publique pouvait enrôler n'importe quel visage sous
      //    n'importe quelle identité — et la reconnaissance faciale, censée être le
      //    contrôle le plus fort, validait ensuite ce visage.
      final reponse = await client.rpc('encheck_visage_enroler', params: {
        'p_jeton':     TrustedPunchService.jeton,
        'p_visage':    embedding,
        'p_photo_url': enrollmentPhotoUrl,
        'p_statut':    status,
      });

      if (reponse is Map && reponse['ok'] == true) {
        return Map<String, dynamic>.from(reponse);
      }
      print('⚠️ Enrôlement refusé par le serveur : '
          '${reponse is Map ? reponse['reason'] : reponse}');
      return null;
    } catch (e) {
      print('❌ Erreur création enrôlement: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getEnrolementActif(
      String employeeId) async {
    try {
      // ⭐ LIVRAISON 16 — lecture par le SERVEUR. La table `face_enrollments` est
      //    sous RLS et la clé publique n'a AUCUN droit de lecture : cette requête
      //    ne renvoyait rien (et le contrôle facial n'avait donc aucun visage de
      //    référence pour comparer). Le jeton dit à quelle entreprise on
      //    appartient ; le serveur ne renvoie que la sienne.
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
        // le serveur trie du plus récent au plus ancien
        return liste.isEmpty ? null : liste.first;
      }
      print('⚠️ Enrôlement refusé par le serveur : ${reponse is Map ? reponse['reason'] : reponse}');
      return null;
    } catch (e) {
      print('❌ Erreur récupération enrôlement: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getStatutEnrolement(
      String employeeId) async {
    try {
      // ⭐ LIVRAISON 16 — même raison que ci-dessus : la lecture directe ne
      //    renvoyait rien. On passe par le serveur et on filtre sur place.
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
      print('⚠️ Statut d''enrôlement refusé par le serveur : ${reponse is Map ? reponse['reason'] : reponse}');
      return null;
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
      // ⭐ LIVRAISON 16 — la configuration aussi passe par le serveur : sinon les
      //    réglages de l'entreprise (seuil de confiance, approbation obligatoire,
      //    droit de repli) étaient ignorés au profit des valeurs par défaut.
      final reponse = await client.rpc('encheck_config_visage', params: {
        'p_jeton': TrustedPunchService.jeton,
      });

      if (reponse is Map && reponse['ok'] == true && reponse['config'] != null) {
        return Map<String, dynamic>.from(reponse['config'] as Map);
      }

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
      // ⭐ LIVRAISON 14 — le journal passe aussi par le serveur. Même sans jeton
      //    valable la tentative est notée (une trace vaut mieux qu'un silence),
      //    mais elle l'est alors SANS identité : on ne peut plus inscrire une
      //    tentative au nom de quelqu'un d'autre.
      await client.rpc('encheck_visage_journaliser', params: {
        'p_jeton':          TrustedPunchService.jeton,
        'p_score':          score,
        'p_matched':        matched,
        'p_liveness_passe': livenessPassee,
        'p_device_id':      deviceId,
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
      // ⭐ LIVRAISON 09 : heure décidée par le serveur, y compris en reconnaissance faciale
      final resultat = await TrustedPunchService.pointer(
        employeeId:     employeeId,
        enterpriseId:   enterpriseId,
        checkType:      checkType,
        method:         'face',
        latitude:       locationLat,
        longitude:      locationLng,
        gpsAccuracy:    gpsAccuracy,
        geofenceId:     geofenceId,
        distanceMeters: distanceMeters,
        isWithinZone:   isWithinZone,
        faceScore:      faceScore,
        faceVerified:   true,
        livenessPasse:  livenessPassee,
        faceAttempts:   faceAttempts,
      );

      if (resultat['ok'] == true) return resultat['attendance_id'] as String?;
      print('❌ Pointage facial refusé : ${resultat['reason']}');
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
      // ⭐ LIVRAISON 16 — ⭐⭐ C'EST LA LECTURE LA PLUS IMPORTANTE : la tablette
      //    télécharge ici TOUS les visages de référence avant de comparer. Sans
      //    droit de lecture, cette liste était VIDE : le contrôle facial ne
      //    pouvait reconnaître personne, tout en ayant l'air de fonctionner.
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
      print('⚠️ Visages refusés par le serveur : ${reponse is Map ? reponse['reason'] : reponse}');
      return [];
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
          // ⭐ LIVRAISON 13 — on lit la VUE PUBLIQUE, pas la table : elle expose
          //    tout sauf les hachages. La 12b a fermé `pin_hash` à la clé publique ;
          //    un `select('*')` sur la table échouerait donc.
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
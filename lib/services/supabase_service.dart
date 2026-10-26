import 'package:supabase_flutter/supabase_flutter.dart';
import 'security_service.dart';
import 'trusted_punch_service.dart';
import 'local_database.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class SupabaseService {
  static const String supabaseUrl = 'https://cxggndvhwdolbtyezjde.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_QqawhPWeRKGvJOGXIopvJQ_gSkSCk0T';

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  // ═══════════════════════════════════════════════════════════
  // 🩺 TRADUIRE UNE ERREUR SUPABASE EN PHRASE LISIBLE
  // ═══════════════════════════════════════════════════════════
  /// LE PIÈGE QUE CETTE FONCTION ÉVITE : un refus d'autorisation n'est pas une
  /// panne de réseau. Quand la table `enterprises` n'a pas de GRANT SELECT pour
  /// le rôle `anon`, Supabase répond `401` avec `permission denied for table
  /// enterprises` (SQLSTATE 42501) — et l'écran d'accueil disait alors
  /// « Erreur de connexion internet ». L'administrateur partait vérifier sa
  /// box alors que le correctif est un GRANT SQL côté base de données.
  ///
  /// La distinction se fait sur le SQLSTATE et le texte de l'erreur, car
  /// PostgREST renvoie 401 à la fois pour une clé API invalide et pour un
  /// droit manquant : le code HTTP seul ne suffit pas à trancher.
  static String messageErreur(Object e) {
    final texte = e.toString().toLowerCase();

    // 42501 : le rôle n'a pas le droit sur l'objet. Correctif = SQL, pas réseau.
    if (texte.contains('42501') || texte.contains('permission denied')) {
      return 'Accès refusé par la base de données : les droits de lecture '
          'manquent pour l\'application de pointage. Correctif à appliquer '
          'dans l\'éditeur SQL Supabase (voir supabase/migrations).';
    }

    // Clé API absente, révoquée, ou projet Supabase différent.
    if (texte.contains('401') ||
        texte.contains('invalid api key') ||
        texte.contains('jwt')) {
      return 'La clé d\'accès à la base de données n\'est pas acceptée. '
          'Vérifiez la clé anon dans lib/services/supabase_service.dart.';
    }

    // RLS : la requête passe mais aucune ligne n'est visible.
    if (texte.contains('row-level security') ||
        texte.contains('row level security')) {
      return 'La sécurité au niveau des lignes (RLS) bloque la lecture. '
          'Ajoutez une politique de lecture pour le rôle anon.';
    }

    if (texte.contains('404') || texte.contains('could not find the table')) {
      return 'Table introuvable côté serveur. Le schéma Supabase et '
          'l\'application ne correspondent pas.';
    }

    // Le reste : coupure réelle, DNS, timeout, hors-ligne.
    return 'Erreur de connexion internet';
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

  /// 💾 CONTRAT D'ACCÈS (25/10/2026) — cache de SESSION uniquement.
  ///
  /// L'ancien cache collectif (toute l'entreprise téléchargée en anonyme) a
  /// été supprimé : `employees_public` est fermé. On mémorise ici le profil
  /// tel que la RPC de connexion vient de le renvoyer — c'est ce qui permet
  /// au mode hors-ligne de retrouver les employés déjà identifiés sur cette
  /// tablette, et rien de plus.
  static Future<void> _mettreEnCacheSession(Map<String, dynamic> profil) async {
    try {
      await LocalDatabase.cacherEmployees([profil]);
    } catch (e) {
      print('⚠️ Cache session non écrit : $e');
    }
  }

  /// Dernière erreur d'accès aux données, en clair. `null` quand tout va bien.
  /// Sert à ne pas annoncer « téléchargé avec succès » après un échec :
  /// getEntreprises() renvoie une liste vide sur erreur, et le vide se
  /// confondait avec « cette base ne contient aucune entreprise ».
  static String? derniereErreur;

  // ═══════════════════════════════════════════════════════════
  // 🏢 RÉCUPÉRER LES ENTREPRISES
  // ═══════════════════════════════════════════════════════════
  /// 🏢 CATALOGUE PUBLIC — CONTRAT ÉTAPE 2 (25/10/2026)
  ///
  /// Remplace l'ancienne lecture directe de `enterprises` par la RPC
  /// `encheck_entreprises_publiques()` : entreprises ACTIVES uniquement,
  /// champs exacts id, name, logo_url, matricule_prefix, pointage_mode.
  /// `pointage_mode` vaut `null` sans configuration : conservé tel quel
  /// (jamais converti silencieusement en 'free' — consigne Admin).
  /// Les anciens droits directs sur `enterprises` seront retirés par
  /// l'équipe Admin après validation de cette bascule.
  static Future<List<Map<String, dynamic>>> getEntreprises() async {
    try {
      final reponse = await client.rpc('encheck_entreprises_publiques');
      final brut = reponse is String ? jsonDecode(reponse) : reponse;
      if (brut is! Map) {
        derniereErreur = 'Réponse du catalogue illisible';
        print('Erreur récupération entreprises: réponse illisible');
        return [];
      }
      if (brut['ok'] != true) {
        derniereErreur =
            'Catalogue refusé : ${brut['raison'] ?? 'raison inconnue'}';
        print('Erreur récupération entreprises: $derniereErreur');
        return [];
      }
      final liste = (brut['entreprises'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      derniereErreur = null;
      return liste;
    } catch (e) {
      derniereErreur = messageErreur(e);
      print('Erreur récupération entreprises: $e');
      print('   ↳ diagnostic: $derniereErreur');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 👤 PROFIL PAR JETON — CONTRAT ÉTAPE 2 (25/10/2026)
  // ═══════════════════════════════════════════════════════════

  /// 🔄 Profil de la session depuis le jeton applicatif.
  ///
  /// Le SERVEUR résout l'employé depuis le jeton — aucun identifiant client
  /// n'est envoyé (ni accepté). Le jeton n'est JAMAIS écrit dans un log.
  /// Retourne l'enveloppe serveur : `{ok:true, expire_le, employee}` ou
  /// `{ok:false, raison}`. Les erreurs techniques (réseau, SQL, fonction
  /// absente) reviennent en `{ok:false, erreur_technique}` — jamais
  /// transformées en succès ni en liste vide (contrat Admin).
  static Future<Map<String, dynamic>> getProfilJeton() async {
    final jeton = TrustedPunchService.jeton;
    if (jeton == null || jeton.isEmpty) {
      return {'ok': false, 'raison': 'jeton_invalide'};
    }
    try {
      final reponse = await client.rpc('encheck_employe_profil', params: {
        'p_jeton': jeton,
      });
      final brut = reponse is String ? jsonDecode(reponse) : reponse;
      if (brut is Map) return Map<String, dynamic>.from(brut);
      return {'ok': false, 'erreur_technique': 'Réponse illisible'};
    } catch (e) {
      return {'ok': false, 'erreur_technique': messageErreur(e)};
    }
  }

  /// 🎯 Rafraîchit la fiche de la session COURANTE (celle du jeton) si — et
  /// seulement si — elle correspond à [employeeIdAttendu]. Retourne la fiche
  /// fraîche (déjà mise en cache) ou `null`.
  ///
  /// [onRefus] reçoit la raison métier (jeton_expire, reauthentification_requise,
  /// jeton_revoque…) pour un message honnête. Les erreurs techniques restent
  /// silencieuses ici : chaque écran gère déjà les siennes.
  static Future<Map<String, dynamic>?> rafraichirProfilDeSession({
    required String employeeIdAttendu,
    void Function(String raison)? onRefus,
  }) async {
    try {
      final r = await getProfilJeton();
      if (r['ok'] == true && r['employee'] is Map) {
        final profil =
            _normaliserEmployee(Map<String, dynamic>.from(r['employee'] as Map));
        // Le jeton ne décrit que SON titulaire : s'il ne correspond pas à
        // l'employé concerné (ex. visage reconnu en mode borne), on n'écrase
        // rien — la fiche du scan reste la référence.
        if (profil['id'] != employeeIdAttendu) return null;
        await _mettreEnCacheSession(profil);
        return profil;
      }
      if (r['erreur_technique'] != null) return null; // technique : silencieux
      onRefus?.call((r['raison'] as String?) ?? 'inconnu');
      return null;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 👥 RÉCUPÉRER LES EMPLOYÉS — SUPPRIMÉ (contrat d'accès employés, 25/10/2026)
  // ═══════════════════════════════════════════════════════════
  //
  // getEmployeesParEntreprise() lisait la vue `employees_public` en anonyme.
  // Cette lecture est désormais interdite côté serveur (migration 011) et le
  // contrat Admin signé le 25/10 l'interdit de toute façon : le personnel ne
  // se télécharge plus en bloc. Le cache local ne reçoit QUE les profils
  // renvoyés par encheck_employee_login / encheck_employee_login_qr au moment
  // où quelqu'un s'identifie sur cette tablette (voir _mettreEnCacheSession).
  // La synchronisation collective viendra de encheck_borne_personnel
  // (appareil autorisé par l'administration).

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
        // Mauvais identifiants = parcours normal : ce n'est PAS une panne
        // d'accès aux données, on n'annonce donc aucune erreur de connexion.
        derniereErreur = null;
        print('Connexion refuse: ' + resultat['raison'].toString());
        return null;
      }

      final empLocal = Map<String, dynamic>.from(resultat['employee'] as Map);
      await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, pin);
      await TrustedPunchService.enregistrerJeton(resultat['jeton'] as String?);
      final profil =
          _normaliserEmployee(Map<String, dynamic>.from(resultat['employee'] as Map));
      // Contrat d'accès : le cache local ne reçoit QUE le profil de la
      // session en cours — jamais tout le personnel de l'entreprise.
      await _mettreEnCacheSession(profil);
      derniereErreur = null;
      return profil;
    } catch (e) {
      derniereErreur = messageErreur(e);
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
        // Mauvais badge = parcours normal : aucune erreur de connexion.
        derniereErreur = null;
        print('Badge refuse: ' + resultat['raison'].toString());
        return null;
      }

      final empLocal = Map<String, dynamic>.from(resultat['employee'] as Map);
      await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, qrCode, parQr: true);
      if (pin != null && pin.isNotEmpty) {
        await LocalDatabase.memoriserVerificateur(empLocal['id'] as String, pin);
      }
      await TrustedPunchService.enregistrerJeton(resultat['jeton'] as String?);
      final profil =
          _normaliserEmployee(Map<String, dynamic>.from(resultat['employee'] as Map));
      // Contrat d'accès : le cache local ne reçoit QUE le profil de la
      // session en cours — jamais tout le personnel de l'entreprise.
      await _mettreEnCacheSession(profil);
      derniereErreur = null;
      return profil;
    } catch (e) {
      derniereErreur = messageErreur(e);
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
  /// Les pointages d'un employé, lus par la fonction `encheck_pointages_historique`.
  ///
  /// POURQUOI NE PAS LIRE LA TABLE DIRECTEMENT
  /// -----------------------------------------
  /// La table `attendances` porte une politique de sécurité au niveau des
  /// lignes (RLS) nommée `encheck_scope_entreprise`, dont la condition est :
  ///
  ///     can_manage_enterprise(enterprise_id)
  ///
  /// Autrement dit : « tu ne vois cette ligne que si tu gères l'entreprise à
  /// laquelle elle appartient ». L'application de pointage est ANONYME — elle
  /// n'a pas de session administrateur — donc cette condition est fausse, et
  /// Postgres retire TOUTES les lignes.
  ///
  /// Le piège : une RLS qui refuse ne renvoie PAS d'erreur. Elle renvoie une
  /// liste vide. L'écran affichait donc « Aucun pointage », exactement comme
  /// pour une journée sans pointage. Rien ne permettait de deviner que les
  /// données existaient bel et bien.
  ///
  /// `encheck_pointages_historique` est déclarée SECURITY DEFINER : elle
  /// s'exécute avec ses propres droits et lit la table pour nous. Sa
  /// signature :
  ///
  ///     encheck_pointages_historique(p_employee_id uuid, p_limite integer)
  ///       → jsonb
  ///
  /// On ne touche donc PAS à la politique RLS : elle est correcte et protège
  /// les données. On emprunte simplement la porte prévue à cet effet.
  static Future<List<Map<String, dynamic>>> _pointagesViaRpc(
      String employeeId,
      int limite,
      ) async {
    final reponse = await client.rpc('encheck_pointages_historique', params: {
      'p_employee_id': employeeId,
      'p_limite': limite,
    });

    // Selon la version du client, une colonne jsonb arrive déjà décodée ou
    // sous forme de texte : on accepte les deux.
    final brut = reponse is String ? jsonDecode(reponse) : reponse;
    if (brut is! List) return <Map<String, dynamic>>[];

    return brut
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getHistoriquePointages(
      String employeeId, {
        int limite = 50,
      }) async {
    try {
      // Chemin unique : la fonction dédiée, non soumise à la RLS.
      // CONTRAT D'ACCÈS (25/10/2026) : plus de repli en lecture directe sur
      // `attendances` — un refus ne doit ni déclencher une lecture de secours
      // ni se transformer en historique vide présenté comme un succès.
      final viaRpc = await _pointagesViaRpc(employeeId, limite);
      derniereErreur = null;
      return viaRpc;
    } catch (e) {
      // L'écran lit `derniereErreur` et affiche l'échec : l'employé distingue
      // une journée sans pointage d'un problème de droits ou de réseau.
      derniereErreur = messageErreur(e);
      print('Erreur historique (RPC seule) : $e');
      print('   ↳ diagnostic: $derniereErreur');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 DERNIER POINTAGE
  // ═══════════════════════════════════════════════════════════

  /// Le pointage le plus récent de l'employé, ou `null`.
  ///
  /// ⚠️ Cette fonction décide si le prochain pointage sera une ENTRÉE ou une
  /// SORTIE. Bloquée par la RLS (voir _pointagesViaRpc), elle renvoyait
  /// toujours `null` : l'application croyait alors n'avoir aucun pointage
  /// et enregistrait une ENTRÉE à chaque passage.
  static Future<Map<String, dynamic>?> dernierPointage(String employeeId) async {
    // Chemin unique : la fonction dédiée. CONTRAT D'ACCÈS (25/10/2026) —
    // plus de repli en lecture directe sur `attendances`.
    try {
      final viaRpc = await _pointagesViaRpc(employeeId, 1);
      if (viaRpc.isNotEmpty) return viaRpc.first;
      return null;
    } catch (e) {
      print('Dernier pointage indisponible (RPC seule) : $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🧠 DÉCISION ENTRÉE / SORTIE
  // ═══════════════════════════════════════════════════════════
  //
  // Ces trois fonctions parlent au « cerveau » installé dans la base par le
  // script SYSTEME_IN_OUT.sql. Leur point commun : aucune n'est indispensable.
  // Si elles échouent ou si les fonctions n'existent pas sur un projet plus
  // ancien, l'application retombe sur son comportement d'avant. Rien ne casse
  // jamais à cause d'elles.

  /// Demande à la base quel type de pointage enregistrer.
  ///
  /// La réponse contient :
  ///   - `type`      : 'in' ou 'out'
  ///   - `confiance` : 'haute', 'moyenne' ou 'basse'
  ///   - `raison`    : la règle qui a décidé
  ///   - `anomalie`  : 'sortie_oubliee', 'presence_courte' ou null
  ///
  /// `null` est renvoyé en cas d'échec : l'appelant applique alors la bascule
  /// locale, comme avant.
  static Future<Map<String, dynamic>?> typeSuggere(String employeeId) async {
    try {
      final reponse = await client
          .rpc('encheck_type_suggere', params: {'p_employee_id': employeeId});

      final brut = reponse is String ? jsonDecode(reponse) : reponse;
      if (brut is Map) return Map<String, dynamic>.from(brut);
      return null;
    } catch (e) {
      print('Suggestion de type indisponible : $e');
      return null;
    }
  }

  /// Inscrit, sur un pointage déjà enregistré, comment la décision a été prise.
  ///
  /// Purement informatif : c'est ce qui permet à l'admin de retrouver les
  /// pointages décidés dans le doute. Un échec est sans conséquence — le
  /// pointage, lui, est déjà enregistré.
  static Future<void> marquerPointage({
    required String attendanceId,
    required String origine,
    String? raison,
    String? anomalie,
  }) async {
    try {
      await client.rpc('encheck_pointage_marquer', params: {
        'p_attendance_id': attendanceId,
        'p_origine': origine,
        'p_raison': raison,
        'p_anomalie': anomalie,
      });
    } catch (e) {
      print('Marquage du pointage impossible (sans conséquence) : $e');
    }
  }

  /// Corrige le type d'un pointage que l'employé vient d'enregistrer.
  ///
  /// La base garde trois garde-fous : le pointage doit exister, appartenir à
  /// l'employé, et dater de moins de 30 minutes. Au-delà, la correction passe
  /// par un administrateur.
  ///
  /// Chaque correction est inscrite dans `attendance_corrections` et lève le
  /// drapeau `modifie_par_employe` : l'admin la voit dans la page Pointages.
  static Future<Map<String, dynamic>?> corrigerType({
    required String attendanceId,
    required String employeeId,
    required String nouveauType,
  }) async {
    try {
      final reponse = await client.rpc('encheck_corriger_type', params: {
        'p_attendance_id': attendanceId,
        'p_employee_id': employeeId,
        'p_nouveau_type': nouveauType,
        // ⭐ Le jeton de session prouve que l'employé s'est bien identifié
        //    sur cet appareil il y a peu. Le serveur s'en sert comme
        //    troisième garde-fou (en plus de l'appartenance du pointage et
        //    du délai de 30 minutes). S'il manque, la fonction ne bloque pas.
        'p_jeton': TrustedPunchService.jeton,
      });

      final brut = reponse is String ? jsonDecode(reponse) : reponse;
      if (brut is Map) return Map<String, dynamic>.from(brut);
      return null;
    } catch (e) {
      print('Correction du type impossible : $e');
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
  /// 📋 RECONNAISSANCE FACIALE — ENRÔLEMENT ACTIF
  ///
  /// CONTRAT ÉTAPE 3 (26/10/2026) : lecture VISAGE V2, portée 'personne' —
  /// le jeton ne décrit que SON titulaire. En cas de refus : pas de repli sur
  /// l'ancienne RPC (v1) ni sur des lectures directes — jamais.
  static Future<Map<String, dynamic>?> getEnrolementActif(String employeeId) async {
    try {
      final reponse = await client.rpc('encheck_visage_lister_v2', params: {
        'p_jeton': TrustedPunchService.jeton,
        'p_portee': 'personne',
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
      print('⚠️ Enrôlement refusé par le serveur: ${reponse is Map ? reponse["raison"] ?? reponse["reason"] : reponse}');
      return null;
    } catch (e) {
      print('❌ Erreur récupération enrôlement actif: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📋 RECONNAISSANCE FACIALE — STATUT ENRÔLEMENT
  // ═══════════════════════════════════════════════════════════
  /// 📋 RECONNAISSANCE FACIALE — STATUT ENRÔLEMENT
  ///
  /// CONTRAT ÉTAPE 3 : visage V2, portée 'personne' (statuts propres du
  /// titulaire visibles). Refus → pas de repli sur la v1.
  static Future<Map<String, dynamic>?> getStatutEnrolement(String employeeId) async {
    try {
      final reponse = await client.rpc('encheck_visage_lister_v2', params: {
        'p_jeton': TrustedPunchService.jeton,
        'p_portee': 'personne',
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
      print('⚠️ Statut enrôlement refusé par le serveur: ${reponse is Map ? reponse["raison"] ?? reponse["reason"] : reponse}');
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
        'pointage_mode': null,
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
        'pointage_mode': null,
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📸 PHOTO D'ENRÔLEMENT — SERVICE PHOTOS (Edge, contrat étape 3)
  // ═══════════════════════════════════════════════════════════

  /// Envoi de la photo d'enrôlement via le service photos
  /// (`pointage-enrollment-photo`, action 'upload') — JETON PERSONNEL,
  /// jamais celui d'une borne. L'ancien uploadBinary/getPublicUrl est
  /// abandonné : le serveur impose chemin/entreprise/employé et retourne
  /// `photo_reference`, la seule valeur à stocker dans `enrollment_photo_url`
  /// (ni URL signée, ni URL publique).
  ///
  /// Quotas serveur : JPEG brut ≤ 2 MiB, corps ≤ 3 MiB, ≤ 8 MP — 10
  /// réservations par heure et par employé (un essai échoué après réservation
  /// consomme le quota). Codes : 400 format/image, 403 accès/jeton,
  /// 429 quota_photo, 503 indisponibilité / envoi NON confirmé.
  static Future<String?> uploadPhotoEnrolement({
    required List<int> photoBytes,
  }) async {
    final jeton = TrustedPunchService.jeton;
    if (jeton == null || jeton.isEmpty) {
      derniereErreur = 'Session absente — reconnectez-vous.';
      return null;
    }
    try {
      // Garantir un JPEG brut : le codec serveur refuse les autres formats.
      List<int> jpeg = photoBytes;
      final estDejaJpeg = photoBytes.length > 2 &&
          photoBytes[0] == 0xFF &&
          photoBytes[1] == 0xD8;
      if (!estDejaJpeg) {
        final decoded = img.decodeImage(Uint8List.fromList(photoBytes));
        if (decoded != null) {
          jpeg = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
        }
      }
      if (jpeg.length > 2 * 1024 * 1024) {
        derniereErreur = 'Photo trop lourde (max 2 Mo) — rapprochez-vous '
            'moins près ou réduisez la résolution.';
        return null;
      }
      final reponse = await client.functions.invoke(
        'pointage-enrollment-photo',
        body: {
          'action': 'upload',
          'p_jeton': jeton,
          'jpeg_base64': base64Encode(jpeg),
        },
      );
      final brut = reponse.data;
      if (reponse.status == 200 && brut is Map && brut['ok'] == true) {
        derniereErreur = null;
        return brut['photo_reference'] as String?;
      }
      derniereErreur = messageErreurPhoto(reponse.status, brut);
      print('❌ Upload photo enrôlement refusé (${reponse.status})');
      return null;
    } catch (e) {
      derniereErreur = 'Envoi de la photo impossible : $e';
      print('❌ Erreur upload photo enrôlement: $e');
      return null;
    }
  }

  /// 💬 Message honnête selon le code HTTP du service photos.
  /// En 503 : l'envoi n'est PAS confirmé — ne jamais affirmer l'enregistrement.
  static String messageErreurPhoto(int status, dynamic brut) {
    final detail = brut is Map
        ? (brut['message'] ?? brut['error'] ?? brut['raison'])
        : null;
    switch (status) {
      case 400:
        return 'Photo refusée (format ou image invalide)'
            '${detail != null ? ' — $detail' : ''}.';
      case 403:
        return 'Session refusée pour le service photos — reconnectez-vous.';
      case 429:
        return 'Quota de photos atteint (10 par heure et par employé) — '
            'réessayez plus tard.';
      case 503:
        return 'Service photos indisponible : l\'envoi n\'a PAS été '
            'confirmé, la photo n\'est pas enregistrée.';
      default:
        return 'Service photos en erreur ($status)'
            '${detail != null ? ' — $detail' : ''}.';
    }
  }

  /// 🔎 URL signée (300 s) d'une photo d'enrôlement appartenant au TITULAIRE
  /// du jeton (action 'read', jeton personnel). L'URL est un porteur :
  /// NE PAS la persister, la journaliser ni la partager. Les anciennes
  /// références public/authenticated .jpg restent acceptées côté serveur.
  static Future<String?> getUrlPhotoEnrolement(String enrollmentId) async {
    final jeton = TrustedPunchService.jeton;
    if (jeton == null || jeton.isEmpty) return null;
    try {
      final reponse = await client.functions.invoke(
        'pointage-enrollment-photo',
        body: {
          'action': 'read',
          'p_jeton': jeton,
          'enrollment_id': enrollmentId,
        },
      );
      final brut = reponse.data;
      if (reponse.status == 200 && brut is Map && brut['ok'] == true) {
        return brut['url'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ Erreur lecture photo enrôlement: $e');
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
  // SUPPRIMÉ (contrat étape 3, 26/10/2026) : l'ancienne lecture collective
  // passait par `encheck_visage_lister` (v1) avec un jeton PERSONNEL.
  // Le cache borne est désormais le SNAPSHOT COMPLET de
  // `encheck_borne_personnel` (jeton borne, remplacement intégral,
  // expiration cache_expire_le) — voir `BorneService.synchroniserPersonnel()`.
  // Aucun repli sur la v1.

  // ═══════════════════════════════════════════════════════════
  // 👤 CHARGER UN EMPLOYÉ PAR ID — SUPPRIMÉ (contrat d'accès 25/10/2026)
  // ═══════════════════════════════════════════════════════════
  // getEmployeeParId() lisait `employees_public` en anonyme : lecture
  // désormais interdite. La fiche vient du profil renvoyé par la RPC de
  // connexion (ou du cache de session) ; un ID fourni par le client n'est
  // de toute façon jamais une autorisation (contrat Admin du 25/10/2026).
}

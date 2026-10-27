// lib/screens/pointage_screen.dart
// ═══════════════════════════════════════════════════════════
// 📱 PAGE POINTAGE
// ═══════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/logo_empreinte.dart';
import '../widgets/qr_scanner_widget.dart';
import '../widgets/qr_photo_scanner_widget.dart';
import '../widgets/pin_photo_widget.dart';
import '../widgets/bandes_motifs.dart';
import '../widgets/web_camera_widget_provider.dart';
import '../services/supabase_service.dart';
import '../services/appareil_service.dart';
import '../services/borne_service.dart';
import '../services/local_database.dart';
import '../services/connectivity_service.dart';
import '../services/theme_service.dart';
import '../services/sync_service.dart';
import '../services/photo_service_interface.dart';
import '../services/geofencing_service.dart';
import '../services/heure_pointage.dart';   // ⭐ LIVRAISON 21
import '../services/pause_service.dart'; // ⏸ VISIBILITÉ DES PAUSES — le bouton du haut de l'écran
import '../services/trusted_punch_service.dart';   // ⭐ LIVRAISON 22
import 'historique_screen.dart';
import 'face_enrollment_screen.dart';
import 'face_pointage_screen.dart';
import '../services/face_recognition_service_provider.dart';
import 'package:geolocator/geolocator.dart'
if (dart.library.html) '../stubs/geolocator_stub.dart';

class PointageScreen extends StatefulWidget {
  const PointageScreen({super.key});

  @override
  State<PointageScreen> createState() => _PointageScreenState();
}

class _PointageScreenState extends State<PointageScreen> {
  String? _modeSelectionne;

  // ⏸ VISIBILITÉ DES PAUSES (17/10/2026)
  //    'pointage' → les gestes enregistrent un pointage (comme d'habitude).
  //    'pause'    → la prochaine identification sert à la PAUSE : le même
  //                 mode que le pointage (PIN / QR / visage), sans jamais
  //                 changer les habitudes de l'entreprise.
  String _intention = 'pointage';
  List<Map<String, dynamic>> _pausesOuvertes = [];
  Timer? _timerPauses;

  // 🔢 PIN
  String numeroMatricule = '';
  String codePin = '';
  bool afficherPin = false;

  // ⚙️ État général
  bool chargement = false;
  bool syncEnCours = false;
  bool chargementEntreprises = true;
  String heureActuelle = '';
  String dateActuelle = '';
  Timer? _timer;
  int pointagesEnAttente = 0;

  // 📷 Scanners
  bool _showScanner = false;
  bool _showPhotoScanner = false;
  bool _showPinPhoto = false;

  // 🌐 Web Camera
  bool _showWebCamera = false;
  String _webCameraRaison = 'pointage';
  Map<String, dynamic>? _pendingEmployeeWebCamera;

  // 🔐 Modules
  bool _moduleQRActif = false;
  bool _modulePhotoActif = false;
  bool _moduleGeofencingActif = false;
  bool _moduleRecoFacialeActif = false;

  // 🤖 Mode personnel
  bool _faceEnrolled = false;
  bool _faceApproved = false;
  String? _faceEmployeeId;
  String? _faceEmployeeName;

  // 🤖 Mode tablette
  bool _kioskMode = false;

  // 🖥️ Mode kiosque choisi à l'accueil (bouton « Mode kiosque ») :
  //    cet appareil est une borne, même sans bail `bk1_` ni config serveur.
  bool _modeKiosqueAppareil = false;

  /// 🖥️ CONTRAT ÉTAPE 3 — la borne est-elle authentifiée (bail `bk1_`
  /// valide) ? Le personnel se synchronise alors par `encheck_borne_personnel`.
  bool _bornePrete = false;
  String _kioskPhase = 'pointage';
  List<Map<String, dynamic>> _kioskEmployeesNonEnroles = [];
  int _kioskEnrolementIndex = 0;

  // 🤖 État écrans
  bool _showFacePointage = false;
  bool _showFaceEnrollment = false;

  Map<String, dynamic> _faceConfig = {
    'confidence_threshold': 0.80,
    'liveness_required': true,
    'admin_approval_required': true,
    'fallback_allowed': true,
    'max_attempts': 3,
    'kiosk_mode_enabled': false,
    'pointage_mode': null,
  };

  Map<String, dynamic>? _employeeEnAttente;

  // 🌍 Geofencing
  dynamic _currentPosition;
  Map<String, dynamic>? _verificationZone;
  bool _gpsVerifie = false;

  // 📊 Données
  Map<String, dynamic>? entrepriseSelectionnee;
  Map<String, dynamic>? _employeeSchedule;
  Map<String, dynamic>? _pendingEmployee;
  Map<String, dynamic>? _dernierEmployePointe;

  // 🔒 LIVRAISON 21 — VERROU ANTI-DOUBLE-GESTE.
  //    Retient l'employé dont le pointage est EN COURS d'enregistrement. Tant
  //    qu'il est là, aucun second pointage de CET employé n'est enregistré.
  //    Volontairement par employé : sur une tablette partagée, le pointage de
  //    l'employé suivant ne doit jamais être bloqué.
  String? _pointageEnCoursPour;

  @override
  void initState() {
    super.initState();
    _mettreAJourHeure();
    _compterPointagesEnAttente();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (timer) => _mettreAJourHeure());
    _initialiserApp();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerPauses?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 🚀 INITIALISATION
  // ═══════════════════════════════════════════════════════════

  Future<void> _initialiserApp() async {
    await _chargerModulesLocaux();
    await _chargerEntrepriseLocale();

    // ⏸ Bandeau des pauses : premier chargement + rafraîchissement doux
    //    (toutes les minutes) pour afficher les rappels « toujours en pause ? ».
    _chargerPausesOuvertes();
    _timerPauses = Timer.periodic(const Duration(minutes: 1), (_) {
      _chargerPausesOuvertes();
    });

    // ⭐ LIVRAISON 22 — demander au serveur le fuseau officiel de CETTE
    //    entreprise (et son décalage actuel). Volontairement SANS `await` :
    //    l'écran s'affiche tout de suite, l'horloge se corrige dès la réponse.
    _rafraichirFuseauEntreprise();
    if (_moduleRecoFacialeActif && entrepriseSelectionnee != null) {
      await _chargerConfigRecoFacialeEnLigne();
    }

    // 🖥️ CONTRAT ÉTAPE 3 — une tablette DÉJÀ provisionnée est une borne,
    //    même si la config serveur est injoignable ou exige un jeton employé :
    //    le bail `bk1_` en coffre sécurisé est la preuve, pas le réglage distant.
    if (await BorneService.aUnBailValide()) {
      if (mounted) setState(() => _kioskMode = true);
    }
  }

  Future<void> _chargerModulesLocaux() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _moduleQRActif = prefs.getBool('module_qr_scanner') ?? false;
      _modulePhotoActif = prefs.getBool('module_photo_pointage') ?? false;
      _moduleGeofencingActif =
          prefs.getBool('module_geolocalisation') ?? false;
      _moduleRecoFacialeActif =
          prefs.getBool('module_reconnaissance_faciale') ?? false;
      _faceEnrolled = prefs.getBool('face_enrolled') ?? false;
      _faceApproved = prefs.getBool('face_approved') ?? false;
      _faceEmployeeId = prefs.getString('face_employee_id');
      _faceEmployeeName = prefs.getString('face_employee_name');
    });

    // 🖥️ Mode kiosque choisi à l'accueil : cet appareil est une borne.
    if (prefs.getString('mode_appareil') == AppareilService.kiosque) {
      if (mounted) {
        setState(() {
          _modeKiosqueAppareil = true;
          _kioskMode = true;
        });
      }
    }

    if (_moduleRecoFacialeActif) {
      final configCache = await LocalDatabase.getConfigFaciale();
      if (configCache != null && mounted) {
        setState(() {
          _faceConfig = configCache;
          _kioskMode =
              (configCache['kiosk_mode_enabled'] as bool? ?? false) ||
              _modeKiosqueAppareil;
        });
      }
      FaceRecognitionService.initialiser();
    }
  }

  Future<void> _chargerConfigRecoFacialeEnLigne() async {
    if (!ConnectivityService.isOnline) return;
    if (entrepriseSelectionnee == null) return;

    try {
      final config = await SupabaseService.getConfigRecoFaciale(
          entrepriseSelectionnee!['id']);
      await LocalDatabase.sauvegarderConfigFaciale(config);
      final kioskMode = config['kiosk_mode_enabled'] as bool? ?? false;
      // 🖥️ CONTRAT ÉTAPE 3 — un défaut de config ne rétrograde JAMAIS une
      //    tablette déjà provisionnée : le bail `bk1_` garde le mode kiosque.
      final bailBorne = await BorneService.aUnBailValide();

      if (mounted) {
        setState(() {
          _faceConfig = config;
          _kioskMode = kioskMode || bailBorne || _modeKiosqueAppareil;
        });
      }

      if (kioskMode || bailBorne) {
        await _chargerTousEmbeddingsEntreprise();
        await _detecterEmployesNonEnroles();
      } else {
        if (_faceEnrolled && !_faceApproved && _faceEmployeeId != null) {
          await _verifierApprobationEnLigne();
        }
      }
    } catch (e) {
      // Garder cache
    }
  }

  Future<void> _chargerTousEmbeddingsEntreprise() async {
    if (!ConnectivityService.isOnline) return;
    if (entrepriseSelectionnee == null) return;

    // 🖥️ CONTRAT ÉTAPE 3 (26/10/2026) : le cache borne est le SNAPSHOT
    // COMPLET de encheck_borne_personnel (jeton borne `bk1_`, remplacement
    // intégral, expiration cache_expire_le). Aucun repli sur la v1 ni sur
    // des lectures directes en cas d'erreur.
    if (!await BorneService.aUnBailValide() && !await BorneService.aUnSecret()) {
      // Jamais provisionnée : le bandeau « Borne non autorisée » suffit,
      // pas de popup à chaque ouverture.
      if (mounted) setState(() => _bornePrete = false);
      return;
    }
    final resultat = await BorneService.synchroniserPersonnel();
    if (resultat['ok'] == true) {
      if (mounted) {
        setState(() {
          _bornePrete = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _bornePrete = false;
        });
        _afficherErreur(resultat['erreur'] ??
            'Synchronisation du personnel impossible.');
      }
    }
  }

  /// 🔎 Balayage collectif « qui n'a pas encore donné son visage ? ».
  ///
  /// CONTRAT ÉTAPE 3 : calculé depuis le SNAPSHOT de borne (personnel
  /// complet + embeddings approuvés actifs). Cache absent/expiré ou
  /// hors-ligne : aucun balayage et un message honnête — jamais de faux
  /// « Tous les employés sont déjà enrôlés ».
  Future<void> _detecterEmployesNonEnroles() async {
    List<Map<String, dynamic>> nonEnroles = [];
    String phase = 'pointage';

    if (ConnectivityService.isOnline &&
        entrepriseSelectionnee != null &&
        await BorneService.cacheValide()) {
      final employes = await LocalDatabase.getEmployeesCache();
      final embeddings =
          await LocalDatabase.getTousEmbeddings(entrepriseSelectionnee!['id']);
      final avecVisage = embeddings
          .map((e) => e['employee_id'] as String?)
          .whereType<String>()
          .toSet();
      nonEnroles = employes
          .where((e) =>
              e['is_active'] != false &&
              (e['id'] is String) &&
              !avecVisage.contains(e['id']))
          .toList();
    }

    if (mounted) {
      setState(() {
        _kioskEmployeesNonEnroles = nonEnroles;
        _kioskPhase = phase;
        _kioskEnrolementIndex = 0;
      });
    }
  }

  /// ⭐ LIVRAISON 22 — l'heure officielle de l'entreprise.
  ///
  /// Le serveur est le seul à connaître les règles de changement d'heure de
  /// chaque pays : on lui demande donc le fuseau de l'entreprise choisie, et
  /// HeurePointage s'en sert partout (historique, horloge, journées).
  /// En cas d'échec (hors-ligne, serveur pas encore équipé) : on garde ce
  /// qu'on savait déjà, et l'application affiche l'heure de la tablette.
  Future<void> _rafraichirFuseauEntreprise() async {
    final id = entrepriseSelectionnee?['id'] as String?;
    if (id == null) return;
    try {
      await TrustedPunchService.contacterServeur(enterpriseId: id);
      if (mounted) setState(() {});   // l'horloge et l'avis se remettent à jour
    } catch (e) {
      print('⚠️ fuseau de l\'entreprise indisponible : $e');
    }
  }

  Future<void> _chargerEntrepriseLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('enterprise_id');
    final name = prefs.getString('enterprise_name');
    final logo = prefs.getString('enterprise_logo');
    final prefix = prefs.getString('matricule_prefix');

    if (id != null) {
      setState(() {
        entrepriseSelectionnee = {
          'id': id,
          'name': name,
          'logo_url': logo,
          'matricule_prefix': prefix,
        };
        chargementEntreprises = false;
      });
    } else {
      setState(() => chargementEntreprises = false);
    }
  }

  Future<void> _verifierApprobationEnLigne() async {
    if (!ConnectivityService.isOnline || _faceEmployeeId == null) return;

    try {
      final statutSupabase =
      await SupabaseService.getStatutEnrolement(_faceEmployeeId!);
      if (statutSupabase?['status'] == 'approved') {
        final enrollment =
        await SupabaseService.getEnrolementActif(_faceEmployeeId!);
        if (enrollment != null && entrepriseSelectionnee != null) {
          final embedding =
          List<double>.from(enrollment['face_embedding'] as List);
          await LocalDatabase.sauvegarderEmbedding(
            employeeId: _faceEmployeeId!,
            enterpriseId: entrepriseSelectionnee!['id'],
            embedding: embedding,
            enrollmentId: enrollment['id'],
          );
          await LocalDatabase.sauvegarderStatutEnrolement(
            employeeId: _faceEmployeeId!,
            status: 'approved',
            enrollmentId: enrollment['id'],
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('face_approved', true);
          if (mounted) setState(() => _faceApproved = true);
        }
      }
    } catch (e) {
      // Silencieux
    }
  }

  Future<void> _compterPointagesEnAttente() async {
    final count = await LocalDatabase.compterPointagesPending();
    setState(() => pointagesEnAttente = count);
  }

  void _mettreAJourHeure() {
    // ⭐ LIVRAISON 22 — l'horloge suit le fuseau de l'ENTREPRISE dès que le
    //    serveur l'a annoncé (HeurePointage), sinon celui de la tablette.
    final now = HeurePointage.maintenant();
    final jours = [
      'Dimanche', 'Lundi', 'Mardi', 'Mercredi',
      'Jeudi', 'Vendredi', 'Samedi'
    ];
    final mois = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
    ];
    if (mounted) {
      setState(() {
        heureActuelle =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        dateActuelle =
        '${jours[now.weekday % 7]} ${now.day} ${mois[now.month - 1]}';
      });
    }
  }

  String get matriculeComplet {
    final prefix = entrepriseSelectionnee?['matricule_prefix'] ?? '';
    if (numeroMatricule.isEmpty) return '$prefix-____';
    return '$prefix-$numeroMatricule';
  }

  // ═══════════════════════════════════════════════════════════
  // 🌍 GPS
  // ═══════════════════════════════════════════════════════════

  Future<bool> _verifierPositionGPS() async {
    if (!_moduleGeofencingActif || entrepriseSelectionnee == null) return true;

    setState(() => chargement = true);

    try {
      _currentPosition = await GeofencingService.obtenirPosition();
      if (_currentPosition == null) {
        final raison = GeofencingService.raisonDernierEchec;

        if (raison == 'permission') {
          // Refus RÉEL de la localisation : réglage à corriger, message clair.
          _afficherErreur(
              'Localisation refusée pour ce site.\n\n'
              'Sur iPad (Safari) : Réglages › Safari › Localisation,\n'
              'ou le bouton « aA » de la page › Paramètres du site › '
              'Localisation › Autoriser.\n\n'
              'Sur Android : Réglages › Applications › Navigateur › '
              'Autorisations › Position.');
          setState(() => chargement = false);
          return false;
        }

        if (raison == 'service') {
          _afficherErreur(
              'Services de localisation désactivés sur la tablette.\n\n'
              'Réglages › Confidentialité et sécurité › '
              'Services de localisation › Activés.');
          setState(() => chargement = false);
          return false;
        }

        // 'introuvable' — GPS temporairement perdu (intérieur, signal
        // faible…) : un ennui de GPS ne doit JAMAIS empêcher un pointage.
        // Même philosophie que le « catch » plus bas : on enregistre quand
        // même, avec un avertissement honnête.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '⚠️ Position introuvable (GPS faible ?) — pointage enregistré sans contrôle de zone.'),
            backgroundColor: EnCheckColors.terreChaude,
          ));
        }
        setState(() {
          chargement = false;
          _gpsVerifie = true;
        });
        return true;
      }

      _verificationZone = await GeofencingService.verifierZone(
        enterpriseId: entrepriseSelectionnee!['id'],
        position: _currentPosition!,
      );

      setState(() {
        _gpsVerifie = true;
        chargement = false;
      });

      if (_verificationZone!['autorise'] == false) {
        _afficherErreurGeofencing(_verificationZone!);
        return false;
      }

      return true;
    } catch (e) {
      setState(() {
        chargement = false;
        _gpsVerifie = true;
      });
      return true;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 SYNC
  // ═══════════════════════════════════════════════════════════

  Future<void> _lancerSynchronisation() async {
    if (!ConnectivityService.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pas de connexion internet')));
      return;
    }
    setState(() => syncEnCours = true);
    await SyncService.synchroniserAutomatique();
    await PhotoService.syncPhotosEnAttente();
    await _compterPointagesEnAttente();
    await _chargerPausesOuvertes(); // ⏸ le bandeau suit la synchro
    setState(() => syncEnCours = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Synchronisation terminée'),
        backgroundColor: EnCheckColors.succes,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ⏸ VISIBILITÉ DES PAUSES (17/10/2026)
  //    Le problème : la pause était cachée dans « Ma journée » que très peu
  //    d'employés consultent. Désormais : un bouton sur l'écran principal +
  //    un bandeau « qui est en pause depuis quand ».
  // ═══════════════════════════════════════════════════════════

  Future<void> _chargerPausesOuvertes() async {
    final entrepriseId = entrepriseSelectionnee?['id']?.toString();
    if (entrepriseId == null) return;
    try {
      final liste =
          await PauseService.pausesOuvertes(enterpriseId: entrepriseId);
      if (mounted) {
        setState(() => _pausesOuvertes = liste);
      }
    } catch (e) {
      print('⚠️ bandeau pauses : $e');
    }
  }

  /// Le bouton « ⏸ PAUSE / REPRISE » de l'écran principal.
  ///
  /// Identique partout : l'employé s'identifie avec SON mode habituel
  /// (PIN / QR / visage — celui que l'entreprise a choisi pour le pointage).
  Future<void> _demarrerFluxPause() async {
    if (_intention == 'pause') return; // déjà en route (anti-double-tap)
    setState(() => _intention = 'pause');

    // Mode visage exclusif / obligatoire : on lance tout de suite le scan
    // visage (reconnaissance SEULE — aucun pointage enregistré).
    if (_moduleRecoFacialeActif) {
      // Contrat Admin (25/10) : null = configuration indisponible — jamais
      // converti silencieusement en 'free'.
      final pointageMode = _faceConfig['pointage_mode'] as String?;
      final pret = _kioskMode || (_faceEnrolled && _faceApproved);
      if ((pointageMode == 'face_exclusive' ||
              pointageMode == 'face_required' ||
              _kioskMode) &&
          pret) {
        await _onBoutonFaceClique();
        return;
      }
    }
    // Sinon : les outils habituels (clavier PIN, scanner QR) sont déjà à
    // l'écran — la ligne « MODE PAUSE » explique quoi faire.
  }

  void _annulerFluxPause() {
    setState(() => _intention = 'pointage');
  }

  /// L'identification a abouti (PIN, QR ou visage) → la feuille de pause.
  Future<void> _ouvrirFeuillePause(Map<String, dynamic> employe) async {
    final entrepriseId = entrepriseSelectionnee?['id']?.toString();
    final employeId = employe['id'] as String?;
    if (employeId == null || entrepriseId == null) {
      _annulerFluxPause();
      return;
    }

    final nom =
        '${employe['first_name'] ?? ''} ${employe['last_name'] ?? ''}'.trim();
    final matricule = employe['matricule']?.toString();

    // « 📍 Hors site » : informatif uniquement — ne bloque JAMAIS la pause.
    var horsSite = false;
    try {
      if (_moduleGeofencingActif) {
        final position =
            await GeofencingService.obtenirPosition(tentatives: 1);
        if (position != null) {
          final zone = await GeofencingService.verifierZone(
              enterpriseId: entrepriseId, position: position);
          horsSite = zone['is_within_zone'] == false;
        }
      }
    } catch (_) {}

    // État actuel : local ∪ base (la fusion est dans PauseService).
    final liste =
        await PauseService.pausesOuvertes(enterpriseId: entrepriseId);
    Map<String, dynamic>? ouverte;
    for (final p in liste) {
      if (p['employee_id'] == employeId) ouverte = p;
    }

    if (!mounted) return;

    String? motifChoisi = ouverte?['motif'] as String?;
    var actionEnCours = false;
    var rappelAffiche = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEtat) {
          final estOuverte = ouverte != null;
          DateTime? debut;
          if (estOuverte) {
            debut = HeurePointage.instantDe(ouverte!['debut']);
          }
          final rappel = debut != null && PauseService.rappelDepasse(debut);
          if (rappel) rappelAffiche = true;
          final heureDebut = debut == null
              ? ''
              : (PauseService.heureCourteDe(
                  debut.toUtc().toIso8601String()));

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: EnCheckColors.gris.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      estOuverte ? Icons.pause_circle : Icons.timer_outlined,
                      color: EnCheckColors.terreChaude,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nom,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          if (matricule != null && matricule.isNotEmpty)
                            Text(
                              matricule,
                              style: const TextStyle(
                                  fontSize: 12, color: EnCheckColors.gris),
                            ),
                        ],
                      ),
                    ),
                    if (horsSite)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: EnCheckColors.terreChaude.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('📍 Hors site',
                            style: TextStyle(
                                fontSize: 11,
                                color: EnCheckColors.terreChaude)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  estOuverte
                      ? 'En pause depuis $heureDebut'
                      : 'Prêt pour la pause ?',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                if (estOuverte && rappelAffiche) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: EnCheckColors.terreChaude.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.alarm,
                            size: 16, color: EnCheckColors.terreChaude),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Toujours en pause ? Touche ▶ Je reprends si tu es de retour.',
                            style: TextStyle(
                                fontSize: 12,
                                color: EnCheckColors.terreChaude),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text('Motif facultatif :',
                    style:
                        TextStyle(fontSize: 12, color: EnCheckColors.gris)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final motif in PauseService.motifs)
                      ChoiceChip(
                        label: Text(motif),
                        selected: motifChoisi == motif,
                        selectedColor:
                            EnCheckColors.terreChaude.withOpacity(0.2),
                        onSelected: (_) async {
                          final nouveau =
                              (motifChoisi == motif) ? null : motif;
                          setEtat(() => motifChoisi = nouveau);
                          if (estOuverte) {
                            // Modifiable tant que la pause est ouverte.
                            await PauseService.changerMotif(
                                employeeId: employeId, motif: nouveau);
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: actionEnCours
                      ? null
                      : () async {
                          setEtat(() => actionEnCours = true);
                          try {
                            if (estOuverte) {
                              await PauseService.reprendre(
                                employeeId: employeId,
                                enterpriseId: entrepriseId,
                              );
                            } else {
                              ouverte = await PauseService.partirEnPause(
                                employeeId: employeId,
                                enterpriseId: entrepriseId,
                                nom: nom,
                                matricule: matricule,
                                motif: motifChoisi,
                              );
                            }
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            final horsLigne = !ConnectivityService.isOnline;
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(estOuverte
                                    ? (horsLigne
                                        ? '▶ Reprise enregistrée hors-ligne : elle sera synchronisée.'
                                        : '▶ Reprise enregistrée. Bon service !')
                                    : (horsLigne
                                        ? '⏸ Pause enregistrée hors-ligne : elle sera synchronisée.'
                                        : '⏸ Pause enregistrée. Bonne pause !')),
                                backgroundColor: estOuverte
                                    ? EnCheckColors.succes
                                    : EnCheckColors.terreChaude,
                              ));
                              _chargerPausesOuvertes();
                            }
                          } catch (e) {
                            setEtat(() => actionEnCours = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  content:
                                      Text("Impossible d'enregistrer : $e")));
                            }
                          }
                        },
                  icon: Icon(estOuverte ? Icons.play_arrow : Icons.pause),
                  label: Text(estOuverte
                      ? '▶ Je reprends'
                      : '⏸ Je pars en pause'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: estOuverte
                        ? EnCheckColors.succes
                        : EnCheckColors.terreChaude,
                    foregroundColor: EnCheckColors.blanc,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    _annulerFluxPause();
    if (mounted) _chargerPausesOuvertes();
  }

  /// Le bandeau « qui est en pause » — visible par tout le monde sur la
  /// tablette partagée (choix validé le 17/10 : avec le nom).
  Widget _construireBandeauPauses() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EnCheckColors.terreChaude.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnCheckColors.terreChaude.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pause_circle,
                  size: 16, color: EnCheckColors.terreChaude),
              SizedBox(width: 6),
              Text('PAUSES EN COURS',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: EnCheckColors.terreChaude)),
            ],
          ),
          const SizedBox(height: 6),
          for (final pause in _pausesOuvertes) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '⏸ ${pause['nom'] ?? 'Employé'} — en pause depuis '
                    '${pause['debut'] == null ? '—' : PauseService.heureCourteDe(pause['debut'] as String)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (pause['debut'] != null &&
                    PauseService.rappelDepasse(
                        HeurePointage.instantDe(pause['debut']) ??
                            DateTime.now().toUtc()))
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: EnCheckColors.erreur.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('🕒 Toujours en pause ?',
                        style: TextStyle(
                            fontSize: 10, color: EnCheckColors.erreur)),
                  ),
              ],
            ),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }

  /// La ligne « MODE PAUSE » pendant l'identification.
  Widget _construireLigneModePause() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EnCheckColors.sableDore.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnCheckColors.sableDore.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pause_circle_outline,
              size: 18, color: EnCheckColors.terreChaude),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '⏸ MODE PAUSE — identifiez-vous comme pour pointer',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _annulerFluxPause,
            child: const Text('ANNULER',
                style: TextStyle(
                    fontSize: 11, color: EnCheckColors.gris)),
          ),
        ],
      ),
    );
  }

  /// Le bouton PAUSE, collé JUSTE AU-DESSUS de la carte MATRICULE
  /// (retour du 17/10 au soir : visible sans jamais scroller).
  Widget _buildBoutonPause() {
    final enModePause = _intention == 'pause';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🎨 Refonte design : la couverture basotho (Lesotho) veille sur le
        //    bloc pause — repos, chaleur. La règle UX reste intacte : le bloc
        //    pause est placé juste au-dessus de la carte MATRICULE.
        const BandeMotif.lesotho(height: 12),
        const SizedBox(height: 6),
        SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enModePause ? null : _demarrerFluxPause,
        icon: Icon(enModePause ? Icons.hourglass_top : Icons.pause_circle),
        label: Text(
          enModePause ? 'MODE PAUSE EN COURS…' : '⏸ PAUSE / REPRISE',
          style: const TextStyle(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: EnCheckColors.terreChaude,
          foregroundColor: EnCheckColors.blanc,
          disabledBackgroundColor: EnCheckColors.gris.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🤖 LOGIQUE RECONNAISSANCE FACIALE
  // ═══════════════════════════════════════════════════════════

  Future<void> _onBoutonFaceClique() async {
    // ⏸ En MODE PAUSE, le GPS ne bloque jamais (fiche LOT D).
    if (_moduleGeofencingActif && _intention != 'pause') {
      final gpsOk = await _verifierPositionGPS();
      if (!gpsOk) return;
    }

    if (_kioskMode) {
      await _lancerPointageFacialKiosk1vN();
    } else {
      if (_faceEnrolled && _faceApproved && _faceEmployeeId != null) {
        await _lancerPointageFacialDirect();
      } else if (_faceEnrolled && !_faceApproved) {
        await _verifierApprobationEnLigne();
        if (_faceApproved) {
          await _lancerPointageFacialDirect();
        } else {
          _afficherDialogEnAttente();
        }
      } else {
        _afficherDialogIdentificationPourEnrolement();
      }
    }
  }

  Future<void> _lancerPointageFacialKiosk1vN() async {
    final tousEmbeddings =
    await LocalDatabase.getTousEmbeddings(entrepriseSelectionnee!['id']);

    if (tousEmbeddings.isEmpty) {
      _afficherErreur(
          'Aucun employé enrôlé. Veuillez d\'abord enrôler les employés.');
      return;
    }

    setState(() {
      _employeeEnAttente = {
        'id': '',
        'first_name': '',
        'last_name': '',
        'enterprise_id': entrepriseSelectionnee!['id'],
      };
      _showFacePointage = true;
    });
  }

  void _lancerEnrolementKioskSuivant() {
    if (_kioskEnrolementIndex >= _kioskEmployeesNonEnroles.length) {
      setState(() => _kioskPhase = 'pointage');
      return;
    }

    final employee = _kioskEmployeesNonEnroles[_kioskEnrolementIndex];
    setState(() {
      _employeeEnAttente = employee;
      _showFaceEnrollment = true;
    });
  }

  void _onEnrolementKioskComplete() async {
    setState(() {
      _showFaceEnrollment = false;
      _kioskEnrolementIndex++;
    });

    await _chargerTousEmbeddingsEntreprise();

    if (_kioskEnrolementIndex >= _kioskEmployeesNonEnroles.length) {
      setState(() => _kioskPhase = 'pointage');
    } else {
      _lancerEnrolementKioskSuivant();
    }
  }

  Future<void> _lancerPointageFacialDirect() async {
    if (_faceEmployeeId == null) return;

    final embeddingData = await LocalDatabase.getEmbedding(_faceEmployeeId!);

    if (embeddingData == null) {
      if (ConnectivityService.isOnline) {
        final enrollment =
        await SupabaseService.getEnrolementActif(_faceEmployeeId!);
        if (enrollment != null && entrepriseSelectionnee != null) {
          final embedding =
          List<double>.from(enrollment['face_embedding'] as List);
          await LocalDatabase.sauvegarderEmbedding(
            employeeId: _faceEmployeeId!,
            enterpriseId: entrepriseSelectionnee!['id'],
            embedding: embedding,
            enrollmentId: enrollment['id'],
          );
        } else {
          _afficherErreur(
              'Profil facial introuvable. Veuillez vous ré-enrôler.');
          return;
        }
      } else {
        _afficherErreur('Profil facial non disponible hors ligne.');
        return;
      }
    }

    final nameParts = (_faceEmployeeName ?? '').split(' ');
    final employee = {
      'id': _faceEmployeeId,
      'first_name': nameParts.isNotEmpty ? nameParts.first : '',
      'last_name': nameParts.length > 1 ? nameParts.skip(1).join(' ') : '',
      'enterprise_id': entrepriseSelectionnee!['id'],
    };

    setState(() {
      _employeeEnAttente = employee;
      _showFacePointage = true;
    });
  }

  void _afficherDialogIdentificationPourEnrolement() {
    final matriculeController = TextEditingController();
    final pinController = TextEditingController();
    bool afficherPinLocal = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EnCheckColors.terreChaude.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_outline,
                    color: EnCheckColors.terreChaude, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Première connexion',
                        style: TextStyle(
                            color: EnCheckColors.terreChaude,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text('Identifiez-vous pour l\'enrôlement',
                        style: TextStyle(
                            color: EnCheckColors.gris,
                            fontSize: 12,
                            fontWeight: FontWeight.normal)),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                afficherPinLocal
                    ? 'Entrez votre code PIN'
                    : 'Entrez votre matricule',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller:
                afficherPinLocal ? pinController : matriculeController,
                obscureText: afficherPinLocal,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                decoration: InputDecoration(
                  hintText: afficherPinLocal ? '● ● ● ●' : 'Matricule',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: EnCheckColors.terreChaude, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(color: EnCheckColors.gris)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: EnCheckColors.terreChaude,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (!afficherPinLocal) {
                  if (matriculeController.text.isEmpty) return;
                  setModalState(() => afficherPinLocal = true);
                } else {
                  if (pinController.text.length < 4) return;
                  Navigator.pop(ctx);
                  await _identifierEtEnroler(
                      matriculeController.text, pinController.text);
                }
              },
              child: Text(afficherPinLocal ? 'Valider' : 'Suivant'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _identifierEtEnroler(String matricule, String pin) async {
    setState(() => chargement = true);

    try {
      final matriculeCompletSaisi =
          '${entrepriseSelectionnee!['matricule_prefix']}-$matricule';

      Map<String, dynamic>? employee;
      final estHorsLigne = !ConnectivityService.isOnline;

      if (estHorsLigne) {
        employee = await LocalDatabase.verifierEmployeeCache(
            entrepriseSelectionnee!['id'], matriculeCompletSaisi, pin);
      } else {
        employee = await SupabaseService.verifierEmployee(
            entrepriseSelectionnee!['id'], matriculeCompletSaisi, pin);
      }

      if (employee == null) {
        setState(() => chargement = false);
        _afficherErreur(
            _messageIdentifiants(estHorsLigne: estHorsLigne, type: 'pin'));
        return;
      }

      String statut = 'none';
      if (ConnectivityService.isOnline) {
        final statutSupabase =
        await SupabaseService.getStatutEnrolement(employee['id']);
        if (statutSupabase != null) {
          statut = statutSupabase['status'];

          if (statut == 'approved') {
            final enrollment =
            await SupabaseService.getEnrolementActif(employee['id']);
            if (enrollment != null) {
              final embedding =
              List<double>.from(enrollment['face_embedding'] as List);
              await LocalDatabase.sauvegarderEmbedding(
                employeeId: employee['id'],
                enterpriseId: entrepriseSelectionnee!['id'],
                embedding: embedding,
                enrollmentId: enrollment['id'],
              );
            }
            await _sauvegarderEmployeLocal(employee, approved: true);
            setState(() {
              chargement = false;
              _employeeEnAttente = employee;
              _showFacePointage = true;
            });
            return;
          } else if (statut == 'pending') {
            await _sauvegarderEmployeLocal(employee, approved: false);
            setState(() => chargement = false);
            _afficherDialogEnAttente();
            return;
          }
        }
      }

      setState(() {
        chargement = false;
        _employeeEnAttente = employee;
        _showFaceEnrollment = true;
      });
    } catch (e) {
      setState(() => chargement = false);
      _afficherErreur('Erreur: $e');
    }
  }

  Future<void> _sauvegarderEmployeLocal(
      Map<String, dynamic> employee, {
        required bool approved,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('face_employee_id', employee['id']);
    await prefs.setString('face_employee_name',
        '${employee['first_name']} ${employee['last_name']}');
    await prefs.setBool('face_enrolled', true);
    await prefs.setBool('face_approved', approved);

    if (mounted) {
      setState(() {
        _faceEmployeeId = employee['id'];
        _faceEmployeeName =
        '${employee['first_name']} ${employee['last_name']}';
        _faceEnrolled = true;
        _faceApproved = approved;
      });
    }
  }

  void _afficherDialogEnAttente() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.hourglass_top, color: EnCheckColors.terreChaude),
            SizedBox(width: 10),
            Text('En attente de validation'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Votre enrôlement facial est en attente de validation.',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            if (_faceConfig['fallback_allowed'] == true) ...[
              const SizedBox(height: 12),
              const Text(
                'Vous pouvez utiliser un autre mode en attendant.',
                style: TextStyle(
                    fontSize: 13, color: EnCheckColors.gris, height: 1.4),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EnCheckColors.terreChaude,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ SUCCÈS FACIAL
  // ═══════════════════════════════════════════════════════════

  void _afficherSuccesFacial(Map<String, dynamic> result) {
    final estEntree = result['check_type'] == 'in';
    final emp = result['employee'] as Map<String, dynamic>?;
    final nomAffiche = emp != null
        ? '${emp['first_name']} ${emp['last_name']}'
        : (_faceEmployeeName ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(estEntree ? Icons.login : Icons.logout,
                color: EnCheckColors.succes, size: 30),
            const SizedBox(width: 10),
            Text(
              estEntree ? 'ENTRÉE' : 'SORTIE',
              style: const TextStyle(
                  color: EnCheckColors.succes,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person,
                  size: 60, color: EnCheckColors.terreChaude),
              const SizedBox(height: 12),
              Text(
                nomAffiche,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pointage enregistré à $heureActuelle',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: EnCheckColors.succes.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        color: EnCheckColors.succes, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Reconnu par reconnaissance faciale',
                        style: TextStyle(
                            color: EnCheckColors.succes,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              if (result['is_within_zone'] != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (result['is_within_zone'] == true
                        ? EnCheckColors.succes
                        : EnCheckColors.erreur)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: result['is_within_zone'] == true
                          ? EnCheckColors.succes
                          : EnCheckColors.erreur,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        result['is_within_zone'] == true
                            ? Icons.location_on
                            : Icons.location_off,
                        color: result['is_within_zone'] == true
                            ? EnCheckColors.succes
                            : EnCheckColors.erreur,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        result['is_within_zone'] == true
                            ? 'Dans la zone autorisée'
                            : 'Hors zone',
                        style: TextStyle(
                          color: result['is_within_zone'] == true
                              ? EnCheckColors.succes
                              : EnCheckColors.erreur,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (result['offline'] == true) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EnCheckColors.terreChaude.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off,
                          color: EnCheckColors.terreChaude, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sauvegardé hors-ligne. Sera synchronisé.',
                          style: TextStyle(
                              color: EnCheckColors.terreChaude, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_dernierEmployePointe != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        HistoriqueScreen(employee: _dernierEmployePointe!),
                  ),
                );
              },
              child: Text('HISTORIQUE',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      letterSpacing: 2)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _modeSelectionne = null;
                _employeeEnAttente = null;
                _gpsVerifie = false;
                _currentPosition = null;
                _verificationZone = null;
              });
            },
            child: const Text('FERMER',
                style: TextStyle(
                    color: EnCheckColors.terreChaude, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🧠 DÉCISION ENTRÉE / SORTIE — LES DIALOGUES
  // ═══════════════════════════════════════════════════════════

  /// Demande à l'employé s'il arrive ou s'il part.
  ///
  /// On n'y vient que quand le système doute vraiment — typiquement une
  /// entrée vieille de plus du seuil d'oubli (12 h par défaut, réglable dans
  /// `encheck_reglages_pointage`), donc une sortie vraisemblablement
  /// oubliée. Le type proposé est mis en avant, mais l'employé tranche.
  ///
  /// Renvoie `null` si l'employé renonce : dans ce cas RIEN n'est enregistré.
  Future<String?> _demanderTypePointage(
      String typePropose, String? anomalie, double? seuilPresenceHeures) async {
    final estEntree = typePropose == 'in';
    // Affichage du seuil : « 12 » plutôt que « 12.0 », « 12,5 » en français.
    final String? seuilTexte = seuilPresenceHeures == null
        ? null
        : (seuilPresenceHeures == seuilPresenceHeures.roundToDouble()
            ? seuilPresenceHeures.toInt().toString()
            : seuilPresenceHeures.toString().replaceFirst('.', ','));

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: EnCheckColors.terreChaude),
            SizedBox(width: 10),
            Text('Vous arrivez ou\nvous partez ?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "L'application n'arrive pas à le déterminer avec certitude.",
              style: TextStyle(color: EnCheckColors.gris, fontSize: 13),
            ),
            if (anomalie == 'sortie_oubliee') ...[
              const SizedBox(height: 12),
              // Le seuil vient de la base (réglage « oubli_sortie_heures ») :
              // aucun chiffre en dur dans l'interface (fiche 2/3, cohérence).
              Text(
                seuilTexte == null
                    ? "Votre dernière entrée est très ancienne : une "
                        "sortie a probablement été oubliée."
                    : "Votre dernière entrée remonte à plus de "
                        "$seuilTexte heures : une sortie a probablement "
                        "été oubliée.",
                style: const TextStyle(
                    color: EnCheckColors.terreChaude,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              estEntree
                  ? "Ce pointage sera une ARRIVÉE."
                  : "Ce pointage sera un DÉPART.",
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ANNULER',
                style: TextStyle(color: EnCheckColors.gris)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EnCheckColors.terreChaude,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, 'out'),
            child: const Text('JE PARS'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EnCheckColors.succes,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, 'in'),
            child: const Text("J'ARRIVE"),
          ),
        ],
      ),
    );
  }

  /// Propose à l'employé de corriger le type de son dernier pointage.
  ///
  /// La base garde trois garde-fous : le pointage doit exister, appartenir à
  /// l'employé, et dater de moins de 30 minutes. Chaque correction est
  /// enregistrée dans `attendance_corrections` et lève le drapeau
  /// `modifie_par_employe` : l'administrateur la voit dans la page Pointages.
  Future<void> _demanderCorrectionType(
      String attendanceId,
      Map<String, dynamic> employee,
      String typeActuel,
      ) async {
    final nouveauType = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Corriger le type',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300)),
        content: Text(
          "Enregistré en ${typeActuel == 'in' ? 'ARRIVÉE' : 'DÉPART'}. "
          "Que fallait-il enregistrer ?\n\n"
          "Votre administrateur sera prévenu de la modification.",
          style: TextStyle(color: EnCheckColors.gris, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ANNULER',
                style: TextStyle(color: EnCheckColors.gris)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EnCheckColors.terreChaude,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'out'),
            child: const Text('DÉPART'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EnCheckColors.succes,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'in'),
            child: const Text('ARRIVÉE'),
          ),
        ],
      ),
    );

    if (nouveauType == null || nouveauType == typeActuel) return;

    final resultat = await SupabaseService.corrigerType(
      attendanceId: attendanceId,
      employeeId: employee['id'],
      nouveauType: nouveauType,
    );

    if (!mounted) return;

    final ok = resultat?['ok'] == true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline,
                color: ok ? EnCheckColors.succes : EnCheckColors.erreur),
            const SizedBox(width: 10),
            Text(ok ? 'Corrigé' : 'Impossible',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w300)),
          ],
        ),
        content: Text(
          ok
              ? "Enregistré en ${nouveauType == 'in' ? 'ARRIVÉE' : 'DÉPART'}."
              : (resultat?['message'] as String?) ??
                  "La correction n'a pas pu être appliquée. Passez par un "
                      "administrateur.",
          style: TextStyle(color: EnCheckColors.gris, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(color: EnCheckColors.terreChaude)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🖥️ BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // ── Mode tablette : phase enrôlement ──
    if (_kioskMode &&
        _kioskPhase == 'enrolling' &&
        _kioskEmployeesNonEnroles.isNotEmpty &&
        !_showFaceEnrollment &&
        !_showFacePointage) {
      return _buildKioskEnrolementScreen();
    }

    // ── Écran reco faciale ──
    if (_showFacePointage && _employeeEnAttente != null) {
      return FacePointageScreen(
        employee: _employeeEnAttente!,
        enterpriseId: entrepriseSelectionnee!['id'],
        config: _faceConfig,
        moduleGeofencingActif: _moduleGeofencingActif,
        positionGPS: _currentPosition,
        verificationZone: _verificationZone,
        kioskMode: _kioskMode,
        // ⏸ En MODE PAUSE : le visage identifie SANS enregistrer de pointage.
        identificationSeule: _intention == 'pause',
        onPointageComplete: (result) async {
          // CONTRAT D'ACCÈS (25/10/2026) : la fiche vient du profil renvoyé
          // par le scan — plus de rechargement anonyme par ID
          // (`employees_public` est fermé).
          Map<String, dynamic>? employeeComplet =
              result['employee'] as Map<String, dynamic>?;
          // 🔄 CONTRAT ÉTAPE 2 (25/10/2026) : rafraîchissement par JETON —
          // uniquement quand la session appartient bien à l'employé identifié
          // (en mode borne, le jeton peut décrire quelqu'un d'autre : on
          // n'écrase alors rien et la fiche du scan reste la référence).
          final empId = result['employee_id'] as String?;
          if (ConnectivityService.isOnline && empId != null && empId.isNotEmpty) {
            final rafraichi = await SupabaseService.rafraichirProfilDeSession(
              employeeIdAttendu: empId,
            );
            if (rafraichi != null) employeeComplet = rafraichi;
          }
          employeeComplet ??= _employeeEnAttente;

          setState(() {
            _showFacePointage = false;
            _dernierEmployePointe = employeeComplet;
            _modeSelectionne = null;
            _gpsVerifie = false;
            _currentPosition = null;
            _verificationZone = null;
          });

          // ⏸ MODE PAUSE : reconnu → feuille de pause (aucun pointage écrit).
          if (result['identification_seule'] == true) {
            if (employeeComplet != null) {
              await _ouvrirFeuillePause(employeeComplet);
            } else {
              _annulerFluxPause();
            }
            return;
          }

          await _compterPointagesEnAttente();
          if (mounted) _afficherSuccesFacial(result);
        },
        onCancel: () {
          setState(() {
            _showFacePointage = false;
            _employeeEnAttente = null;
            _modeSelectionne = null;
            _gpsVerifie = false;
            _currentPosition = null;
            _verificationZone = null;
          });
        },
        onFallback: _faceConfig['fallback_allowed'] == true &&
            _faceConfig['pointage_mode'] != 'face_exclusive'
            ? () {
          setState(() {
            _showFacePointage = false;
            _employeeEnAttente = null;
            _modeSelectionne = 'pin';
          });
        }
            : null,
      );
    }

    // ── Écran enrôlement ──
    if (_showFaceEnrollment && _employeeEnAttente != null) {
      return FaceEnrollmentScreen(
        employee: _employeeEnAttente!,
        enterpriseId: entrepriseSelectionnee!['id'],
        adminApprovalRequired:
        _faceConfig['admin_approval_required'] as bool? ?? true,
        onEnrollmentComplete: () async {
          if (_kioskMode) {
            _onEnrolementKioskComplete();
          } else {
            await _sauvegarderEmployeLocal(
              _employeeEnAttente!,
              approved:
              !(_faceConfig['admin_approval_required'] as bool? ?? true),
            );
            setState(() {
              _showFaceEnrollment = false;
              _employeeEnAttente = null;
              _modeSelectionne = null;
            });
          }
        },
        onCancel: () {
          setState(() {
            _showFaceEnrollment = false;
            _employeeEnAttente = null;
            _modeSelectionne = null;
          });
        },
      );
    }

    // ── Scanner QR simple ──
    if (_showScanner) {
      return QRScannerWidget(
        onScanned: _onQRScanned,
        onClose: () => setState(() {
          _showScanner = false;
          _modeSelectionne = null;
        }),
      );
    }

    // ── Scanner QR + Photo ──
    if (_showPhotoScanner) {
      return QRPhotoScannerWidget(
        onCompleted: _onQRPhotoCompleted,
        onClose: () => setState(() {
          _showPhotoScanner = false;
          _modeSelectionne = null;
        }),
      );
    }

    // ── PIN + Photo (Mobile) ──
    if (_showPinPhoto && _pendingEmployee != null) {
      return PinPhotoWidget(
        employeeName: _pendingEmployee!['first_name'] ?? '',
        onPhotoTaken: (photoBytes) => _onPinPhotoTaken(photoBytes),
        onCancel: () {
          setState(() {
            _showPinPhoto = false;
            _pendingEmployee = null;
            _modeSelectionne = null;
          });
        },
      );
    }

    // ── Web Camera (Web uniquement) ──
    if (_showWebCamera && _pendingEmployeeWebCamera != null && kIsWeb) {
      return WebCameraWidget(
        employeeName:
        '${_pendingEmployeeWebCamera!['first_name']} ${_pendingEmployeeWebCamera!['last_name']}',
        raison: _webCameraRaison,
        onPhotoTaken: (photoBytes) async {
          final employee = _pendingEmployeeWebCamera!;
          final estHorsLigne = !ConnectivityService.isOnline;

          setState(() {
            _showWebCamera = false;
            _pendingEmployeeWebCamera = null;
          });

          // Déterminer la méthode selon la raison
          String method;
          switch (_webCameraRaison) {
            case 'qr':
              method = 'qr_photo';
              break;
            case 'pin':
            default:
              method = 'pin_photo';
              break;
          }

          await _traiterPointage(
            employee,
            method,
            estHorsLigne,
            photoBytes,
          );

          setState(() {
            numeroMatricule = '';
            codePin = '';
            afficherPin = false;
            _modeSelectionne = null;
            _gpsVerifie = false;
            _currentPosition = null;
            _verificationZone = null;
          });
        },
        onCancel: () {
          setState(() {
            _showWebCamera = false;
            _pendingEmployeeWebCamera = null;
            _modeSelectionne = null;
          });
        },
      );
    }

    final bool estEnLigne = ConnectivityService.isOnline;
    final themeService = Provider.of<ThemeService>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: chargementEntreprises
            ? const Center(
            child: CircularProgressIndicator(
                color: EnCheckColors.terreChaude))
            : Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildHeader(estEnLigne, themeService),
                    const SizedBox(height: 30),
                    const LogoEmpreinte(taille: 100),
                    const SizedBox(height: 20),
                    Text(
                      'EN-CHECK',
                      style: EnCheckTextStyles.titrePrincipal.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 🎨 Refonte design : frise Adinkra sous le logo —
                    //    l'étoffe « temps et travail » du kiosque.
                    const BandeMotif.adinkra(height: 28),
                    const SizedBox(height: 18),
                    _buildCarteEntreprise(),
                    const SizedBox(height: 28),
                    Text(
                      heureActuelle,
                      style: EnCheckTextStyles.grosChiffres.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.color,
                      ),
                    ),
                    Text(dateActuelle,
                        style: EnCheckTextStyles.titreSecondaire),
                    _buildAvisFuseau(),
                    if (_moduleGeofencingActif || _kioskMode) ...[
                      const SizedBox(height: 16),
                      _buildIndicateursModules(),
                    ],

                    const SizedBox(height: 24),

                    // ⏸ LE BLOC PAUSE — GLISSÉ JUSTE AU-DESSUS DE LA CARTE
                    //    « MATRICULE » (retour du 17/10 au soir) : c'est là
                    //    que se posent les yeux des employés. En bas de page,
                    //    il fallait scroller tout le temps pour le voir.
                    if (_pausesOuvertes.isNotEmpty) ...[
                      _construireBandeauPauses(),
                      const SizedBox(height: 12),
                    ],
                    _buildBoutonPause(),
                    const SizedBox(height: 12),
                    if (_intention == 'pause') ...[
                      _construireLigneModePause(),
                      const SizedBox(height: 12),
                    ],
                    // 🖥️ CONTRAT ÉTAPE 3 — le provisionnement d'une borne reste
                    //    joignable sans session employé. Le bandeau s'affiche si
                    //    l'entreprise utilise la reco faciale ou le mode kiosque,
                    //    ou si cette tablette a déjà un bail de borne — et
                    //    SEULEMENT dans ces cas : les entreprises en pointage
                    //    PIN/QR pur retrouvent leur écran d'avant, sans bruit.
                    if (_moduleRecoFacialeActif || _kioskMode) ...[
                      _buildBandeauBorne(),
                      const SizedBox(height: 12),
                    ],
                    _buildZonePointage(),
                    const SizedBox(height: 30),
                    _buildSeparateur(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 📱 ÉCRAN ENRÔLEMENT TABLETTE
  // ═══════════════════════════════════════════════════════════

  Widget _buildKioskEnrolementScreen() {
    final total = _kioskEmployeesNonEnroles.length;
    final restants = total - _kioskEnrolementIndex;
    final employee = _kioskEnrolementIndex < total
        ? _kioskEmployeesNonEnroles[_kioskEnrolementIndex]
        : null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: EnCheckColors.terreChaude.withOpacity(0.15),
                    border:
                    Border.all(color: EnCheckColors.terreChaude, width: 2),
                  ),
                  child: const Icon(Icons.tablet_android,
                      color: EnCheckColors.terreChaude, size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'MODE TABLETTE',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
                const SizedBox(height: 8),
                Text(
                  'Phase d\'enrôlement : $restants employé${restants > 1 ? 's' : ''} restant${restants > 1 ? 's' : ''}',
                  style:
                  const TextStyle(color: EnCheckColors.gris, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: total > 0 ? _kioskEnrolementIndex / total : 0,
                    backgroundColor:
                    EnCheckColors.terreChaude.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        EnCheckColors.terreChaude),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_kioskEnrolementIndex / $total enrôlé${_kioskEnrolementIndex > 1 ? 's' : ''}',
                  style:
                  const TextStyle(color: EnCheckColors.gris, fontSize: 12),
                ),
                const SizedBox(height: 40),
                if (employee != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: EnCheckColors.terreChaude.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        const Text('Employé suivant à enrôler :',
                            style: TextStyle(
                                color: EnCheckColors.gris, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(
                          '${employee['first_name']} ${employee['last_name']}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                            Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(employee['matricule'] ?? '',
                            style: const TextStyle(
                                color: EnCheckColors.gris, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _lancerEnrolementKioskSuivant,
                      icon: const Icon(Icons.face_retouching_natural),
                      label: const Text('Enrôler cet employé',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EnCheckColors.terreChaude,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_kioskEnrolementIndex > 0)
                  TextButton(
                    onPressed: () =>
                        setState(() => _kioskPhase = 'pointage'),
                    child: const Text(
                      'Passer au pointage (enrôlement partiel)',
                      style: TextStyle(
                          color: EnCheckColors.gris, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🎯 ZONE DE POINTAGE
  // ═══════════════════════════════════════════════════════════

  Widget _buildZonePointage() {
    if (!_moduleRecoFacialeActif) return _buildModeClassique();

    if (_modeSelectionne == 'pin') return _buildModePIN();
    if (_modeSelectionne == 'qr') return _buildModeQR();

    // Contrat Admin (25/10) : null = configuration indisponible — jamais
    // converti silencieusement en 'free'.
    final pointageMode = _faceConfig['pointage_mode'] as String?;

    if (pointageMode == 'face_exclusive') {
      return _buildBoutonFaceScan(onTap: _onBoutonFaceClique);
    }

    if (pointageMode == 'face_required') {
      return Column(
        children: [
          _buildBoutonFaceScan(onTap: _onBoutonFaceClique),
        ],
      );
    }

    return _buildEcranSelectionMode();
  }

  Widget _buildEcranSelectionMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CHOISISSEZ VOTRE MODE DE POINTAGE',
          textAlign: TextAlign.center,
          style: EnCheckTextStyles.titreSecondaire.copyWith(
            letterSpacing: 1.5,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 20),
        _buildBoutonFaceScan(onTap: _onBoutonFaceClique),
        if (_faceConfig['fallback_allowed'] == true) ...[
          const SizedBox(height: 16),
          _buildBoutonModeSecondaire(
            label: 'CODE PIN',
            icon: Icons.pin_outlined,
            onTap: () => setState(() => _modeSelectionne = 'pin'),
          ),
        ],
        if (_moduleQRActif && _faceConfig['fallback_allowed'] == true) ...[
          const SizedBox(height: 12),
          _buildBoutonModeSecondaire(
            label: 'SCANNER QR',
            icon: Icons.qr_code_scanner,
            onTap: () => setState(() => _modeSelectionne = 'qr'),
          ),
        ],
        if (_kioskMode) ...[
          const SizedBox(height: 20),
          _buildBoutonEnrolerNouvelEmploye(),
        ],
      ],
    );
  }

  Widget _buildModeClassique() {
    if (_moduleQRActif && _modulePhotoActif) return _buildModeQRPhoto();
    if (_moduleQRActif) return _buildModeQRSimple();
    if (_modulePhotoActif) return _buildModePINPhoto();
    return _buildModePINSimple();
  }

  Widget _buildBoutonEnrolerNouvelEmploye() {
    return GestureDetector(
      onTap: () async {
        await _detecterEmployesNonEnroles();
        if (_kioskEmployeesNonEnroles.isEmpty) {
          // CONTRAT ÉTAPE 3 : message honnête selon l'état du cache borne.
          if (!await BorneService.cacheValide()) {
            _afficherErreur(
                'Personnel de la borne non disponible sur cette tablette.\n'
                'Synchronisez la borne (bouton « 🖥 Borne ») — une autorisation '
                'de borne est fournie par le superadmin.\n'
                'En attendant : un employé peut s\'enrôler en s\'identifiant '
                'avec son matricule et son PIN.');
          } else {
            _afficherErreur(
                'Tous les employés actifs de cette borne sont déjà enrôlés.');
          }
          return;
        }
        setState(() {
          _kioskPhase = 'enrolling';
          _kioskEnrolementIndex = 0;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.indigo.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.indigo.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_outlined,
                color: Colors.indigo.shade300, size: 22),
            const SizedBox(width: 10),
            Text(
              'Enrôler un nouvel employé',
              style: TextStyle(
                color: Colors.indigo.shade300,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🖥️ CONTRAT ÉTAPE 3 — bandeau de la borne autorisée.
  Widget _buildBandeauBorne() {
    return GestureDetector(
      onTap: _afficherDialogBorne,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: _bornePrete
              ? Colors.green.withOpacity(0.08)
              : Colors.indigo.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _bornePrete
                ? Colors.green.withOpacity(0.35)
                : Colors.indigo.withOpacity(0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _bornePrete ? Icons.laptop_mac : Icons.laptop,
              size: 20,
              color: _bornePrete
                  ? Colors.green.shade700
                  : Colors.indigo.shade400,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _bornePrete
                    ? "Borne autorisée — personnel synchronisé. Touchez pour gérer."
                    : "Borne non autorisée — touchez pour saisir l'identifiant "
                        "et le secret fournis par le superadmin.",
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: _bornePrete
                      ? Colors.green.shade800
                      : Colors.indigo.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🖥️ Dialogue de provisionnement de la borne (contrat étape 3).
  /// Le secret `bs1_` est présenté une seule fois par le superadmin :
  /// il est conservé dans le coffre sécurisé de l'OS, jamais dans les
  /// préférences ordinaires ni les logs.
  Future<void> _afficherDialogBorne() async {
    final deviceCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    final dejaPrete = await BorneService.aUnBailValide();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.laptop_mac, color: EnCheckColors.terreChaude),
              const SizedBox(width: 10),
              Text(dejaPrete ? "Borne autorisée" : "Autoriser cette borne",
                  style: const TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dejaPrete) ...[
                const Text(
                  "Un bail de borne est actif sur cette tablette. "
                  "Le personnel se synchronise depuis le serveur.",
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ] else ...[
                const Text(
                  "Saisissez l'identifiant de l'appareil et le secret "
                  "communiqués par le superadmin (présenté une seule fois).",
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: deviceCtrl,
                  decoration: const InputDecoration(
                    labelText: "Identifiant de l'appareil",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: secretCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Secret de la borne (bs1_...)",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (dejaPrete) ...[
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await BorneService.seDeconnecter();
                  if (mounted) {
                    setState(() => _bornePrete = false);
                    _afficherErreur(
                        "Borne retirée de cette tablette. Le cache local a été purgé.");
                  }
                },
                child: const Text("Retirer la borne"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _chargerTousEmbeddingsEntreprise();
                  await _detecterEmployesNonEnroles();
                },
                child: const Text("Synchroniser"),
              ),
            ] else ...[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                onPressed: () async {
                  final resultat = await BorneService.authentifier(
                    deviceId: deviceCtrl.text,
                    secret: secretCtrl.text,
                  );
                  if (resultat['ok'] == true) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    // 🖥️ La tablette devient une borne : bascule immédiate en
                    //    mode kiosque, sans attendre un rechargement de config.
                    if (mounted) {
                      setState(() {
                        _kioskMode = true;
                        _bornePrete = true;
                      });
                    }
                    await _chargerTousEmbeddingsEntreprise();
                    await _detecterEmployesNonEnroles();
                  } else {
                    setDialogState(() {});
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(resultat['erreur'] ??
                              "Borne refusée — identifiants invalides."),
                          backgroundColor: Colors.red.shade700,
                        ),
                      );
                    }
                  }
                },
                child: const Text("Activer la borne"),
              ),
            ],
          ],
        ),
      ),
    );
    deviceCtrl.dispose();
    secretCtrl.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 🤖 BOUTON FACE SCAN
  // ═══════════════════════════════════════════════════════════

  Widget _buildBoutonFaceScan({required VoidCallback onTap}) {
    String subtitle;
    if (_kioskMode) {
      subtitle = 'Approchez-vous pour être reconnu';
    } else if (_faceEnrolled && _faceApproved) {
      subtitle = _faceEmployeeName != null
          ? 'Bonjour $_faceEmployeeName'
          : 'Pointage par reconnaissance faciale';
    } else if (_faceEnrolled && !_faceApproved) {
      subtitle = 'Enrôlement en attente de validation';
    } else {
      subtitle = 'Première utilisation : identification requise';
    }

    return GestureDetector(
      onTap: chargement ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [EnCheckColors.brunProfond, Color(0xFF2D1F0E)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: EnCheckColors.terreChaude.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: EnCheckColors.terreChaude.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EnCheckColors.terreChaude.withOpacity(0.08),
                border: Border.all(
                    color: EnCheckColors.terreChaude.withOpacity(0.3),
                    width: 1.5),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ..._buildScanCorners(),
                  Icon(
                    _kioskMode
                        ? Icons.people
                        : (_faceEnrolled && _faceApproved
                        ? Icons.person
                        : Icons.person_add_outlined),
                    color: EnCheckColors.terreChaude,
                    size: 42,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'RECONNAISSANCE FACIALE',
              style: TextStyle(
                  color: EnCheckColors.terreChaude,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: EnCheckColors.sableDore.withOpacity(0.7),
                  fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    EnCheckColors.orDoux.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: EnCheckColors.terreChaude.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: EnCheckColors.terreChaude.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _kioskMode
                        ? Icons.people_outline
                        : (_faceEnrolled && _faceApproved
                        ? Icons.shield_outlined
                        : _faceEnrolled
                        ? Icons.hourglass_top
                        : Icons.info_outline),
                    color: EnCheckColors.terreChaude,
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _kioskMode
                        ? 'Mode tablette — identification auto'
                        : (_faceEnrolled && _faceApproved
                        ? 'Biométrie sécurisée'
                        : _faceEnrolled
                        ? 'En attente de validation'
                        : 'Enrôlement requis'),
                    style: const TextStyle(
                        color: EnCheckColors.terreChaude,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildScanCorners() {
    return [
      Positioned(top: 10, left: 10, child: _buildCoin(topLeft: true)),
      Positioned(top: 10, right: 10, child: _buildCoin(topRight: true)),
      Positioned(bottom: 10, left: 10, child: _buildCoin(bottomLeft: true)),
      Positioned(
          bottom: 10, right: 10, child: _buildCoin(bottomRight: true)),
    ];
  }

  Widget _buildCoin({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        border: Border(
          top: (topLeft || topRight)
              ? BorderSide(
              color: EnCheckColors.orDoux.withOpacity(0.8), width: 2)
              : BorderSide.none,
          bottom: (bottomLeft || bottomRight)
              ? BorderSide(
              color: EnCheckColors.orDoux.withOpacity(0.8), width: 2)
              : BorderSide.none,
          left: (topLeft || bottomLeft)
              ? BorderSide(
              color: EnCheckColors.orDoux.withOpacity(0.8), width: 2)
              : BorderSide.none,
          right: (topRight || bottomRight)
              ? BorderSide(
              color: EnCheckColors.orDoux.withOpacity(0.8), width: 2)
              : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildBoutonModeSecondaire({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border:
          Border.all(color: EnCheckColors.terreChaude.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: EnCheckColors.terreChaude.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: EnCheckColors.terreChaude, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle,
                        style: const TextStyle(
                            color: EnCheckColors.gris, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: EnCheckColors.terreChaude.withOpacity(0.5), size: 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 📱 MODES PIN / QR
  // ═══════════════════════════════════════════════════════════

  Widget _buildModePIN() {
    return Column(
      children: [
        if (_moduleRecoFacialeActif) ...[
          _buildBoutonRetour(() {
            setState(() {
              _modeSelectionne = null;
              numeroMatricule = '';
              codePin = '';
              afficherPin = false;
            });
          }),
          const SizedBox(height: 16),
        ],
        _buildInputCard(),
        const SizedBox(height: 20),
        if (chargement)
          const Padding(
            padding: EdgeInsets.all(20),
            child:
            CircularProgressIndicator(color: EnCheckColors.terreChaude),
          )
        else
          _buildClavier(),
      ],
    );
  }

  Widget _buildModeQR() {
    return Column(
      children: [
        if (_moduleRecoFacialeActif) ...[
          _buildBoutonRetour(() => setState(() => _modeSelectionne = null)),
          const SizedBox(height: 16),
        ],
        _buildQRIcon(),
        const SizedBox(height: 30),
        Text(
          'Présentez votre badge',
          style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 22,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 40),
        if (chargement)
          const CircularProgressIndicator(color: EnCheckColors.terreChaude)
        else
          _buildBoutonScanner(
            _modulePhotoActif ? 'SCANNER (avec photo)' : 'SCANNER MON BADGE',
                () {
              if (_modulePhotoActif) {
                setState(() => _showPhotoScanner = true);
              } else {
                setState(() => _showScanner = true);
              }
            },
          ),
      ],
    );
  }

  Widget _buildModePINSimple() {
    return Column(
      children: [
        _buildInputCard(),
        const SizedBox(height: 20),
        if (chargement)
          const Padding(
            padding: EdgeInsets.all(20),
            child:
            CircularProgressIndicator(color: EnCheckColors.terreChaude),
          )
        else
          _buildClavier(),
      ],
    );
  }

  Widget _buildModePINPhoto() {
    return Column(
      children: [
        _buildPhotoIndicator(),
        const SizedBox(height: 20),
        _buildInputCard(),
        const SizedBox(height: 20),
        if (chargement)
          const Padding(
            padding: EdgeInsets.all(20),
            child:
            CircularProgressIndicator(color: EnCheckColors.terreChaude),
          )
        else
          _buildClavier(),
      ],
    );
  }

  Widget _buildModeQRSimple() {
    return Column(
      children: [
        _buildQRIcon(),
        const SizedBox(height: 30),
        Text(
          'Présentez votre badge',
          style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 22,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 40),
        if (chargement)
          const CircularProgressIndicator(color: EnCheckColors.terreChaude)
        else
          _buildBoutonScanner('SCANNER MON BADGE', () {
            setState(() => _showScanner = true);
          }),
      ],
    );
  }

  Widget _buildModeQRPhoto() {
    return Column(
      children: [
        _buildPhotoIndicator(),
        const SizedBox(height: 20),
        _buildQRIcon(),
        const SizedBox(height: 30),
        Text(
          'Présentez votre badge',
          style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 22,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 40),
        if (chargement)
          const CircularProgressIndicator(color: EnCheckColors.terreChaude)
        else
          _buildBoutonScanner('SCANNER MON BADGE', () {
            setState(() => _showPhotoScanner = true);
          }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🧩 WIDGETS COMMUNS
  // ═══════════════════════════════════════════════════════════

  Widget _buildIndicateursModules() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        if (_moduleGeofencingActif)
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: EnCheckColors.terreChaude.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: EnCheckColors.terreChaude.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _gpsVerifie
                      ? (_verificationZone?['is_within_zone'] == true
                      ? Icons.location_on
                      : _verificationZone?['is_within_zone'] == false
                      ? Icons.location_off
                      : Icons.my_location)
                      : Icons.gps_not_fixed,
                  color: _gpsVerifie
                      ? (_verificationZone?['is_within_zone'] == true
                      ? EnCheckColors.succes
                      : _verificationZone?['is_within_zone'] == false
                      ? EnCheckColors.erreur
                      : EnCheckColors.terreChaude)
                      : EnCheckColors.terreChaude,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _gpsVerifie
                      ? (_verificationZone?['is_within_zone'] == true
                      ? 'Dans la zone ✓'
                      : _verificationZone?['is_within_zone'] == false
                      ? 'Hors zone ⚠'
                      : 'GPS vérifié')
                      : 'Géolocalisation active',
                  style: TextStyle(
                    color: _gpsVerifie
                        ? (_verificationZone?['is_within_zone'] == true
                        ? EnCheckColors.succes
                        : _verificationZone?['is_within_zone'] == false
                        ? EnCheckColors.erreur
                        : EnCheckColors.terreChaude)
                        : EnCheckColors.terreChaude,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (_kioskMode)
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border:
              Border.all(color: Colors.indigo.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tablet_android,
                    color: Colors.indigo.shade300, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Mode tablette',
                  style: TextStyle(
                      color: Colors.indigo.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBoutonRetour(VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: EnCheckColors.terreChaude.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_ios,
                  color: EnCheckColors.terreChaude, size: 14),
              SizedBox(width: 4),
              Text('Retour',
                  style: TextStyle(
                      color: EnCheckColors.terreChaude, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: EnCheckColors.terreChaude.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border:
        Border.all(color: EnCheckColors.terreChaude.withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt, color: EnCheckColors.terreChaude, size: 18),
          SizedBox(width: 8),
          Text('Photo de pointage activée',
              style: TextStyle(
                  color: EnCheckColors.terreChaude,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildQRIcon() {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: EnCheckColors.terreChaude.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(Icons.qr_code_2,
          size: 100, color: EnCheckColors.terreChaude),
    );
  }

  Widget _buildBoutonScanner(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [EnCheckColors.terreChaude, EnCheckColors.orDoux]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: EnCheckColors.terreChaude.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner,
                color: EnCheckColors.blanc, size: 32),
            const SizedBox(width: 15),
            Text(text,
                style: const TextStyle(
                    color: EnCheckColors.blanc,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool estEnLigne, ThemeService themeService) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: estEnLigne ? EnCheckColors.succes : EnCheckColors.erreur,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(estEnLigne ? Icons.wifi : Icons.wifi_off,
                      color: EnCheckColors.blanc, size: 16),
                  const SizedBox(width: 5),
                  Text(estEnLigne ? 'En ligne' : 'Hors-ligne',
                      style: const TextStyle(
                          color: EnCheckColors.blanc, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: syncEnCours ? null : _lancerSynchronisation,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: EnCheckColors.terreChaude,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    if (syncEnCours)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    else
                      const Icon(Icons.sync,
                          color: EnCheckColors.blanc, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      pointagesEnAttente > 0
                          ? '$pointagesEnAttente en attente'
                          : 'Sync',
                      style: const TextStyle(
                          color: EnCheckColors.blanc,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBoutonMaJournee(),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => themeService.toggleTheme(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1), blurRadius: 5),
                  ],
                ),
                child: Icon(
                  themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: EnCheckColors.terreChaude,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 📅 « MA JOURNÉE » — CONSULTER SANS POINTER
  // ═══════════════════════════════════════════════════════════

  /// Bouton d'accès à l'historique de la journée.
  ///
  /// LE PROBLÈME QU'IL RÈSOUT : avant, le bouton HISTORIQUE n'existait que
  /// dans la fenêtre de confirmation affichée APRÈS un pointage réussi. Un
  /// employé qui voulait simplement vérifier sa journée devait donc d'abord
  /// pointer — et ce pointage, justement, venait fausser la journée qu'il
  /// voulait consulter.
  ///
  /// Ce bouton demande le matricule et le PIN, puis ouvre l'historique sans
  /// rien enregistrer.
  Widget _buildBoutonMaJournee() {
    return GestureDetector(
      onTap: _ouvrirHistoriqueJournee,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: EnCheckColors.terreChaude,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.today_outlined, color: EnCheckColors.blanc, size: 16),
            SizedBox(width: 6),
            Text(
              'Ma journée',
              style: TextStyle(
                color: EnCheckColors.blanc,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Demande matricule + PIN, vérifie l'employé, puis ouvre l'historique.
  ///
  /// Aucun pointage n'est créé : c'est toute la différence avec
  /// _identifierEtEnroler, qui enchaîne l'identification et le pointage.
  Future<void> _ouvrirHistoriqueJournee() async {
    if (entrepriseSelectionnee == null) {
      _afficherErreur('Aucune entreprise sélectionnée.');
      return;
    }

    final matriculeController = TextEditingController();
    final pinController = TextEditingController();
    bool afficherPinLocal = false;
    bool verificationEnCours = false;
    String? messageErreur;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.today_outlined,
                  color: EnCheckColors.terreChaude),
              const SizedBox(width: 10),
              Text(
                'MA JOURNÉE',
                style: TextStyle(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w300,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saisissez votre matricule et votre PIN pour consulter vos '
                  'pointages du jour. Aucun pointage ne sera enregistré.',
                  style: TextStyle(color: EnCheckColors.gris, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: matriculeController,
                  keyboardType: TextInputType.number,
                  enabled: !verificationEnCours,
                  decoration: InputDecoration(
                    labelText: 'Matricule',
                    prefixText:
                        '${entrepriseSelectionnee!['matricule_prefix'] ?? ''}-',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (afficherPinLocal) ...[
                  const SizedBox(height: 15),
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    enabled: !verificationEnCours,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
                if (messageErreur != null) ...[
                  const SizedBox(height: 15),
                  Text(
                    messageErreur!,
                    style: const TextStyle(
                        color: EnCheckColors.erreur, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: verificationEnCours ? null : () => Navigator.pop(ctx),
              child: Text(
                'ANNULER',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: EnCheckColors.terreChaude,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: verificationEnCours
                  ? null
                  : () async {
                      if (!afficherPinLocal) {
                        if (matriculeController.text.trim().isEmpty) return;
                        setModalState(() => afficherPinLocal = true);
                        return;
                      }

                      if (pinController.text.length < 4) {
                        setModalState(() => messageErreur =
                            'Le PIN doit contenir au moins 4 chiffres.');
                        return;
                      }

                      setModalState(() {
                        verificationEnCours = true;
                        messageErreur = null;
                      });

                      final matriculeComplet =
                          '${entrepriseSelectionnee!['matricule_prefix']}-'
                          '${matriculeController.text.trim()}';

                      try {
                        // Même logique que _identifierEtEnroler : on lit le
                        // cache local quand la connexion manque.
                        final employee = ConnectivityService.isOnline
                            ? await SupabaseService.verifierEmployee(
                                entrepriseSelectionnee!['id'],
                                matriculeComplet,
                                pinController.text,
                              )
                            : await LocalDatabase.verifierEmployeeCache(
                                entrepriseSelectionnee!['id'],
                                matriculeComplet,
                                pinController.text,
                              );

                        if (!mounted) return;

                        if (employee == null) {
                          setModalState(() {
                            verificationEnCours = false;
                            messageErreur = _messageIdentifiants(
                                estHorsLigne: !ConnectivityService.isOnline,
                                type: 'pin');
                          });
                          return;
                        }

                        Navigator.pop(ctx);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HistoriqueScreen(employee: employee),
                          ),
                        );
                      } catch (e) {
                        setModalState(() {
                          verificationEnCours = false;
                          messageErreur = 'Vérification impossible : $e';
                        });
                      }
                    },
              child: verificationEnCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(afficherPinLocal ? 'CONSULTER' : 'SUIVANT'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarteEntreprise() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (entrepriseSelectionnee?['logo_url'] != null &&
              entrepriseSelectionnee!['logo_url'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  entrepriseSelectionnee!['logo_url'],
                  height: 30,
                  width: 30,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.business,
                      color: EnCheckColors.terreChaude),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.business, color: EnCheckColors.terreChaude),
            ),
          Flexible(
            child: Text(
              entrepriseSelectionnee?['name'] ?? 'Entreprise non chargée',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🎨 Refonte design : frise « perles zoulou » en tête de la carte
        //    MATRICULE — l'écran où l'on rencontre les personnes.
        const BandeMotif.zoulou(height: 14),
        const SizedBox(height: 8),
        Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(afficherPin ? 'CODE PIN' : 'MATRICULE',
                  style: EnCheckTextStyles.titreSecondaire),
              if (afficherPin)
                GestureDetector(
                  onTap: () => setState(() {
                    afficherPin = false;
                    codePin = '';
                  }),
                  child: const Text('← Retour',
                      style: TextStyle(
                          color: EnCheckColors.terreChaude, fontSize: 14)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              afficherPin
                  ? (codePin.isEmpty ? '● ● ● ●' : '● ' * codePin.length)
                  : matriculeComplet,
              style: EnCheckTextStyles.chiffresMono.copyWith(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                letterSpacing: afficherPin ? 8 : 4,
              ),
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }

  Widget _buildClavier() {
    return Column(
      children: [
        _construireLigneClavier(['1', '2', '3']),
        const SizedBox(height: 12),
        _construireLigneClavier(['4', '5', '6']),
        const SizedBox(height: 12),
        _construireLigneClavier(['7', '8', '9']),
        const SizedBox(height: 12),
        _construireLigneClavier(['⌫', '0', '✓']),
      ],
    );
  }

  Widget _construireLigneClavier(List<String> touches) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: touches.map((t) => _construireTouche(t)).toList(),
    );
  }

  Widget _construireTouche(String touche) {
    Color couleurFond;
    Color couleurTexte;

    if (touche == '✓') {
      couleurFond = EnCheckColors.terreChaude;
      couleurTexte = EnCheckColors.blanc;
    } else if (touche == '⌫') {
      couleurFond = Theme.of(context).cardColor == EnCheckColors.blanc
          ? EnCheckColors.brunProfond
          : EnCheckColors.gris;
      couleurTexte = EnCheckColors.blanc;
    } else {
      couleurFond = Theme.of(context).cardColor;
      couleurTexte = Theme.of(context).textTheme.bodyLarge?.color ??
          EnCheckColors.brunProfond;
    }

    return GestureDetector(
      onTap: () => _onToucheAppuyee(touche),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: couleurFond,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Center(
          child: Text(touche,
              style: TextStyle(
                  color: couleurTexte,
                  fontSize: 24,
                  fontWeight: FontWeight.w400)),
        ),
      ),
    );
  }

  /// ⭐ LIVRAISON 22 — l'écart chiffré, quand la tablette n'est pas sur le
  /// fuseau de l'entreprise. Discret, jamais bloquant : il n'apparaît que si
  /// les deux fuseaux diffèrent vraiment (au moins une minute).
  Widget _buildAvisFuseau() {
    final avis = HeurePointage.avisEcartTablette();
    if (avis == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
      child: Text(
        avis,
        textAlign: TextAlign.center,
        style: EnCheckTextStyles.titreSecondaire.copyWith(
          fontSize: 12,
          color: EnCheckColors.terreChaude,
        ),
      ),
    );
  }

  Widget _buildSeparateur() {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            EnCheckColors.sableDore,
            EnCheckColors.terreChaude,
            EnCheckColors.sableDore,
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🎯 CLAVIER
  // ═══════════════════════════════════════════════════════════

  void _onToucheAppuyee(String touche) {
    if (chargement) return;
    setState(() {
      if (touche == '⌫') {
        if (afficherPin && codePin.isNotEmpty) {
          codePin = codePin.substring(0, codePin.length - 1);
        } else if (!afficherPin && numeroMatricule.isNotEmpty) {
          numeroMatricule =
              numeroMatricule.substring(0, numeroMatricule.length - 1);
        }
      } else if (touche == '✓') {
        if (!afficherPin) {
          if (numeroMatricule.isNotEmpty) afficherPin = true;
        } else {
          if (codePin.length >= 4) _validerPointagePIN();
        }
      } else {
        if (afficherPin && codePin.length < 4) {
          codePin += touche;
        } else if (!afficherPin && numeroMatricule.length < 6) {
          numeroMatricule += touche;
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 📱 VALIDATION PIN
  // ═══════════════════════════════════════════════════════════

  Future<void> _validerPointagePIN() async {
    if (entrepriseSelectionnee == null) return;

    // ⏸ En MODE PAUSE, le GPS ne bloque jamais (fiche LOT D) : « Hors site »
    //    reste informatif. Le contrôle n'est fait que pour un vrai pointage.
    if (_moduleGeofencingActif && _intention != 'pause') {
      final gpsOk = await _verifierPositionGPS();
      if (!gpsOk) return;
    }

    setState(() => chargement = true);

    try {
      Map<String, dynamic>? employee;
      final estHorsLigne = !ConnectivityService.isOnline;

      if (estHorsLigne) {
        employee = await LocalDatabase.verifierEmployeeCache(
            entrepriseSelectionnee!['id'], matriculeComplet, codePin);
      } else {
        employee = await SupabaseService.verifierEmployee(
            entrepriseSelectionnee!['id'], matriculeComplet, codePin);
      }

      if (employee != null) {
        _extraireSchedule(employee);

        // ⏸ MODE PAUSE : identifié → la feuille de pause, et RIEN d'autre.
        if (_intention == 'pause') {
          setState(() {
            chargement = false;
            numeroMatricule = '';
            codePin = '';
            afficherPin = false;
            _modeSelectionne = null;
            _gpsVerifie = false;
            _currentPosition = null;
            _verificationZone = null;
          });
          await _ouvrirFeuillePause(employee);
          return;
        }

        if (_modulePhotoActif && !_moduleQRActif) {
          if (kIsWeb) {
            // ── Web → WebCameraWidget ──
            setState(() {
              _pendingEmployeeWebCamera = employee;
              _webCameraRaison = 'pin';
              _showWebCamera = true;
              chargement = false;
            });
          } else {
            // ── Mobile → PinPhotoWidget natif ──
            setState(() {
              _pendingEmployee = employee;
              _showPinPhoto = true;
              chargement = false;
            });
          }
        } else {
          await _traiterPointage(employee, 'pin', estHorsLigne, null);
          setState(() {
            chargement = false;
            numeroMatricule = '';
            codePin = '';
            afficherPin = false;
            _modeSelectionne = null;
            _gpsVerifie = false;
            _currentPosition = null;
            _verificationZone = null;
          });
        }
      } else {
        _afficherErreur(
            _messageIdentifiants(estHorsLigne: estHorsLigne, type: 'pin'));
        setState(() => chargement = false);
      }
    } catch (e) {
      _afficherErreur('Erreur: $e');
      setState(() => chargement = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📷 CALLBACKS
  // ═══════════════════════════════════════════════════════════

  Future<void> _onPinPhotoTaken(Uint8List? photoBytes) async {
    setState(() => _showPinPhoto = false);
    if (_pendingEmployee != null) {
      final estHorsLigne = !ConnectivityService.isOnline;
      await _traiterPointage(
          _pendingEmployee!, 'pin_photo', estHorsLigne, photoBytes);
    }
    setState(() {
      _pendingEmployee = null;
      numeroMatricule = '';
      codePin = '';
      afficherPin = false;
      _modeSelectionne = null;
      _gpsVerifie = false;
      _currentPosition = null;
      _verificationZone = null;
    });
  }

  void _onQRScanned(String code) {
    setState(() => _showScanner = false);
    _validerPointageQR(code, null);
  }

  void _onQRPhotoCompleted(String qrCode, Uint8List? photoBytes) {
    setState(() => _showPhotoScanner = false);

    if (kIsWeb && _modulePhotoActif) {
      // ── Web : QR validé → WebCameraWidget pour la photo ──
      _validerPointageQRPuisPhoto(qrCode);
    } else {
      // ── Mobile : photo déjà dans photoBytes ──
      _validerPointageQR(qrCode, photoBytes);
    }
  }

  // ── QR validé sur Web → chercher l'employé puis ouvrir WebCameraWidget ──
  Future<void> _validerPointageQRPuisPhoto(String qrCode) async {
    if (entrepriseSelectionnee == null) return;

    // ⏸ En MODE PAUSE, le GPS ne bloque jamais (fiche LOT D).
    if (_moduleGeofencingActif && _intention != 'pause') {
      final gpsOk = await _verifierPositionGPS();
      if (!gpsOk) return;
    }

    setState(() => chargement = true);

    try {
      final estHorsLigne = !ConnectivityService.isOnline;
      Map<String, dynamic>? employee;

      if (estHorsLigne) {
        employee = await LocalDatabase.verifierEmployeeParQR(
            entrepriseSelectionnee!['id'], qrCode);
      } else {
        employee = await SupabaseService.verifierEmployeeParQR(
            entrepriseSelectionnee!['id'], qrCode);
      }

      if (employee == null) {
        _afficherErreur(
            _messageIdentifiants(estHorsLigne: estHorsLigne, type: 'qr'));
        setState(() => chargement = false);
        return;
      }

      _extraireSchedule(employee);

      // ⏸ MODE PAUSE : pas de photo, pas de pointage — la feuille de pause.
      if (_intention == 'pause') {
        setState(() {
          chargement = false;
          _modeSelectionne = null;
          _gpsVerifie = false;
          _currentPosition = null;
          _verificationZone = null;
        });
        await _ouvrirFeuillePause(employee);
        return;
      }

      // QR validé → ouvrir WebCameraWidget
      setState(() {
        chargement = false;
        _pendingEmployeeWebCamera = employee;
        _webCameraRaison = 'qr';
        _showWebCamera = true;
      });
    } catch (e) {
      _afficherErreur('Erreur: $e');
      setState(() => chargement = false);
    }
  }

  Future<void> _validerPointageQR(
      String qrCode, Uint8List? photoBytes) async {
    if (entrepriseSelectionnee == null) return;

    // ⏸ En MODE PAUSE, le GPS ne bloque jamais (fiche LOT D).
    if (_moduleGeofencingActif && _intention != 'pause') {
      final gpsOk = await _verifierPositionGPS();
      if (!gpsOk) return;
    }

    setState(() => chargement = true);

    try {
      final estHorsLigne = !ConnectivityService.isOnline;
      Map<String, dynamic>? employee;

      if (estHorsLigne) {
        employee = await LocalDatabase.verifierEmployeeParQR(
            entrepriseSelectionnee!['id'], qrCode);
      } else {
        employee = await SupabaseService.verifierEmployeeParQR(
            entrepriseSelectionnee!['id'], qrCode);
      }

      if (employee != null) {
        _extraireSchedule(employee);

        // ⏸ MODE PAUSE : identifié → la feuille de pause, sans pointage.
        if (_intention == 'pause') {
          setState(() {
            chargement = false;
            _modeSelectionne = null;
            _gpsVerifie = false;
            _currentPosition = null;
            _verificationZone = null;
          });
          await _ouvrirFeuillePause(employee);
          return;
        }

        final method = photoBytes != null ? 'qr_photo' : 'qr_code';
        await _traiterPointage(employee, method, estHorsLigne, photoBytes);
      } else {
        _afficherErreur(
            _messageIdentifiants(estHorsLigne: estHorsLigne, type: 'qr'));
      }
    } catch (e) {
      _afficherErreur('Erreur: $e');
    }

    setState(() {
      chargement = false;
      _modeSelectionne = null;
      _gpsVerifie = false;
      _currentPosition = null;
      _verificationZone = null;
    });
  }

  /// 💬 CONTRAT D'ACCÈS (25/10/2026) — message honnête selon la cause réelle
  /// d'un échec d'identification : plus de vide silencieux ni de « incorrect »
  /// mensonger quand c'est le réseau ou le cache de la tablette.
  String _messageIdentifiants(
      {required bool estHorsLigne, required String type}) {
    if (estHorsLigne) {
      return type == 'qr'
          ? 'Badge incorrect — ou jamais utilisé sur cette tablette (hors-ligne).'
          : 'Matricule ou PIN incorrect — ou employé jamais identifié sur '
              'cette tablette (hors-ligne).';
    }
    final panne = SupabaseService.derniereErreur;
    if (panne != null) {
      return 'Connexion au serveur impossible : $panne';
    }
    return type == 'qr' ? 'Badge non reconnu' : 'Matricule ou PIN incorrect';
  }

  void _extraireSchedule(Map<String, dynamic> employee) {
    final rawSchedules = employee['employee_schedules'];
    if (rawSchedules is List && rawSchedules.isNotEmpty) {
      _employeeSchedule = rawSchedules.first;
    } else if (rawSchedules is Map) {
      _employeeSchedule = rawSchedules as Map<String, dynamic>;
    } else {
      _employeeSchedule = null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ TRAITER POINTAGE PIN/QR
  // ═══════════════════════════════════════════════════════════

  Future<void> _traiterPointage(
      Map<String, dynamic> employee,
      String method,
      bool estHorsLigne,
      Uint8List? photoBytes,
      ) async {
    // ⭐ LIVRAISON 21 — LE VERROU, POSÉ AVANT LE PREMIER await.
    //    Un second geste parti pendant que le premier est encore en vol pour le
    //    MÊME employé n'enregistre rien.
    if (_pointageEnCoursPour == employee['id']) return;
    _pointageEnCoursPour = employee['id'];

    try {
      String typePointage = 'in';
      try {
        final dernierPointage =
        await LocalDatabase.dernierPointageCombine(employee['id']);

        // ⭐ LIVRAISON 21 — LE GESTE DOUBLE N'ÉCRIT PLUS RIEN.
        //    Le type du pointage est déduit du DERNIER pointage connu (local ou
        //    serveur) : une seconde validation à quelques secondes d'intervalle
        //    prenait donc le type OPPOSÉ et fabriquait une session fantôme.
        //    C'est exactement le défaut trouvé en production : 29 paires en
        //    30 jours, les 6 employés, dont l'entrée 20:01:06 suivie d'une
        //    sortie 20:01:15 (9 secondes).
        //    Même seuil que la base : 60 secondes (livraison 20, §1).
        final instantPrecedent = dernierPointage == null
            ? null
            : HeurePointage.instant(dernierPointage);
        if (dernierPointage != null && instantPrecedent != null) {
          final ecartSecondes =
              DateTime.now().toUtc().difference(instantPrecedent).inSeconds;
          if (ecartSecondes >= 0 && ecartSecondes < 60) {
            if (mounted) {
              _afficherDejaPointe(employee, dernierPointage, ecartSecondes);
            }
            return;   // ← RIEN n'est enregistré, ni en local ni au serveur
          }
        }

        if (dernierPointage?['check_type'] == 'in') typePointage = 'out';
      } catch (_) {}

      // ── LE CERVEAU : la base affine la décision ─────────────────────
      // La bascule locale ne regarde que le DERNIER pointage. La base, elle,
      // en connaît l'ancienneté : elle peut donc repérer une sortie oubliée
      // et remettre la séquence d'aplomb, au lieu de l'inverser pour de bon.
      String confiance = 'haute';
      String origineDecision = 'bascule_locale';
      String? anomalie;
      double? seuilPresenceHeures;

      if (ConnectivityService.isOnline) {
        final suggestion = await SupabaseService.typeSuggere(employee['id']);
        if (suggestion != null && suggestion['ok'] == true) {
          typePointage = (suggestion['type'] as String?) ?? typePointage;
          confiance = (suggestion['confiance'] as String?) ?? 'haute';
          origineDecision = (suggestion['raison'] as String?) ?? 'serveur';
          anomalie = suggestion['anomalie'] as String?;
          // Le seuil d'oubli vient de la base (encheck_reglages_pointage) :
          // jamais de chiffre en dur dans l'interface (fiche 2/3, cohérence).
          seuilPresenceHeures =
              (suggestion['seuil_presence_heures'] as num?)?.toDouble();
        }
      }

      // Le système doute vraiment (par exemple une entrée vieille de plus du
      // seuil d'oubli) : plutôt que de deviner, on laisse l'employé trancher.
      if (confiance == 'basse') {
        final choix = await _demanderTypePointage(
            typePointage, anomalie, seuilPresenceHeures);
        if (choix == null) return;   // annulé : RIEN n'est enregistré
        typePointage = choix;
        origineDecision = 'manuel_employe';
        // ⭐ FICHE ARBITRAGE 2/3, P1 — un doute TRANCHÉ PAR L'HUMAIN n'est
        //    plus une anomalie. On remplace l'anomalie du doute (typiquement
        //    'sortie_oubliee') par le code neutre 'resolution_employe' :
        //    la base ne marquera donc JAMAIS suspect un « Départ » choisi en
        //    toute connaissance de cause par l'employé (cas Hippo, 16/10).
        anomalie = 'resolution_employe';
      }

      bool success;
      String? pointageId;

      if (estHorsLigne) {
        await LocalDatabase.sauvegarderPointagePending(
          employeeId: employee['id'],
          enterpriseId: entrepriseSelectionnee!['id'],
          checkType: typePointage,
          method: method,
        );
        if (photoBytes != null) {
          await PhotoService.sauvegarderLocalement(
            photoBytes: photoBytes,
            enterpriseId: entrepriseSelectionnee!['id'],
            employeeId: employee['id'],
          );
        }
        success = true;
      } else {
        pointageId = await GeofencingService.enregistrerPointageAvecGeo(
          employeeId: employee['id'],
          enterpriseId: employee['enterprise_id'],
          checkType: typePointage,
          method: method,
          position: _currentPosition,
          verificationZone: _verificationZone,
        );
        success = pointageId != null;

        if (success && photoBytes != null && pointageId != null) {
          await PhotoService.uploadEtEnregistrer(
            photoBytes: photoBytes,
            enterpriseId: entrepriseSelectionnee!['id'],
            employeeId: employee['id'],
            pointageId: pointageId,
          );
        }
      }

      if (success) {
        if (!estHorsLigne) {
          SyncService.synchroniserPointages();

          // Traçabilité : on inscrit comment le type a été décidé, pour que
          // l'admin puisse retrouver les cas douteux. Sans conséquence si la
          // base refuse : le pointage, lui, est déjà enregistré.
          if (pointageId != null) {
            await SupabaseService.marquerPointage(
              attendanceId: pointageId,
              origine: origineDecision == 'manuel_employe' ? 'manuel' : 'auto',
              raison: origineDecision,
              anomalie: anomalie,
            );
          }
        }
        await _compterPointagesEnAttente();
        if (mounted) {
          _afficherSucces(employee['first_name'], employee['last_name'],
              typePointage, estHorsLigne, employee, photoBytes,
              attendanceId: estHorsLigne ? null : pointageId);
        }
      } else {
        if (mounted) _afficherErreur('Erreur lors de l\'enregistrement');
      }
    } catch (e) {
      if (mounted) _afficherErreur('Erreur inattendue : $e');
    } finally {
      // Quoi qu'il arrive — succès, erreur ou sortie anticipée — le verrou est
      // retiré : aucune tablette ne reste bloquée sur un pointage en cours.
      if (_pointageEnCoursPour == employee['id']) _pointageEnCoursPour = null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ DIALOG SUCCÈS PIN/QR
  // ═══════════════════════════════════════════════════════════

  String? _getEmployeeScheduleInfo() {
    if (_employeeSchedule == null) return null;
    if (_employeeSchedule!['use_custom_hours'] == true) {
      final start = _employeeSchedule!['custom_start_time']
          ?.toString()
          .substring(0, 5) ??
          '--:--';
      final end = _employeeSchedule!['custom_end_time']
          ?.toString()
          .substring(0, 5) ??
          '--:--';
      return '$start - $end';
    }
    if (_employeeSchedule!['work_schedules'] != null) {
      final schedule = _employeeSchedule!['work_schedules'];
      final start =
          schedule['start_time']?.toString().substring(0, 5) ?? '--:--';
      final end = schedule['end_time']?.toString().substring(0, 5) ?? '--:--';
      return '${schedule['name'] ?? 'Planning'} ($start - $end)';
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // ⛔ LIVRAISON 21 — « DÉJÀ POINTÉ » : le second geste n'écrit rien
  // ═══════════════════════════════════════════════════════════

  /// Montre à l'employé le pointage qui vient d'être fait, et n'enregistre RIEN.
  ///
  /// C'est le pendant exact, côté application, du déclencheur posé en base
  /// (livraison 20) : au lieu de laisser la base signaler après coup une paire
  /// à 9 secondes d'intervalle, l'application empêche la seconde ligne
  /// d'exister. L'employé comprend ce qui s'est passé, rien n'est perdu.
  void _afficherDejaPointe(
    Map<String, dynamic> employee,
    Map<String, dynamic> dernierPointage,
    int ecartSecondes,
  ) {
    final estEntree = dernierPointage['check_type'] == 'in';
    final heure = HeurePointage.heureDePointage(dernierPointage);
    final secondes = ecartSecondes <= 1 ? '1 seconde' : '$ecartSecondes secondes';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.timer_outlined,
                color: EnCheckColors.terreChaude, size: 30),
            const SizedBox(width: 10),
            const Text(
              'DÉJÀ POINTÉ',
              style: TextStyle(
                  color: EnCheckColors.terreChaude,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bonjour ${employee['first_name']} ${employee['last_name']}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Votre ${estEntree ? 'ENTRÉE' : 'SORTIE'} de $heure a bien été '
              'enregistrée, il y a $secondes.',
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color),
            ),
            const SizedBox(height: 12),
            Text(
              'Rien n\'a été ajouté : un second pointage à moins d\'une minute '
              'n\'est jamais pris en compte.',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
  }

  void _afficherSucces(
      String prenom,
      String nom,
      String type,
      bool horsLigne,
      Map<String, dynamic> employee,
      Uint8List? photoBytes, {
        /// Identifiant du pointage côté serveur. Sans lui, aucune correction
        /// n'est proposée (cas du hors-ligne : le pointage n'existe pas encore
        /// sur le serveur, il attend dans la file d'attente locale).
        String? attendanceId,
      }) {
    final estEntree = type == 'in';
    final horaires = _getEmployeeScheduleInfo();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(estEntree ? Icons.login : Icons.logout,
                color: EnCheckColors.succes, size: 30),
            const SizedBox(width: 10),
            Text(
              estEntree ? 'ENTRÉE' : 'SORTIE',
              style: const TextStyle(
                  color: EnCheckColors.succes,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoBytes != null) ...[
                Center(
                  child: Container(
                    width: 100,
                    height: 130,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border:
                      Border.all(color: EnCheckColors.succes, width: 3),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(photoBytes, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
              ],
              Text(
                'Bonjour $prenom $nom',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Pointage enregistré à $heureActuelle',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color),
              ),
              if (_verificationZone != null &&
                  _verificationZone!['is_within_zone'] != null) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_verificationZone!['is_within_zone'] == true
                        ? EnCheckColors.succes
                        : EnCheckColors.erreur)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _verificationZone!['is_within_zone'] == true
                          ? EnCheckColors.succes
                          : EnCheckColors.erreur,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _verificationZone!['is_within_zone'] == true
                            ? Icons.location_on
                            : Icons.location_off,
                        color: _verificationZone!['is_within_zone'] == true
                            ? EnCheckColors.succes
                            : EnCheckColors.erreur,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _verificationZone!['is_within_zone'] == true
                            ? 'Dans la zone autorisée'
                            : 'Hors zone',
                        style: TextStyle(
                          color: _verificationZone!['is_within_zone'] == true
                              ? EnCheckColors.succes
                              : EnCheckColors.erreur,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (horaires != null) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EnCheckColors.terreChaude.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule,
                          color: EnCheckColors.terreChaude, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Vos horaires',
                                style: TextStyle(
                                    color: EnCheckColors.terreChaude,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                            Text(horaires,
                                style: const TextStyle(
                                    color: EnCheckColors.terreChaude,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (horsLigne) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EnCheckColors.terreChaude.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off,
                          color: EnCheckColors.terreChaude, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sauvegardé hors-ligne.\nSera synchronisé automatiquement.',
                          style: TextStyle(
                              color: EnCheckColors.terreChaude, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          // L'employé peut corriger son propre type. La base limite la
          // fenêtre à 30 minutes et garde la trace : l'admin verra dans la
          // page Pointages que ce pointage a été modifié.
          if (attendanceId != null)
            TextButton(
              onPressed: () => _demanderCorrectionType(
                  attendanceId, employee, type),
              child: const Text('CORRIGER',
                  style: TextStyle(
                      color: EnCheckColors.terreChaude, letterSpacing: 2)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        HistoriqueScreen(employee: employee)),
              );
            },
            child: Text('HISTORIQUE',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    letterSpacing: 2)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                numeroMatricule = '';
                codePin = '';
                afficherPin = false;
                _modeSelectionne = null;
                _gpsVerifie = false;
                _currentPosition = null;
                _verificationZone = null;
              });
            },
            child: const Text('FERMER',
                style: TextStyle(
                    color: EnCheckColors.terreChaude, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ❌ ERREURS
  // ═══════════════════════════════════════════════════════════

  void _afficherErreurGeofencing(Map<String, dynamic> verification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_off, color: EnCheckColors.erreur, size: 30),
            SizedBox(width: 10),
            Text('HORS ZONE',
                style: TextStyle(
                    color: EnCheckColors.erreur,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2)),
          ],
        ),
        content: Text(
          verification['message'] ?? 'Vous êtes hors de la zone autorisée',
          style:
          TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('COMPRIS',
                style: TextStyle(
                    color: EnCheckColors.terreChaude, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }

  void _afficherErreur(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: EnCheckColors.erreur, size: 30),
            SizedBox(width: 10),
            Text('ERREUR',
                style: TextStyle(
                    color: EnCheckColors.erreur,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2)),
          ],
        ),
        content: Text(message,
            style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => codePin = '');
            },
            child: const Text('RÉESSAYER',
                style: TextStyle(
                    color: EnCheckColors.terreChaude, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }
}
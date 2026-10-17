// lib/screens/face_pointage_screen.dart
// Compatible Mobile (complet) + Web (message d'indisponibilité)

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:ui' as ui;
import '../services/local_database.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../services/face_recognition_service_provider.dart';

// Imports conditionnels pour mobile uniquement
// ignore: uri_does_not_exist
import 'package:camera/camera.dart' if (dart.library.html) '../stubs/camera_stub.dart';
// ignore: uri_does_not_exist
import 'package:geolocator/geolocator.dart' if (dart.library.html) '../stubs/geolocator_stub.dart';

class FacePointageScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  final String enterpriseId;
  final Map<String, dynamic> config;
  final bool moduleGeofencingActif;
  final Function(Map<String, dynamic> result) onPointageComplete;
  final VoidCallback onCancel;
  final VoidCallback? onFallback;
  final dynamic positionGPS; // Position ou null
  final Map<String, dynamic>? verificationZone;
  final bool kioskMode;

  /// 🎯 MODE PAUSE (visibilité, 17/10/2026) : quand c'est `true`, le visage
  /// sert UNIQUEMENT à reconnaître l'employé — AUCUN pointage n'est
  /// enregistré. Le résultat `identification_seule` part dans
  /// `onPointageComplete` pour ouvrir la feuille de pause.
  final bool identificationSeule;

  const FacePointageScreen({
    super.key,
    required this.employee,
    required this.enterpriseId,
    required this.config,
    required this.moduleGeofencingActif,
    required this.onPointageComplete,
    required this.onCancel,
    this.onFallback,
    this.positionGPS,
    this.verificationZone,
    this.kioskMode = false,
    this.identificationSeule = false,
  });

  @override
  State<FacePointageScreen> createState() => _FacePointageScreenState();
}

class _FacePointageScreenState extends State<FacePointageScreen> {
  // Variables mobiles uniquement
  dynamic _cameraController;
  bool _cameraInitialized = false;
  bool _isProcessing = false;
  bool _scanning = true;
  Timer? _analyseTimer;

  String _feedbackMessage = 'Placez votre visage dans le cadre';
  bool _visageDetecte = false;
  bool _qualiteOk = false;

  int _tentatives = 0;
  bool _showFallback = false;

  bool _pointageEnCours = false;
  bool _pointageTermine = false;
  Map<String, dynamic>? _resultats;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initialiserCamera();
      FaceRecognitionService.initialiser();
    }
  }

  @override
  void dispose() {
    _analyseTimer?.cancel();
    if (!kIsWeb && _cameraController != null) {
      (_cameraController as CameraController).dispose();
    }
    super.dispose();
  }

  Future<void> _initialiserCamera() async {
    if (kIsWeb) return;

    try {
      final cameras = await availableCameras();
      CameraDescription? frontCamera;

      for (final cam in cameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          frontCamera = cam;
          break;
        }
      }

      frontCamera ??= cameras.isNotEmpty ? cameras.first : null;
      if (frontCamera == null) return;

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      _cameraController = controller;

      if (mounted) {
        setState(() {
          _cameraInitialized = true;
          _feedbackMessage = widget.kioskMode
              ? 'Approchez-vous pour être reconnu'
              : 'Placez votre visage dans le cadre';
        });
        _demarrerAnalysePeriodique();
      }
    } catch (e) {
      debugPrint('❌ Erreur caméra: $e');
    }
  }

  void _demarrerAnalysePeriodique() {
    if (kIsWeb) return;
    _analyseTimer?.cancel();
    _analyseTimer = Timer.periodic(
      const Duration(milliseconds: 800),
          (timer) async {
        if (!_scanning || _pointageTermine || _isProcessing) return;
        await _analyserFrame();
      },
    );
  }

  Future<void> _analyserFrame() async {
    if (kIsWeb || _isProcessing || !_scanning) return;
    _isProcessing = true;

    try {
      final controller = _cameraController as CameraController;
      final XFile photo = await controller.takePicture();

      final faces = await FaceRecognitionService.detecterVisagesDepuisFichier(photo.path);

      if (faces.isEmpty) {
        _mettreAJourFeedback(
          widget.kioskMode ? 'Approchez-vous pour être reconnu' : 'Placez votre visage dans le cadre',
          false, false,
        );
        return;
      }

      if (faces.length > 1) {
        _mettreAJourFeedback('Un seul visage à la fois', true, false);
        return;
      }

      final face = faces.first;
      final livenessRequired = widget.config['liveness_required'] as bool? ?? true;
      bool livenessOk = true;

      if (livenessRequired) {
        final liveness = FaceRecognitionService.verifierLiveness(face);
        livenessOk = liveness['liveness_ok'];
        if (!livenessOk) {
          _mettreAJourFeedback(liveness['message'], true, false);
          return;
        }
      }

      _mettreAJourFeedback('Analyse en cours...', true, true);

      final photoBytes = await photo.readAsBytes();
      await _tenterReconnaissance(photoBytes, face, livenessOk);
    } catch (e) {
      // Silencieux
    } finally {
      _isProcessing = false;
    }
  }

  void _mettreAJourFeedback(String message, bool visage, bool qualite) {
    if (mounted) {
      setState(() {
        _feedbackMessage = message;
        _visageDetecte = visage;
        _qualiteOk = qualite;
      });
    }
  }

  Future<void> _tenterReconnaissance(Uint8List photoBytes, dynamic face, bool livenessOk) async {
    if (kIsWeb) return;

    setState(() => _scanning = false);
    _analyseTimer?.cancel();

    try {
      final embeddingLive = await FaceRecognitionService.extraireEmbedding(photoBytes, face);

      if (embeddingLive == null) {
        _echecReconnaissance();
        return;
      }

      if (widget.kioskMode) {
        await _identifierParmiTous(embeddingLive, livenessOk);
      } else {
        await _verifierEmployeConnu(embeddingLive, livenessOk);
      }
    } catch (e) {
      debugPrint('❌ Erreur reconnaissance: $e');
      _echecReconnaissance();
    }
  }

  Future<void> _identifierParmiTous(List<double> embeddingLive, bool livenessOk) async {
    final threshold = (widget.config['confidence_threshold'] as num?)?.toDouble() ?? 0.80;
    Map<String, dynamic>? meilleurEmployee;
    double meilleurScore = 0;

    final tousEmbeddings = await LocalDatabase.getTousEmbeddings(widget.enterpriseId);

    if (tousEmbeddings.isEmpty) {
      _afficherErreurMessage('Aucun profil facial enrôlé.\nVeuillez d\'abord enrôler les employés.');
      return;
    }

    for (final embeddingData in tousEmbeddings) {
      final embeddingRef = List<double>.from(embeddingData['embedding'] as List);
      final score = FaceRecognitionService.calculerSimilarite(embeddingLive, embeddingRef);

      if (score > meilleurScore) {
        meilleurScore = score;
        final empId = embeddingData['employee_id'] as String;
        final emp = await LocalDatabase.getEmployeeParId(empId);
        if (emp != null) meilleurEmployee = emp;
      }
    }

    if (meilleurScore >= threshold && meilleurEmployee != null) {
      await _validerPointage(meilleurScore, livenessOk, employee: meilleurEmployee);
    } else {
      _tentatives++;
      final maxAttempts = (widget.config['max_attempts'] as int?) ?? 3;

      if (_tentatives >= maxAttempts) {
        _afficherErreurMessage('Visage non reconnu après $_tentatives tentatives.');
      } else {
        _mettreAJourFeedback('Non reconnu ($_tentatives/$maxAttempts). Réessayez.', false, false);
        setState(() => _scanning = true);
        _demarrerAnalysePeriodique();
      }
    }
  }

  Future<void> _verifierEmployeConnu(List<double> embeddingLive, bool livenessOk) async {
    final embeddingData = await LocalDatabase.getEmbedding(widget.employee['id']);

    if (embeddingData == null) {
      _afficherErreurMessage('Profil facial non trouvé. Veuillez vous enrôler.');
      return;
    }

    final embeddingRef = List<double>.from(embeddingData['embedding'] as List);
    final score = FaceRecognitionService.calculerSimilarite(embeddingLive, embeddingRef);
    final threshold = (widget.config['confidence_threshold'] as num?)?.toDouble() ?? 0.80;

    if (ConnectivityService.isOnline) {
      await SupabaseService.loggerTentativeFaciale(
        enterpriseId: widget.enterpriseId,
        employeeId: widget.employee['id'],
        score: score,
        matched: score >= threshold,
        livenessPassee: livenessOk,
      );
    }

    if (score >= threshold) {
      await _validerPointage(score, livenessOk);
    } else {
      _tentatives++;
      final maxAttempts = (widget.config['max_attempts'] as int?) ?? 3;

      if (_tentatives >= maxAttempts) {
        final fallbackAllowed = widget.config['fallback_allowed'] as bool? ?? true;
        final pointageMode = widget.config['pointage_mode'] as String? ?? 'free';

        if (fallbackAllowed && pointageMode != 'face_exclusive' && widget.onFallback != null) {
          setState(() => _showFallback = true);
        } else {
          _afficherErreurMessage('Reconnaissance impossible. Contactez votre administrateur.');
        }
      } else {
        _echecReconnaissance();
      }
    }
  }

  Future<void> _validerPointage(double score, bool livenessOk, {Map<String, dynamic>? employee}) async {
    setState(() => _pointageEnCours = true);
    final emp = employee ?? widget.employee;

    // 🎯 MODE PAUSE : reconnu → on rend l'identité et on s'arrête ICI.
    //    Aucun pointage n'est écrit (règle d'or : la pause passe uniquement
    //    par les 2 RPC de pause, jamais par `attendances`).
    if (widget.identificationSeule) {
      setState(() {
        _pointageTermine = true;
        _pointageEnCours = false;
      });
      widget.onPointageComplete({
        'identification_seule': true,
        'score': score,
        'liveness_ok': livenessOk,
        'employee_id': emp['id'],
        'employee': emp,
      });
      return;
    }

    try {
      final dernierPointage = await LocalDatabase.dernierPointageCombine(emp['id']);
      final checkType = (dernierPointage?['check_type'] == 'in') ? 'out' : 'in';

      String? pointageId;
      double? lat, lng, acc;

      if (widget.positionGPS != null) {
        final pos = widget.positionGPS;
        lat = pos.latitude;
        lng = pos.longitude;
        acc = pos.accuracy;
      }

      if (ConnectivityService.isOnline) {
        pointageId = await SupabaseService.enregistrerPointageFacial(
          employeeId: emp['id'],
          enterpriseId: widget.enterpriseId,
          checkType: checkType,
          faceScore: score,
          livenessPassee: livenessOk,
          faceAttempts: _tentatives + 1,
          locationLat: lat,
          locationLng: lng,
          gpsAccuracy: acc,
          geofenceId: widget.verificationZone?['geofence_id'],
          distanceMeters: widget.verificationZone?['distance_meters'],
          isWithinZone: widget.verificationZone?['is_within_zone'],
        );
      } else {
        await LocalDatabase.sauvegarderPointagePending(
          employeeId: emp['id'],
          enterpriseId: widget.enterpriseId,
          checkType: checkType,
          method: 'face',
        );
      }

      setState(() {
        _pointageTermine = true;
        _pointageEnCours = false;
        _resultats = {
          'check_type': checkType,
          'score': score,
          'liveness_ok': livenessOk,
          'is_within_zone': widget.verificationZone?['is_within_zone'],
          'employee_id': emp['id'],
          'employee': emp,
          'pointage_id': pointageId,
          'offline': !ConnectivityService.isOnline,
        };
      });
    } catch (e) {
      debugPrint('❌ Erreur validation pointage: $e');
      setState(() => _pointageEnCours = false);
      _echecReconnaissance();
    }
  }

  void _echecReconnaissance() {
    setState(() => _scanning = true);
    _mettreAJourFeedback(
      'Visage non reconnu ($_tentatives essai${_tentatives > 1 ? 's' : ''}). Réessayez.',
      false, false,
    );
    _demarrerAnalysePeriodique();
  }

  void _afficherErreurMessage(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: EnCheckColors.erreur),
            SizedBox(width: 10),
            Text('Erreur', style: TextStyle(color: EnCheckColors.erreur)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onCancel();
            },
            child: const Text('Fermer', style: TextStyle(color: EnCheckColors.terreChaude)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ══════════════════════════════════════════════════
    // WEB : Écran d'indisponibilité
    // ══════════════════════════════════════════════════
    if (kIsWeb) {
      return _buildWebUnavailableScreen();
    }

    // ══════════════════════════════════════════════════
    // MOBILE : Écrans normaux
    // ══════════════════════════════════════════════════
    if (_pointageTermine && _resultats != null) return _buildSuccesScreen();
    if (_showFallback) return _buildFallbackScreen();
    if (_pointageEnCours) return _buildTraitementScreen();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Aperçu caméra
                  if (_cameraInitialized && _cameraController != null)
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: CameraPreview(_cameraController as CameraController),
                    )
                  else
                    const Center(child: CircularProgressIndicator(color: EnCheckColors.terreChaude)),

                  // Cadre ovale
                  CustomPaint(
                    size: MediaQuery.of(context).size,
                    painter: _FacePointageCadrePainter(
                      couleur: _qualiteOk
                          ? EnCheckColors.succes
                          : _visageDetecte
                          ? EnCheckColors.terreChaude
                          : Colors.white54,
                    ),
                  ),

                  // Feedback
                  Positioned(
                    bottom: 40,
                    left: 20,
                    right: 20,
                    child: Column(
                      children: [
                        if (_tentatives > 0)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: EnCheckColors.erreur.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: EnCheckColors.erreur),
                            ),
                            child: Text(
                              'Tentative $_tentatives/${widget.config['max_attempts'] ?? 3}',
                              style: const TextStyle(color: EnCheckColors.erreur, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _qualiteOk ? EnCheckColors.succes : Colors.white24),
                          ),
                          child: Text(
                            _feedbackMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _qualiteOk ? EnCheckColors.succes : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // ÉCRANS
  // ══════════════════════════════════════════════════════════

  Widget _buildWebUnavailableScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: Colors.black,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: widget.onCancel,
                    child: const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Text('Pointage par visage', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: EnCheckColors.erreur.withOpacity(0.15),
                          border: Border.all(color: EnCheckColors.erreur.withOpacity(0.4), width: 2),
                        ),
                        child: const Icon(Icons.face_retouching_off, color: EnCheckColors.erreur, size: 50),
                      ),
                      const SizedBox(height: 28),
                      const Text('Non disponible sur Web', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      const Text(
                        'La reconnaissance faciale nécessite l\'application mobile native.',
                        style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.7),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: widget.onCancel,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Retour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EnCheckColors.terreChaude,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      if (widget.onFallback != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.onFallback,
                            icon: const Icon(Icons.swap_horiz, color: Colors.white54),
                            label: const Text('Utiliser un autre mode', style: TextStyle(color: Colors.white54, fontSize: 14)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    Color gpsIconColor = Colors.white54;
    IconData gpsIcon = Icons.location_on;

    if (widget.moduleGeofencingActif && widget.verificationZone != null) {
      if (widget.verificationZone!['is_within_zone'] == true) {
        gpsIconColor = EnCheckColors.succes;
      } else if (widget.verificationZone!['is_within_zone'] == false) {
        gpsIconColor = EnCheckColors.erreur;
        gpsIcon = Icons.location_off;
      } else {
        gpsIconColor = EnCheckColors.terreChaude;
        gpsIcon = Icons.my_location;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.black,
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onCancel,
            child: const Icon(Icons.close, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pointage par visage', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  widget.kioskMode ? 'Identification automatique...' : 'Regardez la caméra',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          if (widget.moduleGeofencingActif)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: gpsIconColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: gpsIconColor.withOpacity(0.4)),
              ),
              child: Icon(gpsIcon, color: gpsIconColor, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildTraitementScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EnCheckColors.terreChaude.withOpacity(0.2),
                  border: Border.all(color: EnCheckColors.terreChaude, width: 3),
                ),
                child: const CircularProgressIndicator(color: EnCheckColors.terreChaude, strokeWidth: 3),
              ),
              const SizedBox(height: 30),
              const Text('Analyse en cours...', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccesScreen() {
    final estEntree = _resultats!['check_type'] == 'in';
    final score = (_resultats!['score'] as double) * 100;
    final emp = _resultats!['employee'] as Map<String, dynamic>?;
    final nomAffiche = emp != null ? '${emp['first_name']} ${emp['last_name']}' : '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EnCheckColors.succes.withOpacity(0.2),
                  border: Border.all(color: EnCheckColors.succes, width: 3),
                ),
                child: Icon(estEntree ? Icons.login : Icons.logout, color: EnCheckColors.succes, size: 50),
              ),
              const SizedBox(height: 24),
              Text(
                estEntree ? 'ENTRÉE' : 'SORTIE',
                style: const TextStyle(color: EnCheckColors.succes, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3),
              ),
              const SizedBox(height: 12),
              Text(nomAffiche, style: const TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('👤 Reconnaissance', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text('${score.toStringAsFixed(0)}%', style: const TextStyle(color: EnCheckColors.succes, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => widget.onPointageComplete(_resultats!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnCheckColors.terreChaude,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Fermer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.face_retouching_off, size: 80, color: EnCheckColors.erreur),
              const SizedBox(height: 24),
              const Text('Reconnaissance échouée', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                'Après ${widget.config['max_attempts'] ?? 3} tentatives, la reconnaissance n\'a pas pu vous identifier.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.grey, height: 1.6),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onFallback,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Utiliser un autre mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnCheckColors.terreChaude,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PAINTER — utilise dart:ui Size
// ══════════════════════════════════════════════════════════════

class _FacePointageCadrePainter extends CustomPainter {
  final Color couleur;
  _FacePointageCadrePainter({required this.couleur});

  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 60),
      width: size.width * 0.72,
      height: size.height * 0.48,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(_FacePointageCadrePainter oldDelegate) => oldDelegate.couleur != couleur;
}
// lib/screens/face_enrollment_screen.dart
// Compatible Mobile + Web

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/face_recognition_service_provider.dart';
import '../services/supabase_service.dart';
import '../services/local_database.dart';
import '../theme/app_theme.dart';

// Import conditionnel
import 'package:camera/camera.dart' if (dart.library.html) '../stubs/camera_stub.dart';

class FaceEnrollmentScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  final String enterpriseId;
  final bool adminApprovalRequired;
  final VoidCallback onEnrollmentComplete;
  final VoidCallback onCancel;

  const FaceEnrollmentScreen({
    super.key,
    required this.employee,
    required this.enterpriseId,
    required this.adminApprovalRequired,
    required this.onEnrollmentComplete,
    required this.onCancel,
  });

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  dynamic _cameraController;
  bool _cameraInitialized = false;
  bool _isProcessing = false;

  int _currentStep = 0;
  final List<String> _instructions = [
    'Regardez droit devant',
    'Tournez légèrement à gauche',
    'Tournez légèrement à droite',
    'Levez légèrement le menton',
  ];

  final List<List<double>> _embeddings = [];
  Uint8List? _photoEnrolement;

  String _feedbackMessage = 'Préparez-vous...';
  bool _qualiteOk = false;

  bool _enrolementTermine = false;
  bool _enregistrementEnCours = false;

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
          _feedbackMessage = _instructions[_currentStep];
          _qualiteOk = true;
        });
      }
    } catch (e) {
      print('❌ Erreur caméra: $e');
    }
  }

  Future<void> _capturerEtape() async {
    if (_isProcessing || kIsWeb) return;
    setState(() => _isProcessing = true);

    try {
      final controller = _cameraController as CameraController;

      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      final XFile photo = await controller.takePicture();
      final Uint8List photoBytes = await photo.readAsBytes();

      final faces = await FaceRecognitionService.detecterVisagesDepuisFichier(photo.path);

      if (faces.isEmpty) {
        _afficherErreur('Aucun visage détecté.');
        setState(() {
          _isProcessing = false;
          _qualiteOk = true;
        });
        return;
      }

      if (faces.length > 1) {
        _afficherErreur('Plusieurs visages détectés.');
        setState(() {
          _isProcessing = false;
          _qualiteOk = true;
        });
        return;
      }

      final embedding = await FaceRecognitionService.extraireEmbedding(photoBytes, faces.first);

      if (embedding == null) {
        _afficherErreur('Erreur extraction.');
        setState(() {
          _isProcessing = false;
          _qualiteOk = true;
        });
        return;
      }

      _embeddings.add(embedding);
      if (_currentStep == 0) _photoEnrolement = photoBytes;

      setState(() {
        _currentStep++;
        _isProcessing = false;
      });

      if (_currentStep >= _instructions.length) {
        await _finaliserEnrolement();
      } else {
        setState(() {
          _feedbackMessage = _instructions[_currentStep];
          _qualiteOk = true;
        });
      }
    } catch (e) {
      print('❌ Erreur capture: $e');
      setState(() {
        _isProcessing = false;
        _qualiteOk = true;
      });
    }
  }

  Future<void> _finaliserEnrolement() async {
    setState(() {
      _enrolementTermine = true;
      _enregistrementEnCours = true;
    });

    try {
      final embeddingMoyen = FaceRecognitionService.moyenneVecteurs(_embeddings);

      String? photoUrl;
      if (_photoEnrolement != null) {
        photoUrl = await SupabaseService.uploadPhotoEnrolement(
          photoBytes: _photoEnrolement!.toList(),
          enterpriseId: widget.enterpriseId,
          employeeId: widget.employee['id'],
        );
      }

      final enrollment = await SupabaseService.creerEnrolement(
        employeeId: widget.employee['id'],
        enterpriseId: widget.enterpriseId,
        embedding: embeddingMoyen,
        enrollmentPhotoUrl: photoUrl ?? '',
        adminApprovalRequired: widget.adminApprovalRequired,
      );

      if (enrollment == null) {
        _afficherErreur('Erreur sauvegarde.');
        setState(() {
          _enrolementTermine = false;
          _enregistrementEnCours = false;
          _currentStep = 0;
          _embeddings.clear();
        });
        return;
      }

      final status = widget.adminApprovalRequired ? 'pending' : 'approved';

      await LocalDatabase.sauvegarderStatutEnrolement(
        employeeId: widget.employee['id'],
        status: status,
        enrollmentId: enrollment['id'],
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('face_employee_id', widget.employee['id']);
      await prefs.setString('face_employee_name', '${widget.employee['first_name']} ${widget.employee['last_name']}');
      await prefs.setBool('face_enrolled', true);
      await prefs.setBool('face_approved', !widget.adminApprovalRequired);

      if (!widget.adminApprovalRequired) {
        await LocalDatabase.sauvegarderEmbedding(
          employeeId: widget.employee['id'],
          enterpriseId: widget.enterpriseId,
          embedding: embeddingMoyen,
          enrollmentId: enrollment['id'],
        );
      }

      setState(() => _enregistrementEnCours = false);
    } catch (e) {
      print('❌ Erreur finalisation: $e');
      setState(() => _enregistrementEnCours = false);
    }
  }

  void _afficherErreur(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: EnCheckColors.erreur),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebUnavailableScreen();
    if (_enrolementTermine && !_enregistrementEnCours) return _buildResultatScreen();
    if (_enregistrementEnCours) return _buildEnregistrementScreen();

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
                  if (_cameraInitialized && _cameraController != null)
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: CameraPreview(_cameraController as CameraController),
                    )
                  else
                    const Center(child: CircularProgressIndicator(color: EnCheckColors.terreChaude)),
                  CustomPaint(
                    size: MediaQuery.of(context).size,
                    painter: _FaceCadrePainter(couleur: _qualiteOk ? EnCheckColors.succes : Colors.white54),
                  ),
                  Positioned(
                    bottom: 120,
                    left: 20,
                    right: 20,
                    child: Container(
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildProgressBar(),
            _buildCaptureButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildWebUnavailableScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.face_retouching_off, color: EnCheckColors.erreur, size: 80),
                const SizedBox(height: 28),
                const Text('Enrôlement non disponible sur Web', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Retour'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EnCheckColors.terreChaude,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.black,
      child: Row(
        children: [
          GestureDetector(onTap: widget.onCancel, child: const Icon(Icons.close, color: Colors.white, size: 28)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enrôlement Facial', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${widget.employee['first_name']} ${widget.employee['last_name']}', style: const TextStyle(color: EnCheckColors.terreChaude, fontSize: 14)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: EnCheckColors.terreChaude.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: EnCheckColors.terreChaude),
            ),
            child: Text('${_currentStep + 1}/${_instructions.length}', style: const TextStyle(color: EnCheckColors.terreChaude, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
      child: Row(
        children: List.generate(_instructions.length, (index) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 6,
              decoration: BoxDecoration(
                color: index < _currentStep ? EnCheckColors.succes : index == _currentStep ? EnCheckColors.terreChaude : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _qualiteOk && !_isProcessing ? _capturerEtape : null,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _qualiteOk ? EnCheckColors.succes : Colors.white24,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: _isProcessing
            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
            : const Icon(Icons.camera_alt, color: Colors.white, size: 36),
      ),
    );
  }

  Widget _buildEnregistrementScreen() {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: EnCheckColors.terreChaude),
            SizedBox(height: 30),
            Text('Enregistrement...', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultatScreen() {
    final isPending = widget.adminApprovalRequired;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPending ? Icons.hourglass_top : Icons.check_circle,
                  color: isPending ? EnCheckColors.terreChaude : EnCheckColors.succes,
                  size: 80,
                ),
                const SizedBox(height: 30),
                Text(
                  isPending ? 'En attente de validation' : 'Enrôlement réussi !',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onEnrollmentComplete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EnCheckColors.terreChaude,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Continuer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaceCadrePainter extends CustomPainter {
  final Color couleur;
  _FaceCadrePainter({required this.couleur});

  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: size.width * 0.7,
      height: size.height * 0.45,
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
  bool shouldRepaint(_FaceCadrePainter oldDelegate) => oldDelegate.couleur != couleur;
}
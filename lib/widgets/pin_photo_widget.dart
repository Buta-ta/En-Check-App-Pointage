// lib/widgets/pin_photo_widget.dart
// Dispatch Mobile (camera native) / Web (getUserMedia)

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/app_theme.dart';
import 'web_camera_widget_provider.dart';
import 'dart:async';

// Import conditionnel caméra mobile
import '../stubs/camera_stub.dart'
if (dart.library.io) 'package:camera/camera.dart';

class PinPhotoWidget extends StatefulWidget {
  final String employeeName;
  final Function(Uint8List? photoBytes) onPhotoTaken;
  final VoidCallback onCancel;

  const PinPhotoWidget({
    super.key,
    required this.employeeName,
    required this.onPhotoTaken,
    required this.onCancel,
  });

  @override
  State<PinPhotoWidget> createState() => _PinPhotoWidgetState();
}

class _PinPhotoWidgetState extends State<PinPhotoWidget> {
  @override
  Widget build(BuildContext context) {
    // ══════════════════════════════════════════════════════
    // WEB → WebCameraWidget (getUserMedia)
    // ══════════════════════════════════════════════════════
    if (kIsWeb) {
      return WebCameraWidget(
        employeeName: widget.employeeName,
        onPhotoTaken: widget.onPhotoTaken,
        onCancel: widget.onCancel,
        raison: 'pin',
      );
    }

    // ══════════════════════════════════════════════════════
    // MOBILE → Widget caméra natif (code original)
    // ══════════════════════════════════════════════════════
    return _PinPhotoMobile(
      employeeName: widget.employeeName,
      onPhotoTaken: widget.onPhotoTaken,
      onCancel: widget.onCancel,
    );
  }
}

// ════════════════════════════════════════════════════════════
// VERSION MOBILE — code original inchangé
// ════════════════════════════════════════════════════════════

class _PinPhotoMobile extends StatefulWidget {
  final String employeeName;
  final Function(Uint8List? photoBytes) onPhotoTaken;
  final VoidCallback onCancel;

  const _PinPhotoMobile({
    required this.employeeName,
    required this.onPhotoTaken,
    required this.onCancel,
  });

  @override
  State<_PinPhotoMobile> createState() => _PinPhotoMobileState();
}

class _PinPhotoMobileState extends State<_PinPhotoMobile>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCameraError = false;
  bool _isCapturing = false;
  bool _photoTaken = false;
  Uint8List? _capturedPhoto;
  int _countdown = 2;
  Timer? _countdownTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCamera();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      CameraDescription? frontCamera;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }
      frontCamera ??= cameras.isNotEmpty ? cameras.first : null;
      if (frontCamera == null) {
        setState(() => _isCameraError = true);
        _skipPhoto();
        return;
      }
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _startCountdown();
      }
    } catch (e) {
      setState(() => _isCameraError = true);
      _skipPhoto();
    }
  }

  void _skipPhoto() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) widget.onPhotoTaken(null);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _isCapturing = true;
      _countdown = 2;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _capturePhoto();
      }
    });
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      widget.onPhotoTaken(null);
      return;
    }
    try {
      final XFile photo = await _cameraController!.takePicture();
      final Uint8List bytes = await photo.readAsBytes();
      setState(() {
        _capturedPhoto = bytes;
        _photoTaken = true;
      });
      await Future.delayed(const Duration(milliseconds: 1500));
      widget.onPhotoTaken(_capturedPhoto);
    } catch (e) {
      widget.onPhotoTaken(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isCameraInitialized && _cameraController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 100,
                  height: _cameraController!.value.previewSize?.width ?? 100,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            )
          else if (_isCameraError)
            Container(
              color: EnCheckColors.brunProfond,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, color: EnCheckColors.gris, size: 80),
                    SizedBox(height: 20),
                    Text('Caméra non disponible', style: TextStyle(color: EnCheckColors.gris, fontSize: 18)),
                  ],
                ),
              ),
            )
          else
            Container(
              color: EnCheckColors.brunProfond,
              child: const Center(child: CircularProgressIndicator(color: EnCheckColors.orDoux)),
            ),
          Container(color: Colors.black.withOpacity(0.3)),
          SafeArea(child: Center(child: _buildContent())),
          if (_photoTaken && _capturedPhoto != null)
            Positioned(
              bottom: 30,
              right: 30,
              child: Container(
                width: 110,
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: EnCheckColors.succes, width: 4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.memory(_capturedPhoto!, fit: BoxFit.cover),
                ),
              ),
            ),
          if (!_isCapturing)
            Positioned(
              top: 50,
              left: 20,
              child: SafeArea(
                child: GestureDetector(
                  onTap: widget.onCancel,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_photoTaken) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: EnCheckColors.succes.withOpacity(0.95),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 70),
            const SizedBox(height: 20),
            Text(
              'Bonjour ${widget.employeeName} !',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text('Pointage enregistré', style: TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
      );
    }
    if (_isCapturing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 30),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: EnCheckColors.brunProfond.withOpacity(0.95),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😊', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 20),
            const Text('Un petit sourire', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            const Text('et c\'est tout !', style: TextStyle(color: EnCheckColors.orDoux, fontSize: 20)),
            const SizedBox(height: 30),
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EnCheckColors.terreChaude,
                ),
                child: Center(
                  child: Text('$_countdown', style: const TextStyle(color: Colors.white, fontSize: 45, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
      margin: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: EnCheckColors.brunProfond.withOpacity(0.95),
        borderRadius: BorderRadius.circular(25),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: EnCheckColors.orDoux),
          SizedBox(height: 20),
          Text('Préparation...', style: TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
    );
  }
}
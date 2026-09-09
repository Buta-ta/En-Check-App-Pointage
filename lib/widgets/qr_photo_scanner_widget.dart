// lib/widgets/qr_photo_scanner_widget.dart
// ═══════════════════════════════════════════════════════════
// 📷 WIDGET SCANNER QR CODE + PHOTO
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

// Import conditionnel caméra
import '../stubs/camera_stub.dart' if (dart.library.io) 'package:camera/camera.dart' as cam;

// ═══════════════════════════════════════════════════════════
// LE RESTE DU FICHIER — IDENTIQUE MAIS AVEC PRÉFIXE cam.
// ═══════════════════════════════════════════════════════════

class QRPhotoScannerWidget extends StatefulWidget {
  final Function(String qrCode, Uint8List? photoBytes) onCompleted;
  final VoidCallback onClose;

  const QRPhotoScannerWidget({
    super.key,
    required this.onCompleted,
    required this.onClose,
  });

  @override
  State<QRPhotoScannerWidget> createState() => _QRPhotoScannerWidgetState();
}

class _QRPhotoScannerWidgetState extends State<QRPhotoScannerWidget>
    with TickerProviderStateMixin {
  MobileScannerController? _scannerController;
  cam.CameraController? _cameraController;
  bool _isCameraReady = false;

  bool _hasScanned = false;
  bool _isCapturingPhoto = false;
  bool _photoTaken = false;
  String? _scannedCode;
  Uint8List? _capturedPhoto;

  int _countdown = 2;
  Timer? _countdownTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initScanner();
    _initAnimations();
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.front,
      torchEnabled: false,
    );
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  // Remplacer UNIQUEMENT la méthode _initCameraForPhoto() :

  Future<void> _initCameraForPhoto() async {
    // ══════════════════════════════════════════════════════
    // WEB → pas de caméra native après QR
    // La photo web est gérée séparément via WebCameraWidget
    // dans pointage_screen après le scan QR
    // ══════════════════════════════════════════════════════
    if (kIsWeb) {
      // Sur web : compléter le scan QR sans photo ici
      // La photo sera prise par WebCameraWidget dans pointage_screen
      setState(() {
        _photoTaken = true;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      _completeProcess();
      return;
    }

    // ══════════════════════════════════════════════════════
    // MOBILE → code original inchangé
    // ══════════════════════════════════════════════════════
    try {
      await _scannerController?.stop();
      final cameras = await cam.availableCameras();
      cam.CameraDescription? frontCamera;
      for (final camera in cameras) {
        if (camera.lensDirection == cam.CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }
      frontCamera ??= cameras.isNotEmpty ? cameras.first : null;
      if (frontCamera == null) {
        _completeWithoutPhoto();
        return;
      }
      _cameraController = cam.CameraController(
        frontCamera,
        cam.ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: cam.ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
        _startPhotoCountdown();
      }
    } catch (e) {
      _completeWithoutPhoto();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _scannerController?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;

    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;

      if (code != null && code.isNotEmpty) {
        setState(() {
          _hasScanned = true;
          _scannedCode = code;
          _isCapturingPhoto = true;
        });
        _initCameraForPhoto();
        break;
      }
    }
  }

  void _startPhotoCountdown() {
    setState(() {
      _countdown = 2;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        _capturePhoto();
      }
    });
  }

  Future<void> _capturePhoto() async {
    if (kIsWeb) {
      _completeWithoutPhoto();
      return;
    }

    try {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        print('❌ Caméra non prête');
        _completeWithoutPhoto();
        return;
      }

      print('📸 Capture de la photo...');
      final cam.XFile photo = await _cameraController!.takePicture();
      final Uint8List bytes = await photo.readAsBytes();

      print('✅ Photo capturée: ${bytes.length} bytes');

      setState(() {
        _capturedPhoto = bytes;
        _photoTaken = true;
      });

      await Future.delayed(const Duration(milliseconds: 1500));
      _completeProcess();
    } catch (e) {
      print('❌ Erreur capture photo: $e');
      _completeWithoutPhoto();
    }
  }

  void _completeWithoutPhoto() {
    print('⚠️ Continuation sans photo');
    setState(() {
      _photoTaken = true;
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      _completeProcess();
    });
  }

  void _completeProcess() {
    print('🏁 Processus terminé - QR: $_scannedCode, Photo: ${_capturedPhoto?.length ?? 0} bytes');
    widget.onCompleted(_scannedCode!, _capturedPhoto);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!_hasScanned && _scannerController != null)
            MobileScanner(
              controller: _scannerController!,
              onDetect: _onDetect,
            )
          else if (_isCameraReady && _cameraController != null && !kIsWeb)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 100,
                  height: _cameraController!.value.previewSize?.width ?? 100,
                  child: cam.CameraPreview(_cameraController!),
                ),
              ),
            )
          else
            Container(color: Colors.black),
          _buildOverlay(),
          _buildHeader(),
          _buildCentralContent(),
          _buildCameraIndicator(),
          if (_photoTaken && _capturedPhoto != null) _buildPhotoPreview(),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(_isCapturingPhoto ? 0.3 : 0.5),
      ),
      child: Stack(
        children: [
          if (!_hasScanned)
            Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: EnCheckColors.orDoux, width: 3),
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.transparent,
                ),
              ),
            ),
          if (!_hasScanned)
            Center(
              child: SizedBox(
                width: 280,
                height: 280,
                child: CustomPaint(painter: _CornersPainter()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: _isCapturingPhoto ? null : widget.onClose,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.close,
                  color: _isCapturingPhoto ? Colors.grey : Colors.white,
                  size: 24,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _hasScanned
                    ? EnCheckColors.succes.withOpacity(0.8)
                    : Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _getHeaderTitle(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  String _getHeaderTitle() {
    if (_photoTaken) return '📸 Photo prise !';
    if (_isCapturingPhoto) return '✅ Badge reconnu';
    return 'Scanner le Badge';
  }

  Widget _buildCentralContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!_hasScanned) ...[
            const SizedBox(height: 200),
          ],
          if (_isCapturingPhoto && !_photoTaken) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: EnCheckColors.brunProfond.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: EnCheckColors.orDoux.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text('😊', style: TextStyle(fontSize: 50)),
                  const SizedBox(height: 15),
                  const Text(
                    'Un petit sourire',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'et c\'est tout !',
                    style: TextStyle(
                      color: EnCheckColors.orDoux,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 25),
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: EnCheckColors.terreChaude,
                        boxShadow: [
                          BoxShadow(
                            color: EnCheckColors.terreChaude.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '$_countdown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_photoTaken) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: EnCheckColors.succes.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 60),
                  SizedBox(height: 15),
                  Text(
                    'Pointage enregistré !',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraIndicator() {
    if (_isCapturingPhoto) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: EnCheckColors.brunProfond.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Montrez votre badge QR face à l\'écran',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          if (!_hasScanned)
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: EnCheckColors.orDoux,
                strokeWidth: 2,
              ),
            )
          else
            const Icon(Icons.check_circle, color: EnCheckColors.succes, size: 40),
        ],
      ),
    );
  }

  Widget _buildPhotoPreview() {
    return Positioned(
      bottom: 30,
      right: 30,
      child: Container(
        width: 100,
        height: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EnCheckColors.orDoux, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.memory(
            _capturedPhoto!,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EnCheckColors.orDoux
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 20.0;

    canvas.drawLine(const Offset(0, cornerLength), const Offset(0, radius), paint);
    canvas.drawArc(const Rect.fromLTWH(0, 0, radius * 2, radius * 2), 3.14, 0.5, false, paint);
    canvas.drawLine(const Offset(radius, 0), const Offset(cornerLength, 0), paint);

    canvas.drawLine(Offset(size.width - cornerLength, 0), Offset(size.width - radius, 0), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - radius * 2, 0, radius * 2, radius * 2), -0.5, 0.5, false, paint);
    canvas.drawLine(Offset(size.width, radius), Offset(size.width, cornerLength), paint);

    canvas.drawLine(Offset(size.width, size.height - cornerLength), Offset(size.width, size.height - radius), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - radius * 2, size.height - radius * 2, radius * 2, radius * 2), 0, 0.5, false, paint);
    canvas.drawLine(Offset(size.width - radius, size.height), Offset(size.width - cornerLength, size.height), paint);

    canvas.drawLine(Offset(cornerLength, size.height), Offset(radius, size.height), paint);
    canvas.drawArc(Rect.fromLTWH(0, size.height - radius * 2, radius * 2, radius * 2), 0.5, 0.5, false, paint);
    canvas.drawLine(Offset(0, size.height - radius), Offset(0, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
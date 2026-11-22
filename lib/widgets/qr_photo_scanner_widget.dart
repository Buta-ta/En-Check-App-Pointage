// lib/widgets/qr_photo_scanner_widget.dart
// ═══════════════════════════════════════════════════════════
// 📷 WIDGET SCANNER QR CODE + PHOTO
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import 'qr_scanner_chrome.dart';

// Import conditionnel caméra
import '../stubs/camera_stub.dart' if (dart.library.io) 'package:camera/camera.dart' as cam;

// ═══════════════════════════════════════════════════════════
// LE RESTE DU FICHIER — IDENTIQUE MAIS AVEC PRÉFIXE cam.
// ═══════════════════════════════════════════════════════════

class QRPhotoScannerWidget extends StatefulWidget {
  final Function(String qrCode, Uint8List? photoBytes) onCompleted;
  final VoidCallback onClose;
  final VoidCallback? onPinFallback;

  const QRPhotoScannerWidget({
    super.key,
    required this.onCompleted,
    required this.onClose,
    this.onPinFallback,
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
  bool _photoUnavailable = false;
  bool _photoDeferredToWebCamera = false;
  bool _photoCameraFailed = false;
  bool _processCompleted = false;
  bool _isFrontScanner = true;
  MobileScannerErrorCode? _cameraError;
  MobileScannerErrorCode? _queuedCameraError;
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
        _photoDeferredToWebCamera = true;
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
        await _setPhotoCameraError();
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
      await _setPhotoCameraError();
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
      await _setPhotoCameraError();
      return;
    }

    try {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        print('❌ Caméra non prête');
        await _setPhotoCameraError();
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
      await _setPhotoCameraError();
    }
  }

  Future<void> _setPhotoCameraError() async {
    final cameraController = _cameraController;
    _cameraController = null;
    await cameraController?.dispose();
    if (!mounted) return;
    setState(() {
      _isCameraReady = false;
      _photoCameraFailed = true;
    });
  }

  Future<void> _retryPhotoCamera() async {
    if (!mounted) return;
    await _cameraController?.dispose();
    setState(() => _photoCameraFailed = false);
    await _initCameraForPhoto();
  }

  void _continueWithoutPhoto() {
    if (!mounted) return;
    setState(() {
      _photoTaken = true;
      _photoUnavailable = true;
      _photoCameraFailed = false;
      _isCapturingPhoto = false;
    });
    Future.delayed(const Duration(milliseconds: 500), _completeProcess);
  }

  void _completeProcess() {
    if (_processCompleted || !mounted || _scannedCode == null) return;
    _processCompleted = true;
    print('🏁 Processus terminé - QR: $_scannedCode, Photo: ${_capturedPhoto?.length ?? 0} bytes');
    widget.onCompleted(_scannedCode!, _capturedPhoto);
  }

  void _queueCameraError(MobileScannerException exception) {
    final code = exception.errorCode;
    if (_cameraError == code || _queuedCameraError == code) return;
    _queuedCameraError = code;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queuedCameraError = null;
      if (_cameraError != code) setState(() => _cameraError = code);
    });
  }

  Future<void> _retryScanner() async {
    setState(() => _cameraError = null);
    try {
      await _scannerController?.start();
    } catch (_) {
      // L'erreur sera renvoyée par MobileScanner.errorBuilder.
    }
  }

  Future<void> _switchScannerCamera() async {
    try {
      await _scannerController?.switchCamera();
      if (mounted) setState(() => _isFrontScanner = !_isFrontScanner);
    } catch (_) {
      // Si l'appareil n'a qu'un objectif, le scan reste disponible.
    }
  }

  Future<void> _toggleScannerTorch() async {
    try {
      await _scannerController?.toggleTorch();
      if (mounted) setState(() {});
    } catch (_) {
      // La lampe peut ne pas être prise en charge par cet appareil.
    }
  }

  String? get _cameraErrorTitle {
    switch (_cameraError) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Autorisez l’accès à la caméra';
      case MobileScannerErrorCode.unsupported:
        return 'Caméra indisponible';
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.controllerAlreadyInitialized:
      case MobileScannerErrorCode.genericError:
        return 'Impossible d’ouvrir la caméra';
      case null:
        return null;
    }
  }

  String? get _cameraErrorMessage {
    switch (_cameraError) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Autorisez l’accès à la caméra dans les réglages, puis réessayez.';
      case MobileScannerErrorCode.unsupported:
        return 'Cet appareil ou ce navigateur ne prend pas en charge la lecture caméra.';
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.controllerAlreadyInitialized:
      case MobileScannerErrorCode.genericError:
        return 'Vérifiez la caméra puis réessayez, ou utilisez le code PIN.';
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = _scannerController;
    final scanning = !_hasScanned && scanner != null;
    final Widget cameraPreview;
    if (scanning) {
      cameraPreview = MobileScanner(
        controller: scanner!,
        onDetect: _onDetect,
        errorBuilder: (context, exception, child) {
          _queueCameraError(exception);
          return const ColoredBox(color: Color(0xFF292824));
        },
      );
    } else if (_isCameraReady && _cameraController != null && !kIsWeb) {
      cameraPreview = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 100.0,
            height: _cameraController!.value.previewSize?.width ?? 100.0,
            child: cam.CameraPreview(_cameraController!),
          ),
        ),
      );
    } else {
      cameraPreview = const ColoredBox(color: Color(0xFF292824));
    }

    final isCapturing = _isCapturingPhoto && !_photoTaken;
    return QrScannerChrome(
      cameraPreview: cameraPreview,
      onClose: widget.onClose,
      headerTitle: isCapturing || _photoDeferredToWebCamera
          ? 'Badge reconnu'
          : _photoTaken
              ? (_photoUnavailable ? 'Photo indisponible' : 'Photo prise')
              : 'Scanner le badge',
      instruction: isCapturing
          ? 'Regardez l’écran : la photo de contrôle va être prise.'
          : _photoTaken
              ? 'Le pointage continue.'
              : 'Montrez le QR code du badge face à la caméra',
      statusLabel: scanning
          ? 'Recherche du QR code…'
          : _photoDeferredToWebCamera
              ? 'Ouverture de la caméra de contrôle…'
              : isCapturing
                  ? 'Photo de contrôle en cours…'
                  : _photoUnavailable
                      ? 'La lecture QR reste valide'
                      : 'Photo capturée — poursuite du pointage…',
      cameraLabel: scanning
          ? (_isFrontScanner ? 'Caméra frontale' : 'Caméra arrière')
          : 'Caméra frontale',
      isFrontCamera: scanning ? _isFrontScanner : true,
      showTorchButton: scanning,
      torchAvailable:
          scanning && scanner?.value.torchState != TorchState.unavailable,
      torchEnabled: scanning && scanner?.value.torchState == TorchState.on,
      showSwitchButton: scanning,
      onToggleTorch: _toggleScannerTorch,
      onSwitchCamera: _switchScannerCamera,
      showViewfinder: scanning,
      isBusy: _isCapturingPhoto && !_photoCameraFailed,
      onPinFallback: _photoCameraFailed
          ? _continueWithoutPhoto
          : scanning
              ? widget.onPinFallback
              : null,
      pinFallbackLabel:
          _photoCameraFailed ? 'Continuer sans photo' : 'Utiliser le code PIN',
      centerContent: scanning ? null : _buildPhotoCaptureContent(),
      cameraErrorTitle: _photoCameraFailed
          ? 'Caméra de contrôle indisponible'
          : _cameraErrorTitle,
      cameraErrorMessage: _photoCameraFailed
          ? 'Réessayez la caméra ou continuez le pointage sans photo.'
          : _cameraErrorMessage,
      onRetryCamera: _photoCameraFailed ? _retryPhotoCamera : _retryScanner,
      foregroundOverlay:
          _photoTaken && _capturedPhoto != null ? _buildPhotoPreview() : null,
    );
  }

  Widget _buildPhotoCaptureContent() {
    if (_photoTaken) {
      final title = _photoUnavailable
          ? 'Photo non disponible'
          : _photoDeferredToWebCamera
              ? 'Badge reconnu'
              : 'Photo prise';
      final subtitle = _photoUnavailable
          ? 'Le pointage continue sans photo.'
          : _photoDeferredToWebCamera
              ? 'Ouverture de la caméra de contrôle…'
              : 'La photo de contrôle est prête.';
      return _phaseCard(
        icon: _photoUnavailable ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
        title: title,
        subtitle: subtitle,
      );
    }

    if (!_isCameraReady) {
      return _phaseCard(
        icon: Icons.camera_alt_outlined,
        title: 'Badge reconnu',
        subtitle: 'Préparation de la caméra de contrôle…',
        showLoader: true,
      );
    }

    return Container(
      width: math
          .min(340.0, MediaQuery.sizeOf(context).width - 40)
          .toDouble(),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF233A37).withOpacity(0.97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF71877F).withOpacity(0.62)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('😊', style: TextStyle(fontSize: 42)),
          const SizedBox(height: 10),
          const Text(
            'Un petit sourire',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFF2E7D4),
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'et c’est tout !',
            textAlign: TextAlign.center,
            style: TextStyle(color: EnCheckColors.orDoux, fontSize: 15),
          ),
          const SizedBox(height: 18),
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 66,
              height: 66,
              decoration: const BoxDecoration(
                color: Color(0xFF233A37),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Color(0xFFF2E7D4),
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseCard({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showLoader = false,
  }) {
    return Container(
      width: math
          .min(320.0, MediaQuery.sizeOf(context).width - 48)
          .toDouble(),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF233A37).withOpacity(0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF71877F).withOpacity(0.62)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLoader)
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: EnCheckColors.orDoux,
              ),
            )
          else
            Icon(icon, color: EnCheckColors.orDoux, size: 38),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF2E7D4),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD7D0C5),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPreview() {
    return Positioned(
      top: 88,
      right: 24,
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

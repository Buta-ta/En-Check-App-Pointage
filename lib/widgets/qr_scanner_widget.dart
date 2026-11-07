// ═══════════════════════════════════════════════════════════
// 📷 LECTEUR QR — habillage conforme à la maquette mobile choisie
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'qr_scanner_chrome.dart';

class QRScannerWidget extends StatefulWidget {
  final Function(String) onScanned;
  final VoidCallback onClose;
  final VoidCallback? onPinFallback;
  final bool forceFrontCamera;
  final bool showSwitchButton;

  const QRScannerWidget({
    super.key,
    required this.onScanned,
    required this.onClose,
    this.onPinFallback,
    this.forceFrontCamera = false,
    this.showSwitchButton = true,
  });

  @override
  State<QRScannerWidget> createState() => _QRScannerWidgetState();
}

class _QRScannerWidgetState extends State<QRScannerWidget> {
  late final MobileScannerController cameraController;
  bool _hasScanned = false;
  bool _isFrontCamera = false;
  MobileScannerErrorCode? _cameraError;
  MobileScannerErrorCode? _queuedCameraError;

  @override
  void initState() {
    super.initState();
    _isFrontCamera = widget.forceFrontCamera;
    cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: _isFrontCamera ? CameraFacing.front : CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.isEmpty) continue;

      setState(() => _hasScanned = true);
      widget.onScanned(code);
      return;
    }
  }

  Future<void> _switchCamera() async {
    try {
      await cameraController.switchCamera();
      if (mounted) setState(() => _isFrontCamera = !_isFrontCamera);
    } catch (_) {
      // Le bouton reste sans effet si le navigateur/appareil ne peut pas
      // changer d'objectif ; l'écran de scan lui-même reste utilisable.
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await cameraController.toggleTorch();
    } catch (_) {
      // Certains appareils exposent l'icône mais ne permettent pas la lampe.
    }
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

  Future<void> _retryCamera() async {
    setState(() => _cameraError = null);
    try {
      await cameraController.start();
    } catch (_) {
      // MobileScanner signalera l'erreur à nouveau via errorBuilder.
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
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: cameraController,
      builder: (context, state, _) {
        return QrScannerChrome(
          cameraPreview: MobileScanner(
            controller: cameraController,
            onDetect: _onDetect,
            errorBuilder: (context, exception, child) {
              _queueCameraError(exception);
              return const ColoredBox(color: Color(0xFF292824));
            },
          ),
          onClose: widget.onClose,
          onPinFallback: widget.onPinFallback,
          instruction: _isFrontCamera
              ? 'Montrez le QR code face à l’écran'
              : 'Placez le QR code du badge dans le cadre',
          statusLabel: _hasScanned
              ? 'QR détecté — vérification du badge…'
              : 'Recherche du QR code…',
          cameraLabel: _isFrontCamera ? 'Caméra frontale' : 'Caméra arrière',
          isFrontCamera: _isFrontCamera,
          showTorchButton: true,
          torchAvailable: state.torchState != TorchState.unavailable,
          torchEnabled: state.torchState == TorchState.on,
          showSwitchButton: widget.showSwitchButton,
          showViewfinder: !_hasScanned,
          isBusy: _hasScanned,
          onToggleTorch: _toggleTorch,
          onSwitchCamera: _switchCamera,
          cameraErrorTitle: _cameraErrorTitle,
          cameraErrorMessage: _cameraErrorMessage,
          onRetryCamera: _retryCamera,
        );
      },
    );
  }
}

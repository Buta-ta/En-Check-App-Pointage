// ═══════════════════════════════════════════════════════════
// 📷 WIDGET SCANNER QR CODE (AVEC SWITCH CAMÉRA)
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

class QRScannerWidget extends StatefulWidget {
  final Function(String) onScanned;
  final VoidCallback onClose;
  final bool forceFrontCamera; // Pour le mode QR + Photo
  final bool showSwitchButton; // Afficher le bouton switch ou non

  const QRScannerWidget({
    super.key,
    required this.onScanned,
    required this.onClose,
    this.forceFrontCamera = false,
    this.showSwitchButton = true,
  });

  @override
  State<QRScannerWidget> createState() => _QRScannerWidgetState();
}

class _QRScannerWidgetState extends State<QRScannerWidget> {
  late MobileScannerController cameraController;
  bool _hasScanned = false;
  bool _isFrontCamera = false;

  @override
  void initState() {
    super.initState();
    _isFrontCamera = widget.forceFrontCamera;
    _initController();
  }

  void _initController() {
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

  // ═══════════════════════════════════════════════════════════
  // 🔄 SWITCH CAMÉRA
  // ═══════════════════════════════════════════════════════════

  Future<void> _switchCamera() async {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    await cameraController.switchCamera();
  }

  // ═══════════════════════════════════════════════════════════
  // 📸 DÉTECTION QR CODE
  // ═══════════════════════════════════════════════════════════

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;

    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;

      if (code != null && code.isNotEmpty) {
        setState(() {
          _hasScanned = true;
        });

        widget.onScanned(code);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ═══════════════════════════════════════════
          // 📷 VUE CAMÉRA
          // ═══════════════════════════════════════════
          MobileScanner(controller: cameraController, onDetect: _onDetect),

          // ═══════════════════════════════════════════
          // 🎯 OVERLAY AVEC CADRE DE SCAN
          // ═══════════════════════════════════════════
          Container(
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5)),
            child: Stack(
              children: [
                // Zone centrale transparente (cadre de scan)
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

                // Coins décoratifs
                Center(
                  child: SizedBox(
                    width: 280,
                    height: 280,
                    child: CustomPaint(painter: CornersPainter()),
                  ),
                ),
              ],
            ),
          ),

          // ═══════════════════════════════════════════
          // 🔝 HEADER
          // ═══════════════════════════════════════════
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Bouton Fermer
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 24),
                    ),
                  ),

                  // Titre
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Scanner le Badge',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  // Boutons droite (Flash + Switch)
                  Row(
                    children: [
                      // Bouton Flash (caché si caméra frontale)
                      if (!_isFrontCamera)
                        GestureDetector(
                          onTap: () => cameraController.toggleTorch(),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ValueListenableBuilder(
                              valueListenable: cameraController,
                              builder: (context, state, child) {
                                return Icon(
                                  state.torchState == TorchState.on
                                      ? Icons.flash_on
                                      : Icons.flash_off,
                                  color: state.torchState == TorchState.on
                                      ? EnCheckColors.orDoux
                                      : Colors.white,
                                  size: 24,
                                );
                              },
                            ),
                          ),
                        ),

                      // Espacement
                      if (!_isFrontCamera && widget.showSwitchButton)
                        const SizedBox(width: 10),

                      // Bouton Switch Caméra
                      if (widget.showSwitchButton)
                        GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _isFrontCamera
                                  ? Icons.camera_rear
                                  : Icons.camera_front,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ═══════════════════════════════════════════
          // 📝 INSTRUCTIONS EN BAS
          // ═══════════════════════════════════════════
          Positioned(
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
                  child: Text(
                    _isFrontCamera
                        ? 'Montrez le QR Code face à l\'écran'
                        : 'Placez le QR Code du badge dans le cadre',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 20),
                // Animation de scan
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
          ),

          // ═══════════════════════════════════════════
          // 📷 INDICATEUR CAMÉRA ACTIVE
          // ═══════════════════════════════════════════
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: EnCheckColors.terreChaude.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isFrontCamera ? 'Caméra frontale' : 'Caméra arrière',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 🎨 PAINTER POUR LES COINS DÉCORATIFS
// ═══════════════════════════════════════════════════════════
class CornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EnCheckColors.orDoux
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 20.0;

    // Coin supérieur gauche
    canvas.drawLine(const Offset(0, cornerLength), const Offset(0, radius), paint);
    canvas.drawArc(
      const Rect.fromLTWH(0, 0, radius * 2, radius * 2),
      3.14,
      0.5,
      false,
      paint,
    );
    canvas.drawLine(const Offset(radius, 0), const Offset(cornerLength, 0), paint);

    // Coin supérieur droit
    canvas.drawLine(
      Offset(size.width - cornerLength, 0),
      Offset(size.width - radius, 0),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(size.width - radius * 2, 0, radius * 2, radius * 2),
      -0.5,
      0.5,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(size.width, radius),
      Offset(size.width, cornerLength),
      paint,
    );

    // Coin inférieur droit
    canvas.drawLine(
      Offset(size.width, size.height - cornerLength),
      Offset(size.width, size.height - radius),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width - radius * 2,
        size.height - radius * 2,
        radius * 2,
        radius * 2,
      ),
      0,
      0.5,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(size.width - radius, size.height),
      Offset(size.width - cornerLength, size.height),
      paint,
    );

    // Coin inférieur gauche
    canvas.drawLine(
      Offset(cornerLength, size.height),
      Offset(radius, size.height),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(0, size.height - radius * 2, radius * 2, radius * 2),
      0.5,
      0.5,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height - radius),
      Offset(0, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Habillage partagé des écrans de lecture QR : caméra, viseur, contrôles
/// et états de lecture suivent la maquette mobile choisie.
class QrScannerChrome extends StatelessWidget {
  final Widget cameraPreview;
  final VoidCallback onClose;
  final String headerTitle;
  final String instruction;
  final String statusLabel;
  final String cameraLabel;
  final bool isFrontCamera;
  final bool showTorchButton;
  final bool torchAvailable;
  final bool torchEnabled;
  final bool showSwitchButton;
  final bool showViewfinder;
  final bool isBusy;
  final VoidCallback? onToggleTorch;
  final VoidCallback? onSwitchCamera;
  final VoidCallback? onPinFallback;
  final String pinFallbackLabel;
  final String? cameraErrorTitle;
  final String? cameraErrorMessage;
  final VoidCallback? onRetryCamera;
  final Widget? centerContent;
  final Widget? foregroundOverlay;

  const QrScannerChrome({
    super.key,
    required this.cameraPreview,
    required this.onClose,
    this.headerTitle = 'Scanner le badge',
    required this.instruction,
    required this.statusLabel,
    required this.cameraLabel,
    this.isFrontCamera = false,
    this.showTorchButton = true,
    this.torchAvailable = false,
    this.torchEnabled = false,
    this.showSwitchButton = true,
    this.showViewfinder = true,
    this.isBusy = false,
    this.onToggleTorch,
    this.onSwitchCamera,
    this.onPinFallback,
    this.pinFallbackLabel = 'Utiliser le code PIN',
    this.cameraErrorTitle,
    this.cameraErrorMessage,
    this.onRetryCamera,
    this.centerContent,
    this.foregroundOverlay,
  });

  bool get _hasCameraError => cameraErrorTitle != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF292824),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final frameSide = math.min(
            480.0,
            math.min(constraints.maxWidth * 0.68, constraints.maxHeight * 0.41),
          ).toDouble();

          return Stack(
            fit: StackFit.expand,
            children: [
              cameraPreview,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScannerScrimPainter(
                      frameSide: frameSide,
                      showViewfinder: showViewfinder && !_hasCameraError,
                    ),
                  ),
                ),
              ),
              if (_hasCameraError)
                Center(
                  child: _CameraErrorCard(
                    title: cameraErrorTitle!,
                    message: cameraErrorMessage ??
                        'Vérifiez la caméra puis réessayez.',
                    onRetry: onRetryCamera,
                  ),
                )
              else if (centerContent != null)
                Center(child: centerContent!)
              else if (showViewfinder)
                Center(
                  child: SizedBox.square(
                    dimension: frameSide,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.035),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CustomPaint(
                        painter: _ScannerCornersPainter(),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(context),
                    const Spacer(),
                    _buildFooter(context),
                  ],
                ),
              ),
              if (foregroundOverlay != null) foregroundOverlay!,
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final showTorch = showTorchButton && !isFrontCamera;
    final controlSize = MediaQuery.sizeOf(context).width < 380 ? 48.0 : 56.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _controlButton(
            context,
            icon: Icons.close_rounded,
            label: 'Fermer le lecteur QR',
            onPressed: isBusy ? null : onClose,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              headerTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFF2E7D4),
                fontSize: controlSize < 56 ? 16 : 19,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showTorch)
                _controlButton(
                  context,
                  icon: torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  label: torchAvailable ? 'Activer ou désactiver la lampe' : 'Lampe indisponible',
                  onPressed: torchAvailable ? onToggleTorch : null,
                  active: torchEnabled,
                ),
              if (showTorch && showSwitchButton) const SizedBox(width: 8),
              if (showSwitchButton)
                _controlButton(
                  context,
                  icon: Icons.cameraswitch_rounded,
                  label: 'Changer de caméra',
                  onPressed: isBusy ? null : onSwitchCamera,
                ),
              if (!showTorch && !showSwitchButton)
                SizedBox(width: controlSize),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 600;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, compact ? 12 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 560),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: compact ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF233A37).withOpacity(0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF71877F).withOpacity(0.55)),
            ),
            child: Text(
              instruction,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFF1E6D3),
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_hasCameraError) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF78A39A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                ] else ...[
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFFE2BE83),
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    _hasCameraError ? 'Scan suspendu' : statusLabel,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _hasCameraError
                          ? const Color(0xFFFFDDA9)
                          : const Color(0xFFE7DFD2),
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showViewfinder && !_hasCameraError) ...[
            const SizedBox(height: 12),
            const _ScanProgressDots(),
          ],
          if (cameraErrorMessage != null && _hasCameraError) ...[
            const SizedBox(height: 4),
            Text(
              cameraErrorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD7D0C5),
                fontSize: 11.5,
                height: 1.25,
              ),
            ),
          ],
          if (onPinFallback != null && !isBusy) ...[
            SizedBox(height: compact ? 4 : 8),
            TextButton.icon(
              onPressed: onPinFallback,
              icon: const Icon(Icons.pin_outlined, size: 17),
              label: Text(pinFallbackLabel),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF1E6D3),
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
          SizedBox(height: compact ? 2 : 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF233A37).withOpacity(0.88),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF71877F).withOpacity(0.48)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isFrontCamera ? Icons.camera_front_rounded : Icons.camera_rear_rounded,
                  color: const Color(0xFFEEDFC7),
                  size: 18,
                ),
                const SizedBox(width: 9),
                Text(
                  cameraLabel,
                  style: const TextStyle(
                    color: Color(0xFFEEDFC7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    final controlSize = MediaQuery.sizeOf(context).width < 380 ? 48.0 : 56.0;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: const Color(0xFF203633).withOpacity(onPressed == null ? 0.68 : 0.94),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: const Color(0xFF748A82).withOpacity(0.56),
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: controlSize,
              height: controlSize,
              child: Icon(
                icon,
                color: active
                    ? EnCheckColors.orDoux
                    : onPressed == null
                        ? const Color(0xFF9C9B94)
                        : const Color(0xFFF2E7D4),
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanProgressDots extends StatelessWidget {
  const _ScanProgressDots();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Lecture QR en cours',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 3; index++) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: index == 2
                      ? EnCheckColors.orDoux.withOpacity(0.82)
                      : const Color(0xFF78A39A).withOpacity(0.86),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            const SizedBox(width: 2),
            Container(
              width: 30,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraErrorCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _CameraErrorCard({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final side = math
        .min(320.0, MediaQuery.sizeOf(context).width - 48)
        .toDouble();
    return Container(
      width: side,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF242D2A).withOpacity(0.98),
        borderRadius: BorderRadius.circular(22),
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
          const Icon(Icons.camera_alt_outlined, color: EnCheckColors.orDoux, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF2E7D4),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD7D0C5),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF2E7D4),
                side: const BorderSide(color: Color(0xFF71877F)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScannerScrimPainter extends CustomPainter {
  final double frameSide;
  final bool showViewfinder;

  const _ScannerScrimPainter({
    required this.frameSide,
    required this.showViewfinder,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    if (showViewfinder && frameSide > 0) {
      final frameRect = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: frameSide,
        height: frameSide,
      );
      final hole = Path()
        ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(8)));
      final scrim = Path.combine(PathOperation.difference, outer, hole);
      canvas.drawPath(
        scrim,
        Paint()..color = const Color(0xB3242421),
      );
    } else {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xB3242421),
      );
    }
  }

  @override
  bool shouldRepaint(_ScannerScrimPainter oldDelegate) =>
      oldDelegate.frameSide != frameSide ||
      oldDelegate.showViewfinder != showViewfinder;
}

class _ScannerCornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EnCheckColors.orDoux
      ..strokeWidth = math.max(4.0, size.width * 0.014).toDouble()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final length = math.min(72.0, size.width * 0.17).toDouble();
    const inset = 2.0;
    canvas.drawLine(Offset(inset, length), Offset(inset, inset), paint);
    canvas.drawLine(Offset(inset, inset), Offset(length, inset), paint);
    canvas.drawLine(Offset(size.width - length, inset), Offset(size.width - inset, inset), paint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, length), paint);
    canvas.drawLine(Offset(inset, size.height - length), Offset(inset, size.height - inset), paint);
    canvas.drawLine(Offset(inset, size.height - inset), Offset(length, size.height - inset), paint);
    canvas.drawLine(Offset(size.width - length, size.height - inset), Offset(size.width - inset, size.height - inset), paint);
    canvas.drawLine(Offset(size.width - inset, size.height - length), Offset(size.width - inset, size.height - inset), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

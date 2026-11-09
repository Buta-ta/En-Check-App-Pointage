import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Splash Flutter léger : un seul mouvement, sans dépendance ni attente imposée.
class EcranDemarrage extends StatefulWidget {
  const EcranDemarrage({super.key, this.chargementLong = false});

  final bool chargementLong;

  @override
  State<EcranDemarrage> createState() => _EcranDemarrageState();
}

class _EcranDemarrageState extends State<EcranDemarrage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF121312) : const Color(0xFFF5F2E9);
    final ink = dark ? const Color(0xFFEEEBE4) : const Color(0xFF1D1C1B);
    final accent = const Color(0xFF3A686D);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 360 || constraints.maxHeight < 560;
            final logoSize = math.min(compact ? 112.0 : 138.0,
                constraints.maxWidth * .38).toDouble();
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = reduceMotion ? 1.0 : _controller.value;
                final meet = Curves.easeInOutCubic.transform(
                    ((t - .08) / .55).clamp(0.0, 1.0).toDouble());
                final reveal = reduceMotion
                    ? 1.0
                    : Curves.easeOutCubic.transform(((t - .66) / .34).clamp(0.0, 1.0).toDouble());
                final handsOpacity = reduceMotion
                    ? 0.0
                    : (1 - Curves.easeIn.transform(((t - .72) / .24).clamp(0.0, 1.0).toDouble()));
                final contact = reduceMotion ? 0.0 : ((t - .56) / .12).clamp(0.0, 1.0).toDouble();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: math.min(310.0, constraints.maxWidth - 32).toDouble(),
                      height: compact ? 155 : 188,
                      child: Stack(alignment: Alignment.center, children: [
                        if (contact > 0 && contact < 1)
                          Container(
                            width: 44 + 50 * contact,
                            height: 44 + 50 * contact,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: accent.withOpacity((1-contact)*.46), width: 2),
                            ),
                          ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _HighFivePainter(
                              progress: meet,
                              opacity: handsOpacity,
                              color: dark ? const Color(0xFFD6C8A8) : const Color(0xFF806A4F),
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: reveal,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - reveal)),
                            child: Container(
                              width: logoSize,
                              height: logoSize,
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: dark ? const Color(0xFF1D1E1C) : Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                  color: accent.withOpacity(dark ? .2 : .12),
                                  blurRadius: 30,
                                  spreadRadius: 2,
                                )],
                              ),
                              child: Image.asset('assets/logo_encheck.png', fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Opacity(
                      opacity: reveal,
                      child: Transform.translate(
                        offset: Offset(0, 7 * (1 - reveal)),
                        child: Text('En-Check', style: TextStyle(
                          color: ink, fontSize: compact ? 26 : 30,
                          fontWeight: FontWeight.w700, letterSpacing: -.7,
                        )),
                      ),
                    ),
                    SizedBox(height: compact ? 11 : 16),
                    AnimatedOpacity(
                      opacity: widget.chargementLong ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Text('Chargement…', style: TextStyle(
                        color: ink.withOpacity(.62), fontSize: 14,
                      )),
                    ),
                  ],
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

/// Deux silhouettes stylisées en tracés vectoriels, dessinées dans l'espace local.
class _HighFivePainter extends CustomPainter {
  const _HighFivePainter({required this.progress, required this.opacity, required this.color});
  final double progress;
  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final p = Curves.easeInOutCubic.transform(progress);
    final center = size.width / 2;
    final y = size.height * .49;
    final reach = size.width * .187 * p;
    final squeeze = progress > .88 ? 1 - .035 * ((progress - .88) / .12) : 1.0;
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13 * (size.width / 310).clamp(.78, 1.1).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(center, y);
    canvas.scale(squeeze, squeeze);
    final left = Path()
      ..moveTo(-size.width * .53 + reach * .28, 35)
      ..cubicTo(-size.width * .39, 31, -size.width * .31, 12, -reach - 10, 1)
      ..cubicTo(-reach - 5, -5, -reach + 2, -18, -reach + 7, -31)
      ..lineTo(-reach + 9, -49)
      ..cubicTo(-reach + 10, -57, -reach + 22, -57, -reach + 22, -48)
      ..lineTo(-reach + 23, -35)
      ..lineTo(-reach + 29, -50)
      ..cubicTo(-reach + 32, -58, -reach + 44, -55, -reach + 42, -46)
      ..lineTo(-reach + 39, -31)
      ..lineTo(-reach + 49, -43)
      ..cubicTo(-reach + 54, -49, -reach + 64, -43, -reach + 58, -35)
      ..lineTo(-reach + 44, -17)
      ..cubicTo(-reach + 31, -4, -reach + 25, 7, -reach + 27, 17)
      ..lineTo(-size.width * .20, 42);
    final right = Path()
      ..moveTo(size.width * .53 - reach * .28, 35)
      ..cubicTo(size.width * .39, 31, size.width * .31, 12, reach + 10, 1)
      ..cubicTo(reach + 5, -5, reach - 2, -18, reach - 7, -31)
      ..lineTo(reach - 9, -49)
      ..cubicTo(reach - 10, -57, reach - 22, -57, reach - 22, -48)
      ..lineTo(reach - 23, -35)
      ..lineTo(reach - 29, -50)
      ..cubicTo(reach - 32, -58, reach - 44, -55, reach - 42, -46)
      ..lineTo(reach - 39, -31)
      ..lineTo(reach - 49, -43)
      ..cubicTo(reach - 54, -49, reach - 64, -43, reach - 58, -35)
      ..lineTo(reach - 44, -17)
      ..cubicTo(reach - 31, -4, reach - 25, 7, reach - 27, 17)
      ..lineTo(size.width * .20, 42);
    final depart = size.width * .34 * (1 - p);
    canvas.save();
    canvas.translate(-depart, 0);
    canvas.drawPath(left, paint);
    canvas.restore();
    canvas.save();
    canvas.translate(depart, 0);
    canvas.drawPath(right, paint);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HighFivePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.opacity != opacity || oldDelegate.color != color;
}

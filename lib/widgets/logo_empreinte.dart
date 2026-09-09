import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LogoEmpreinte extends StatelessWidget {
  final double taille;

  const LogoEmpreinte({super.key, this.taille = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(colors: [EnCheckColors.sableDore, EnCheckColors.sableClair]),
        boxShadow: [
          BoxShadow(
            color: EnCheckColors.terreChaude.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: CustomPaint(size: Size(taille, taille), painter: EmpreintePiedPainter()),
    );
  }
}

class EmpreintePiedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = EnCheckColors.brunProfond.withOpacity(0.8)
          ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scale = size.width / 100;

    // ═══════════════════════════════════════════
    // 🦶 PLANTE DU PIED COMPLÈTE
    // ═══════════════════════════════════════════
    final plantePath = Path();

    // Départ : haut gauche (sous le gros orteil)
    plantePath.moveTo(centerX - 20 * scale, centerY - 5 * scale);

    // Coussin sous le gros orteil (bosse)
    plantePath.quadraticBezierTo(
      centerX - 22 * scale,
      centerY + 5 * scale,
      centerX - 18 * scale,
      centerY + 12 * scale,
    );

    // Voûte plantaire (creux intérieur) - LA PARTIE IMPORTANTE
    plantePath.quadraticBezierTo(
      centerX - 8 * scale,
      centerY + 18 * scale,
      centerX - 10 * scale,
      centerY + 30 * scale,
    );

    // Vers le talon (côté intérieur)
    plantePath.quadraticBezierTo(
      centerX - 12 * scale,
      centerY + 38 * scale,
      centerX - 8 * scale,
      centerY + 42 * scale,
    );

    // Bas du talon
    plantePath.quadraticBezierTo(
      centerX,
      centerY + 46 * scale,
      centerX + 8 * scale,
      centerY + 42 * scale,
    );

    // Talon côté extérieur
    plantePath.quadraticBezierTo(
      centerX + 12 * scale,
      centerY + 38 * scale,
      centerX + 14 * scale,
      centerY + 30 * scale,
    );

    // Côté extérieur du pied (plus droit, pas de voûte)
    plantePath.quadraticBezierTo(
      centerX + 18 * scale,
      centerY + 20 * scale,
      centerX + 22 * scale,
      centerY + 10 * scale,
    );

    // Coussin côté extérieur (sous le petit orteil)
    plantePath.quadraticBezierTo(
      centerX + 24 * scale,
      centerY + 2 * scale,
      centerX + 20 * scale,
      centerY - 5 * scale,
    );

    // Haut de la plante (sous les orteils)
    plantePath.quadraticBezierTo(
      centerX + 10 * scale,
      centerY - 2 * scale,
      centerX,
      centerY + 2 * scale,
    );

    plantePath.quadraticBezierTo(
      centerX - 10 * scale,
      centerY + 2 * scale,
      centerX - 20 * scale,
      centerY - 5 * scale,
    );

    plantePath.close();
    canvas.drawPath(plantePath, paint);

    // ═══════════════════════════════════════════
    // 👆 GROS ORTEIL
    // ═══════════════════════════════════════════
    final grosOrteilPath = Path();
    grosOrteilPath.addOval(
      Rect.fromCenter(
        center: Offset(centerX - 15 * scale, centerY - 18 * scale),
        width: 16 * scale,
        height: 22 * scale,
      ),
    );
    canvas.drawPath(grosOrteilPath, paint);

    // ═══════════════════════════════════════════
    // 👆 DEUXIÈME ORTEIL
    // ═══════════════════════════════════════════
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 2 * scale, centerY - 22 * scale),
        width: 12 * scale,
        height: 18 * scale,
      ),
      paint,
    );

    // ═══════════════════════════════════════════
    // 👆 TROISIÈME ORTEIL
    // ═══════════════════════════════════════════
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 10 * scale, centerY - 20 * scale),
        width: 11 * scale,
        height: 16 * scale,
      ),
      paint,
    );

    // ═══════════════════════════════════════════
    // 👆 QUATRIÈME ORTEIL
    // ═══════════════════════════════════════════
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 20 * scale, centerY - 16 * scale),
        width: 10 * scale,
        height: 14 * scale,
      ),
      paint,
    );

    // ═══════════════════════════════════════════
    // 👆 PETIT ORTEIL
    // ═══════════════════════════════════════════
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 28 * scale, centerY - 10 * scale),
        width: 9 * scale,
        height: 12 * scale,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// 🎨 BANDES DÉCORATIVES « MOTIFS AFRICAINS »
// ═══════════════════════════════════════════════════════════════════════════
//
// Inspirées des grandes traditions textiles africaines, comme dans l'app
// En-Check Admin :
//
//   • ADINKRA (Ghana)      — symboles estampés sur indigo. Ici, l'univers
//                            « pointage / temps » : le rythme de la journée.
//   • PERLES ZOULOU (Afrique du Sud) — losanges et triangles perlés.
//                            Ici, l'univers « personnes » (carte matricule).
//   • LÉSOTHO (Lesotho)    — la couverture basotho : repos, chaleur.
//                            Ici, le bloc PAUSE.
//
// Ces motifs sont DESSINÉS EN VECTEURS (CustomPaint) : nets à toute taille,
// légers, et faciles à remplacer plus tard par les illustrations officielles
// de l'équipe artistique.
//
// RÈGLE D'OR : une bande est un ACCENT (frise, en-tête, séparateur).
// Jamais de motif en arrière-plan d'un texte important : sur une tablette de
// pointage, la lisibilité passe avant tout.
//
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';

enum MotifAfricain { adinkra, zoulou, lesotho }

class BandeMotif extends StatelessWidget {
  final MotifAfricain motif;
  final double height;
  final BorderRadius? radius;

  const BandeMotif.adinkra({super.key, this.height = 40, this.radius})
      : motif = MotifAfricain.adinkra;

  const BandeMotif.zoulou({super.key, this.height = 40, this.radius})
      : motif = MotifAfricain.zoulou;

  const BandeMotif.lesotho({super.key, this.height = 40, this.radius})
      : motif = MotifAfricain.lesotho;

  @override
  Widget build(BuildContext context) {
    final bande = CustomPaint(
      size: Size(double.infinity, height),
      painter: _PeintreMotif(motif),
    );
    if (radius == null) return bande;
    return ClipRRect(borderRadius: radius!, child: bande);
  }
}

// ─── Palette des motifs ─────────────────────────────────────────────────────

class _MotifCouleurs {
  // Adinkra (étoffe indigo estampée)
  static const Color adinkraFond = Color(0xFF1B2A4A);
  static const Color adinkraCreme = Color(0xFFF2E8D8);
  static const Color adinkraTerre = Color(0xFFB5673F);

  // Perles zoulou
  static const Color zoulouFond = Color(0xFF2B1B12);
  static const Color zoulouTurquoise = Color(0xFF2FA8B8);
  static const Color zoulouEmeraude = Color(0xFF2E7D5B);
  static const Color zoulouCreme = Color(0xFFF2E8D8);
  static const Color zoulouOr = Color(0xFFD4AF37);
  static const Color zoulouTerre = Color(0xFFC2703D);

  // Couvertures basotho (Lesotho)
  static const Color lesothoCreme = Color(0xFFF4EDE0);
  static const Color lesothoMarine = Color(0xFF1E3A5F);
  static const Color lesothoTerre = Color(0xFFC86B45);
}

class _PeintreMotif extends CustomPainter {
  final MotifAfricain motif;

  _PeintreMotif(this.motif);

  @override
  void paint(Canvas canvas, Size size) {
    switch (motif) {
      case MotifAfricain.adinkra:
        _peindreAdinkra(canvas, size);
        break;
      case MotifAfricain.zoulou:
        _peindreZoulou(canvas, size);
        break;
      case MotifAfricain.lesotho:
        _peindreLesotho(canvas, size);
        break;
    }
  }

  @override
  bool shouldRepaint(_PeintreMotif ancien) => ancien.motif != motif;

  // ── Utilitaires ───────────────────────────────────────────────────────────

  Paint _plein(Color c) => Paint()..color = c;

  Paint _trait(Color c, double epaisseur) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = epaisseur;

  // ── ADINKRA : frise de symboles estampés sur indigo ───────────────────────

  void _peindreAdinkra(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _plein(_MotifCouleurs.adinkraFond));

    // Liserés haut et bas (bords de l'étoffe)
    canvas.drawRect(
        Rect.fromLTWH(0, h * 0.08, size.width, math.max(1.5, h * 0.05)),
        _plein(_MotifCouleurs.adinkraCreme));
    canvas.drawRect(
        Rect.fromLTWH(0, h * 0.87, size.width, math.max(1.5, h * 0.05)),
        _plein(_MotifCouleurs.adinkraTerre));

    final cy = h * 0.5;
    final s = math.min(h * 0.42, 26.0);
    final pas = s * 4.2;
    var i = 0;
    for (double x = s; x < size.width + pas; x += pas) {
      final creme = i.isEven;
      final teinte = creme
          ? _MotifCouleurs.adinkraCreme
          : _MotifCouleurs.adinkraTerre;
      _symboleAnneau(canvas, Offset(x, cy), s, teinte);
      _symboleQuatreFolio(canvas, Offset(x + pas * 0.25, cy), s, teinte);
      _symboleLosangeX(canvas, Offset(x + pas * 0.5, cy), s, teinte);
      _symboleBarres(canvas, Offset(x + pas * 0.75, cy), s, teinte);
      i++;
    }
  }

  void _symboleAnneau(Canvas canvas, Offset c, double s, Color teinte) {
    canvas.drawCircle(c, s * 0.5, _trait(teinte, math.max(1.6, s * 0.12)));
    canvas.drawCircle(c, s * 0.16, _plein(teinte));
  }

  void _symboleQuatreFolio(Canvas canvas, Offset c, double s, Color teinte) {
    final r = s * 0.22;
    for (final d in const [
      Offset(0, -1),
      Offset(0, 1),
      Offset(-1, 0),
      Offset(1, 0)
    ]) {
      canvas.drawCircle(c + d * (s * 0.34), r, _plein(teinte));
    }
    canvas.drawCircle(c, s * 0.16, _plein(teinte));
  }

  void _symboleLosangeX(Canvas canvas, Offset c, double s, Color teinte) {
    final demi = s * 0.52;
    final losange = Path()
      ..moveTo(c.dx, c.dy - demi)
      ..lineTo(c.dx + demi, c.dy)
      ..lineTo(c.dx, c.dy + demi)
      ..lineTo(c.dx - demi, c.dy)
      ..close();
    canvas.drawPath(losange, _trait(teinte, math.max(1.6, s * 0.11)));
    canvas.drawLine(Offset(c.dx - demi * 0.55, c.dy - demi * 0.55),
        Offset(c.dx + demi * 0.55, c.dy + demi * 0.55), _trait(teinte, 1.6));
    canvas.drawLine(Offset(c.dx + demi * 0.55, c.dy - demi * 0.55),
        Offset(c.dx - demi * 0.55, c.dy + demi * 0.55), _trait(teinte, 1.6));
  }

  void _symboleBarres(Canvas canvas, Offset c, double s, Color teinte) {
    final hauteur = s * 0.95;
    final ep = math.max(1.6, s * 0.11);
    for (var k = -2; k <= 2; k++) {
      final x = c.dx + k * s * 0.24;
      canvas.drawLine(Offset(x, c.dy - hauteur / 2),
          Offset(x, c.dy + hauteur / 2), _trait(teinte, ep));
    }
  }

  // ── PERLES ZOULOU : losanges imbriqués + triangles perlés ────────────────

  void _peindreZoulou(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _plein(_MotifCouleurs.zoulouFond));

    // Filets d'or en haut et en bas (monture de la perlerie)
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, math.max(1.2, h * 0.06)),
        _plein(_MotifCouleurs.zoulouOr));
    canvas.drawRect(
        Rect.fromLTWH(0, h * 0.94, size.width, math.max(1.2, h * 0.06)),
        _plein(_MotifCouleurs.zoulouOr));

    final cy = h * 0.5;
    final s = h * 0.62;
    final pas = s * 2.1;
    for (double x = s * 0.5; x < size.width + pas; x += pas) {
      _losangeImbrique(canvas, Offset(x, cy), s);
      _trianglesPerles(canvas, Offset(x + pas * 0.5, cy), s * 0.8);
    }
  }

  void _losangeImbrique(Canvas canvas, Offset c, double s) {
    const teintes = [
      _MotifCouleurs.zoulouTurquoise,
      _MotifCouleurs.zoulouCreme,
      _MotifCouleurs.zoulouEmeraude,
      _MotifCouleurs.zoulouOr,
      _MotifCouleurs.zoulouTerre,
    ];
    for (var k = 0; k < teintes.length; k++) {
      final cote = s * (1 - k * 0.185);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(math.pi / 4);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: cote, height: cote),
          _plein(teintes[k]));
      canvas.restore();
    }
  }

  void _trianglesPerles(Canvas canvas, Offset c, double s) {
    const teintes = [
      _MotifCouleurs.zoulouCreme,
      _MotifCouleurs.zoulouEmeraude,
      _MotifCouleurs.zoulouTurquoise,
    ];
    for (var k = 0; k < teintes.length; k++) {
      final demiLargeur = s * 0.5;
      final yBas = c.dy + s * 0.45 - k * s * 0.32;
      final yHaut = yBas - s * 0.38;
      final triangle = Path()
        ..moveTo(c.dx - demiLargeur, yBas)
        ..lineTo(c.dx, yHaut)
        ..lineTo(c.dx + demiLargeur, yBas)
        ..close();
      canvas.drawPath(triangle, _plein(teintes[k]));
    }
  }

  // ── LÉSOTHO : la couverture basotho (rayures + petits losanges) ──────────

  void _peindreLesotho(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _plein(_MotifCouleurs.lesothoCreme));

    // Rayures du tissu : bande marine haute, double filet terre, pied marine
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h * 0.22),
        _plein(_MotifCouleurs.lesothoMarine));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.26, size.width, h * 0.07),
        _plein(_MotifCouleurs.lesothoTerre));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.78, size.width, h * 0.08),
        _plein(_MotifCouleurs.lesothoTerre));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.90, size.width, h * 0.10),
        _plein(_MotifCouleurs.lesothoMarine));

    // Champ du milieu : losanges et chevrons semés
    final cy = h * 0.56;
    final s = h * 0.26;
    var i = 0;
    for (double x = s; x < size.width + s * 3; x += s * 3) {
      final teinte = i.isEven
          ? _MotifCouleurs.lesothoMarine
          : _MotifCouleurs.lesothoTerre;
      _petitLosange(canvas, Offset(x, cy), s, teinte);
      _chevron(canvas, Offset(x + s * 1.5, cy), s,
          i.isEven ? _MotifCouleurs.lesothoTerre : _MotifCouleurs.lesothoMarine);
      i++;
    }
  }

  void _petitLosange(Canvas canvas, Offset c, double s, Color teinte) {
    final losange = Path()
      ..moveTo(c.dx, c.dy - s)
      ..lineTo(c.dx + s * 0.8, c.dy)
      ..lineTo(c.dx, c.dy + s)
      ..lineTo(c.dx - s * 0.8, c.dy)
      ..close();
    canvas.drawPath(losange, _plein(teinte));
  }

  void _chevron(Canvas canvas, Offset c, double s, Color teinte) {
    final t = _trait(teinte, math.max(1.4, s * 0.28));
    canvas.drawLine(
        Offset(c.dx - s * 0.5, c.dy - s * 0.8), Offset(c.dx + s * 0.4, c.dy), t);
    canvas.drawLine(
        Offset(c.dx + s * 0.4, c.dy), Offset(c.dx - s * 0.5, c.dy + s * 0.8), t);
  }
}

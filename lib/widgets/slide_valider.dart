// lib/widgets/slide_valider.dart
// ═══════════════════════════════════════════════════════════
// 🔓 « GLISSER POUR VALIDER » — le bouton slide (style unlock)
// ═══════════════════════════════════════════════════════════
//
//  L'employé glisse le bouton doré de gauche à droite pour confirmer.
//  Fonctionne au doigt (tactile) ET à la souris (PWA sur ordinateur).
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SlideValider extends StatefulWidget {
  /// Renvoie true si l'action a réussi (le bouton se remet en place).
  final Future<bool> Function() onGlisse;
  final String label;

  const SlideValider({
    super.key,
    required this.onGlisse,
    this.label = 'Glisser pour valider',
  });

  @override
  State<SlideValider> createState() => _SlideValiderState();
}

class _SlideValiderState extends State<SlideValider> {
  static const double _tailleBouton = 48;

  double _position = 0;
  bool _enCours = false;
  bool _succes = false;

  Future<void> _finGlissement(double largeurUtile) async {
    if (_enCours) return;
    if (_position >= largeurUtile * 0.8) {
      setState(() {
        _position = largeurUtile;
        _enCours = true;
      });
      bool ok = false;
      try {
        ok = await widget.onGlisse();
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      if (ok) {
        setState(() => _succes = true);
        await Future.delayed(const Duration(milliseconds: 900));
      }
      if (!mounted) return;
      setState(() {
        _position = 0;
        _enCours = false;
        _succes = false;
      });
    } else {
      setState(() => _position = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeurUtile = constraints.maxWidth - _tailleBouton - 8;
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            if (_enCours || _succes) return;
            setState(() {
              _position =
                  (_position + details.delta.dx).clamp(0.0, largeurUtile);
            });
          },
          onHorizontalDragEnd: (_) => _finGlissement(largeurUtile),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: EnCheckColors.brunProfond,
              borderRadius: BorderRadius.circular(29),
              border: Border.all(
                color: EnCheckColors.orDoux.withOpacity(0.55),
                width: 1.2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Le libellé au centre (il s'efface sous le bouton glissé).
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _succes ? Icons.check_circle : Icons.lock_open,
                        size: 16,
                        color: EnCheckColors.orDoux,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _succes ? 'Enregistré' : widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: EnCheckColors.blanc,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Le bouton doré à glisser.
                AnimatedPositioned(
                  duration: Duration(milliseconds: _position == 0 ? 220 : 60),
                  curve: Curves.easeOut,
                  left: 4 + _position,
                  child: Container(
                    width: _tailleBouton,
                    height: _tailleBouton,
                    decoration: BoxDecoration(
                      color: _succes
                          ? EnCheckColors.succes
                          : EnCheckColors.orDoux,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _enCours
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: EnCheckColors.brunProfond,
                            ),
                          )
                        : Icon(
                            _succes ? Icons.check : Icons.arrow_forward,
                            color: EnCheckColors.brunProfond,
                            size: 24,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

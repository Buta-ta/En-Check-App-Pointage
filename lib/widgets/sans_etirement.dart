// lib/widgets/sans_etirement.dart
// ═══════════════════════════════════════════════════════════
// 📵 SANS ÉTIREMENT — désactive l'effet de sur-défilement Android
// ═══════════════════════════════════════════════════════════
//
//  Sur Android 12+ (Material 3), Flutter étire VERTICALEMENT tout le
//  contenu d'une zone qui défile quand le doigt tire au-delà d'un bord
//  (StretchingOverscrollIndicator). Quand la page tient sans défilement,
//  chaque geste est un dépassement de bord : toute la page se déforme
//  pendant le geste puis reprend sa forme.
//
//  Ce widget intercepte l'OverscrollIndicatorNotification et refuse
//  l'indication : la page et ses éléments ne s'étirent jamais pendant
//  les gestes de l'utilisateur (fiche « Affichage mobile »).
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class SansEtirement extends StatelessWidget {
  const SansEtirement({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        notification.disallowIndicator();
        return true;
      },
      child: child,
    );
  }
}

// lib/widgets/web_camera_widget_stub.dart
//
// Version NON-WEB de WebCameraWidget. La vraie caméra (dart:html /
// package:web) n'existe que dans le navigateur : si un écran Android la
// compilait, toute l'APK casserait. Ce double, lui, compile partout.
// Il ne devrait jamais s'afficher sur mobile (les écrans utilisent le
// plugin camera natif) — c'est un garde-fou de compilation.

import 'dart:typed_data';
import 'package:flutter/material.dart';

class WebCameraWidget extends StatelessWidget {
  final String employeeName;
  final Function(Uint8List? photoBytes) onPhotoTaken;
  final VoidCallback onCancel;
  final String raison;

  const WebCameraWidget({
    super.key,
    required this.employeeName,
    required this.onPhotoTaken,
    required this.onCancel,
    this.raison = 'pointage',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, size: 48),
          const SizedBox(height: 12),
          const Text('Caméra web non disponible sur cette plateforme.'),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onCancel,
            child: const Text('Retour'),
          ),
        ],
      ),
    );
  }
}

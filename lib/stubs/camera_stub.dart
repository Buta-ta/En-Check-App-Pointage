// lib/stubs/camera_stub.dart
// Stub caméra pour Flutter Web — NE REDÉFINIT PAS les types Flutter

import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:flutter/material.dart';

enum CameraLensDirection { front, back, external }
enum ResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }
enum ImageFormatGroup { jpeg, yuv420, bgra8888, nv21 }

class CameraDescription {
  final String name;
  final CameraLensDirection lensDirection;
  final int sensorOrientation;

  const CameraDescription({
    this.name = 'stub',
    this.lensDirection = CameraLensDirection.front,
    this.sensorOrientation = 0,
  });
}

class CameraValue {
  final bool isInitialized;
  final bool isStreamingImages;
  final Size? previewSize;

  const CameraValue({
    this.isInitialized = false,
    this.isStreamingImages = false,
    this.previewSize,
  });
}

class CameraController extends ValueNotifier<CameraValue> {
  CameraController(
      CameraDescription description,
      ResolutionPreset resolutionPreset, {
        bool enableAudio = true,
        ImageFormatGroup? imageFormatGroup,
      }) : super(const CameraValue());

  Future<void> initialize() async {
    value = const CameraValue(
      isInitialized: true,
      previewSize: Size(480, 640),
    );
  }

  Future<XFile> takePicture() async => XFile('');

  Future<void> startImageStream(Function(dynamic) onImage) async {}

  Future<void> stopImageStream() async {}

  @override
  Future<void> dispose() async {
    value = const CameraValue();
    super.dispose();
  }
}

class XFile {
  final String path;
  const XFile(this.path);
  Future<Uint8List> readAsBytes() async => Uint8List(0);
}

// Widget factice pour le preview — hérite bien de Widget
class CameraPreview extends StatelessWidget {
  final CameraController controller;
  const CameraPreview(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Caméra non disponible sur Web',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}

Future<List<CameraDescription>> availableCameras() async => [];
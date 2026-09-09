// lib/widgets/web_camera_widget.dart

import 'dart:async';
import 'dart:convert'; // ✅ AJOUTÉ pour base64Decode
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../theme/app_theme.dart';

class WebCameraWidget extends StatefulWidget {
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
  State<WebCameraWidget> createState() => _WebCameraWidgetState();
}

class _WebCameraWidgetState extends State<WebCameraWidget> {
  web.HTMLVideoElement? _videoElement;
  web.MediaStream? _mediaStream;

  bool _cameraReady = false;
  bool _permissionRefusee = false;
  bool _isCapturing = false;
  bool _photoTaken = false;
  Uint8List? _capturedPhoto;

  int _countdown = 3;
  Timer? _countdownTimer;

  static int _viewIdCounter = 0;
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'web-camera-${_viewIdCounter++}';
    _initialiserCamera();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _arreterCamera();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // 📷 INITIALISER getUserMedia
  // ═══════════════════════════════════════════════════════

  Future<void> _initialiserCamera() async {
    try {
      _videoElement = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = 'scaleX(-1)';

      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
            (int viewId) => _videoElement!,
      );

      final constraints = {
        'video': {
          'facingMode': 'user',
          'width': 640,
          'height': 480,
        },
        'audio': false,
      }.jsify()! as web.MediaStreamConstraints;

      _mediaStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

      _videoElement!.srcObject = _mediaStream;

      if (mounted) {
        setState(() => _cameraReady = true);
        await Future.delayed(const Duration(milliseconds: 800));
        _demarrerCountdown();
      }
    } catch (e) {
      print('❌ Erreur accès caméra web: $e');
      if (mounted) {
        setState(() => _permissionRefusee = true);
      }
    }
  }

  void _arreterCamera() {
    if (_mediaStream != null) {
      final tracks = _mediaStream!.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
      _mediaStream = null;
    }
    _videoElement = null;
  }

  // ═══════════════════════════════════════════════════════
  // ⏱️ COUNTDOWN
  // ═══════════════════════════════════════════════════════

  void _demarrerCountdown() {
    setState(() {
      _isCapturing = true;
      _countdown = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _capturerPhoto();
      }
    });
  }

  // ═══════════════════════════════════════════════════════
  // 📸 CAPTURER VIA toDataURL (évite les problèmes toBlob)
  // ═══════════════════════════════════════════════════════

  Future<void> _capturerPhoto() async {
    if (_videoElement == null) {
      widget.onPhotoTaken(null);
      return;
    }

    try {
      final width = _videoElement!.videoWidth;
      final height = _videoElement!.videoHeight;

      if (width == 0 || height == 0) {
        print('❌ Vidéo pas encore prête');
        widget.onPhotoTaken(null);
        return;
      }

      final canvas = web.HTMLCanvasElement()
        ..width = width
        ..height = height;

      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;

      // Miroir horizontal pour caméra frontale
      ctx.translate(width.toDouble(), 0);
      ctx.scale(-1, 1);
      ctx.drawImage(_videoElement!, 0, 0);

      // ✅ toDataURL — pas de problème de types JSAny
      final dataUrl = canvas.toDataURL('image/jpeg', 0.85.toJS);

      // Extraire la partie base64 après "data:image/jpeg;base64,"
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex == -1) {
        print('❌ Format dataURL invalide');
        widget.onPhotoTaken(null);
        return;
      }

      final base64String = dataUrl.substring(commaIndex + 1);

      // ✅ Décoder base64 en Uint8List via dart:convert
      final photoBytes = base64Decode(base64String);

      _arreterCamera();

      if (mounted) {
        setState(() {
          _capturedPhoto = photoBytes;
          _photoTaken = true;
        });
      }

      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        widget.onPhotoTaken(photoBytes);
      }
    } catch (e) {
      print('❌ Erreur capture photo web: $e');
      _arreterCamera();
      widget.onPhotoTaken(null);
    }
  }

  // ═══════════════════════════════════════════════════════
  // 🖥️ BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_permissionRefusee) {
      return _buildPermissionRefusee();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Vidéo live
          if (_cameraReady && !_photoTaken)
            Positioned.fill(
              child: HtmlElementView(viewType: _viewId),
            )
          else if (_photoTaken && _capturedPhoto != null)
            Positioned.fill(
              child: Image.memory(_capturedPhoto!, fit: BoxFit.cover),
            )
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: EnCheckColors.orDoux),
              ),
            ),

          // Overlay sombre
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.35)),
          ),

          // Contenu central
          SafeArea(child: Center(child: _buildContenu())),

          // Bouton annuler (avant countdown)
          if (!_isCapturing && !_photoTaken)
            Positioned(
              top: 50,
              left: 20,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () {
                    _arreterCamera();
                    widget.onCancel();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                    const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContenu() {
    if (_photoTaken) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: EnCheckColors.succes.withOpacity(0.95),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: EnCheckColors.succes.withOpacity(0.4),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 70),
            const SizedBox(height: 20),
            Text(
              'Bonjour ${widget.employeeName} !',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Pointage enregistré',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_isCapturing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 30),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: EnCheckColors.brunProfond.withOpacity(0.92),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: EnCheckColors.orDoux.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😊', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 20),
            const Text(
              'Un petit sourire',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'et c\'est tout !',
              style: TextStyle(color: EnCheckColors.orDoux, fontSize: 20),
            ),
            const SizedBox(height: 30),
            TweenAnimationBuilder<double>(
              key: ValueKey(_countdown),
              tween: Tween(begin: 1.2, end: 0.8),
              duration: const Duration(milliseconds: 900),
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EnCheckColors.terreChaude,
                      boxShadow: [
                        BoxShadow(
                          color: EnCheckColors.terreChaude.withOpacity(0.6),
                          blurRadius: 25,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '$_countdown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 45,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
      margin: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: EnCheckColors.brunProfond.withOpacity(0.95),
        borderRadius: BorderRadius.circular(25),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: EnCheckColors.orDoux),
          SizedBox(height: 20),
          Text(
            'Accès caméra...',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 🚫 PERMISSION REFUSÉE
  // ═══════════════════════════════════════════════════════

  Widget _buildPermissionRefusee() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: EnCheckColors.erreur.withOpacity(0.15),
                    border: Border.all(
                      color: EnCheckColors.erreur.withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: EnCheckColors.erreur,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Accès caméra requis',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                const Text(
                  'La photo est obligatoire pour le pointage.\n\n'
                      'Veuillez autoriser l\'accès à la caméra dans '
                      'les paramètres de votre navigateur puis réessayez.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    height: 1.7,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📍 Comment autoriser la caméra :',
                        style: TextStyle(
                          color: EnCheckColors.orDoux,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '1. Cliquez sur l\'icône 🔒 dans la barre d\'adresse\n'
                            '2. Trouvez "Caméra"\n'
                            '3. Sélectionnez "Autoriser"\n'
                            '4. Rechargez la page',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _permissionRefusee = false;
                        _cameraReady = false;
                      });
                      _initialiserCamera();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'Réessayer',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EnCheckColors.terreChaude,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    _arreterCamera();
                    widget.onCancel();
                  },
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
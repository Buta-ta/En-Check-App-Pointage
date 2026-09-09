// ═══════════════════════════════════════════════════════════
// 🤖 SERVICE RECONNAISSANCE FACIALE
// ═══════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

class FaceRecognitionService {
  static Interpreter? _interpreter;
  static FaceDetector? _faceDetector;
  static bool _isInitialized = false;

  // Taille d'entrée du modèle MobileFaceNet
  static const int _inputSize = 160;  // FaceNet utilise 160x160
  static const int _embeddingSize = 128;  // FaceNet produit 128 floats

  // ═══════════════════════════════════════════════════════════
  // 🚀 INITIALISER LE SERVICE
  // ═══════════════════════════════════════════════════════════

  static Future<bool> initialiser() async {
    if (_isInitialized) return true;

    try {
      // Charger le modèle TFLite
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
        options: InterpreterOptions()..threads = 4,
      );;

      // Initialiser le détecteur de visages ML Kit
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true, // Pour liveness (sourire, yeux)
          enableLandmarks: true,
          enableTracking: false,
          minFaceSize: 0.15,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

      _isInitialized = true;
      print('✅ FaceRecognitionService initialisé');
      return true;
    } catch (e) {
      print('❌ Erreur initialisation FaceRecognitionService: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 DÉTECTER LES VISAGES DANS UNE IMAGE
  // ═══════════════════════════════════════════════════════════

  static Future<List<Face>> detecterVisages(InputImage inputImage) async {
    if (_faceDetector == null) await initialiser();

    try {
      final faces = await _faceDetector!.processImage(inputImage);
      return faces;
    } catch (e) {
      print('❌ Erreur détection visages: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ VÉRIFIER LA QUALITÉ DU VISAGE
  // ═══════════════════════════════════════════════════════════

  static Map<String, dynamic> verifierQualiteVisage(Face face, int imageWidth, int imageHeight) {
    // Vérifier l'angle de rotation (trop penché = mauvaise qualité)
    final headEulerY = face.headEulerAngleY ?? 0; // Gauche/droite
    final headEulerZ = face.headEulerAngleZ ?? 0; // Rotation

    if (headEulerY.abs() > 30) {
      return {
        'valide': false,
        'message': 'Regardez droit devant la caméra',
      };
    }

    if (headEulerZ.abs() > 20) {
      return {
        'valide': false,
        'message': 'Redressez la tête',
      };
    }

    // Vérifier la taille du visage (pas trop loin)
    final faceWidth = face.boundingBox.width;
    final faceRatio = faceWidth / imageWidth;

    if (faceRatio < 0.2) {
      return {
        'valide': false,
        'message': 'Rapprochez-vous de la caméra',
      };
    }

    if (faceRatio > 0.9) {
      return {
        'valide': false,
        'message': 'Éloignez-vous un peu',
      };
    }

    return {
      'valide': true,
      'message': 'Visage détecté',
      'euler_y': headEulerY,
      'euler_z': headEulerZ,
      'face_ratio': faceRatio,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 👁️ VÉRIFICATION LIVENESS (ANTI-SPOOFING)
  // ═══════════════════════════════════════════════════════════

  static Map<String, dynamic> verifierLiveness(Face face) {
    // Probabilité que les yeux soient ouverts (0.0 = fermés, 1.0 = ouverts)
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;

    // Les deux yeux doivent être ouverts pour un vrai visage
    final yeuxOuverts = leftEyeOpen > 0.5 && rightEyeOpen > 0.5;

    return {
      'liveness_ok': yeuxOuverts,
      'left_eye_open': leftEyeOpen,
      'right_eye_open': rightEyeOpen,
      'message': yeuxOuverts
          ? 'Liveness validé'
          : 'Veuillez ouvrir les yeux et regarder la caméra',
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 🧮 EXTRAIRE LE VECTEUR FACIAL (EMBEDDING)
  // ═══════════════════════════════════════════════════════════

  static Future<List<double>?> extraireEmbedding(
      Uint8List imageBytes,
      Face face,
      ) async {
    if (_interpreter == null) await initialiser();

    try {
      // Décoder l'image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // Crop et resize le visage
      final boundingBox = face.boundingBox;

      // Ajouter une marge autour du visage (20%)
      final margin = (boundingBox.width * 0.2).toInt();
      final x = max(0, boundingBox.left.toInt() - margin);
      final y = max(0, boundingBox.top.toInt() - margin);
      final w = min(image.width - x, boundingBox.width.toInt() + margin * 2);
      final h = min(image.height - y, boundingBox.height.toInt() + margin * 2);

      // Crop le visage
      img.Image faceCrop = img.copyCrop(image, x: x, y: y, width: w, height: h);

      // Resize à la taille d'entrée du modèle (112x112)
      img.Image faceResized = img.copyResize(
        faceCrop,
        width: _inputSize,
        height: _inputSize,
      );

      // Normaliser les pixels (-1 à 1)
      final input = _imageToInput(faceResized);

      // Préparer la sortie
      final output = List.filled(1 * _embeddingSize, 0.0)
          .reshape([1, _embeddingSize]);

      // Inférence
      _interpreter!.run(input, output);

      // Extraire le vecteur
      final embedding = List<double>.from(output[0]);

      // Normaliser le vecteur (L2 normalization)
      return _normaliserVecteur(embedding);
    } catch (e) {
      print('❌ Erreur extraction embedding: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔢 CONVERTIR IMAGE EN TENSOR D'ENTRÉE
  // ═══════════════════════════════════════════════════════════

  static List<List<List<List<double>>>> _imageToInput(img.Image image) {
    // Shape: [1, 112, 112, 3]
    final input = List.generate(
      1,
          (_) => List.generate(
        _inputSize,
            (y) => List.generate(
          _inputSize,
              (x) {
            final pixel = image.getPixel(x, y);
            return [
              (pixel.r.toDouble() - 127.5) / 128.0,
              (pixel.g.toDouble() - 127.5) / 128.0,
              (pixel.b.toDouble() - 127.5) / 128.0,
            ];
          },
        ),
      ),
    );
    return input;
  }

  // ═══════════════════════════════════════════════════════════
  // 📐 NORMALISER UN VECTEUR (L2)
  // ═══════════════════════════════════════════════════════════

  static List<double> _normaliserVecteur(List<double> vecteur) {
    double norme = 0;
    for (var v in vecteur) {
      norme += v * v;
    }
    norme = sqrt(norme);

    if (norme == 0) return vecteur;

    return vecteur.map((v) => v / norme).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 📊 CALCULER LA SIMILARITÉ ENTRE DEUX VECTEURS
  // (Distance cosinus → plus proche de 1 = plus similaire)
  // ═══════════════════════════════════════════════════════════

  static double calculerSimilarite(
      List<double> vecteur1,
      List<double> vecteur2,
      ) {
    if (vecteur1.length != vecteur2.length) return 0.0;

    double produitScalaire = 0;
    double norme1 = 0;
    double norme2 = 0;

    for (int i = 0; i < vecteur1.length; i++) {
      produitScalaire += vecteur1[i] * vecteur2[i];
      norme1 += vecteur1[i] * vecteur1[i];
      norme2 += vecteur2[i] * vecteur2[i];
    }

    norme1 = sqrt(norme1);
    norme2 = sqrt(norme2);

    if (norme1 == 0 || norme2 == 0) return 0.0;

    // Score entre -1 et 1, on ramène entre 0 et 1
    final cosine = produitScalaire / (norme1 * norme2);
    return (cosine + 1) / 2;
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 CALCULER LA MOYENNE DE PLUSIEURS VECTEURS
  // (Pour l'enrôlement avec plusieurs captures)
  // ═══════════════════════════════════════════════════════════

  static List<double> moyenneVecteurs(List<List<double>> vecteurs) {
    if (vecteurs.isEmpty) return [];
    if (vecteurs.length == 1) return vecteurs.first;

    final taille = vecteurs.first.length;
    final moyenne = List<double>.filled(taille, 0.0);

    for (var vecteur in vecteurs) {
      for (int i = 0; i < taille; i++) {
        moyenne[i] += vecteur[i];
      }
    }

    for (int i = 0; i < taille; i++) {
      moyenne[i] /= vecteurs.length;
    }

    // Normaliser le vecteur moyen
    return _normaliserVecteur(moyenne);
  }

  // ═══════════════════════════════════════════════════════════
  // 🖼️ CONVERTIR CAMERAIMAGE EN INPUTIMAGE (ML Kit)
  // ═══════════════════════════════════════════════════════════

  static Future<List<Face>> detecterVisagesDepuisFichier(String imagePath) async {
    if (_faceDetector == null) await initialiser();
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector!.processImage(inputImage);
      return faces;
    } catch (e) {
      print('❌ Erreur détection visages: $e');
      return [];
    }
  }

// Garder l'ancienne mais elle ne sera plus utilisée pour le stream
  static InputImage? cameraImageToInputImage(
      CameraImage cameraImage,
      CameraDescription camera,
      ) {
    return null; // Désactivé, on utilise fichier
  }
  // ═══════════════════════════════════════════════════════════
  // 🧹 LIBÉRER LES RESSOURCES
  // ═══════════════════════════════════════════════════════════

  static Future<void> dispose() async {
    _interpreter?.close();
    await _faceDetector?.close();
    _isInitialized = false;
    print('🧹 FaceRecognitionService libéré');
  }
}
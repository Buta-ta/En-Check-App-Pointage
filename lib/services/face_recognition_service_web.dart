// lib/services/face_recognition_service_web.dart
// Version Web — mode dégradé (pas de TFLite sur web)

import 'dart:typed_data';

class FaceRecognitionService {
  static bool _isInitialized = false;

  static Future<bool> initialiser() async {
    if (_isInitialized) return true;
    _isInitialized = true;
    print('✅ FaceRecognitionService WEB initialisé (mode dégradé)');
    return true;
  }

  static Future<List<dynamic>> detecterVisagesDepuisFichier(String path) async {
    print('⚠️ Détection visages non disponible sur Web');
    return [];
  }

  static Map<String, dynamic> verifierQualiteVisage(dynamic face, int imageWidth, int imageHeight) {
    return {
      'valide': false,
      'message': 'Reconnaissance faciale non disponible sur Web',
    };
  }

  static Map<String, dynamic> verifierLiveness(dynamic face) => {
    'liveness_ok': false,
    'left_eye_open': 0.0,
    'right_eye_open': 0.0,
    'message': 'Liveness non disponible sur Web',
  };

  static Future<List<double>?> extraireEmbedding(Uint8List imageBytes, dynamic face) async {
    print('⚠️ Extraction embedding non disponible sur Web');
    return null;
  }

  static double calculerSimilarite(List<double> a, List<double> b) => 0.0;

  static List<double> moyenneVecteurs(List<List<double>> vecteurs) {
    if (vecteurs.isEmpty) return [];
    return vecteurs.first;
  }

  static Future<void> dispose() async {
    _isInitialized = false;
  }
}
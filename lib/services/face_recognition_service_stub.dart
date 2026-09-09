// lib/services/face_recognition_service_stub.dart
// Fallback stub — plateforme non supportée

import 'dart:typed_data';

class FaceRecognitionService {
  static Future<bool> initialiser() async {
    print('⚠️ FaceRecognitionService STUB — plateforme non supportée');
    return false;
  }

  static Future<List<dynamic>> detecterVisagesDepuisFichier(String path) async => [];

  static Map<String, dynamic> verifierQualiteVisage(dynamic face, int w, int h) => {
    'valide': false,
    'message': 'Non disponible',
  };

  static Map<String, dynamic> verifierLiveness(dynamic face) => {
    'liveness_ok': false,
    'message': 'Non disponible',
  };

  static Future<List<double>?> extraireEmbedding(Uint8List imageBytes, dynamic face) async => null;

  static double calculerSimilarite(List<double> a, List<double> b) => 0.0;

  static List<double> moyenneVecteurs(List<List<double>> vecteurs) => [];

  static Future<void> dispose() async {}
}
// Stub FaceRecognitionService pour Flutter Web
// Toutes les méthodes retournent des valeurs vides

class FaceRecognitionService {
  static Future<void> initialiser() async {}

  static Future<List<dynamic>> detecterVisagesDepuisFichier(
      String path,
      ) async => [];

  static Map<String, dynamic> verifierLiveness(dynamic face) => {
    'liveness_ok': false,
    'message': 'Non disponible sur Web',
  };

  static Future<List<double>?> extraireEmbedding(
      dynamic photoBytes,
      dynamic face,
      ) async => null;

  static double calculerSimilarite(
      List<double> a,
      List<double> b,
      ) => 0.0;
}
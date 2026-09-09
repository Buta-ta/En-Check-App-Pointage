import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static bool _isOnline = true;

  // ═══════════════════════════════════════════════════════════
  // 🌐 VÉRIFIER SI ON EST EN LIGNE
  // ═══════════════════════════════════════════════════════════
  static bool get isOnline => _isOnline;

  // ═══════════════════════════════════════════════════════════
  // 🚀 INITIALISER LE SERVICE
  // ═══════════════════════════════════════════════════════════
  static Future<void> initialize() async {
    await _verifierConnexion();

    _connectivity.onConnectivityChanged.listen((results) {
      _isOnline = results.any((result) => result != ConnectivityResult.none);
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 VÉRIFIER LA CONNEXION ACTUELLE
  // ═══════════════════════════════════════════════════════════
  static Future<bool> _verifierConnexion() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = results.any((result) => result != ConnectivityResult.none);
    return _isOnline;
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 RAFRAÎCHIR LE STATUT
  // ═══════════════════════════════════════════════════════════
  static Future<bool> rafraichirStatut() async {
    return await _verifierConnexion();
  }
}

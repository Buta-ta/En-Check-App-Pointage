// ═══════════════════════════════════════════════════════════

// lib/services/geofencing_service.dart
// Version Mobile — NE PAS MODIFIER LE RESTE DU FICHIER

export 'geofencing_service.dart' if (dart.library.html) 'geofencing_service_web.dart';


// 🌍 SERVICE GEOFENCING
// ═══════════════════════════════════════════════════════════

import 'dart:math' show cos, sqrt, asin, pi;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'trusted_punch_service.dart';

class GeofencingService {
  static final _supabase = Supabase.instance.client;

  // ═══════════════════════════════════════════════════════════
  // 🔧 VÉRIFIER SI LE MODULE EST ACTIVÉ
  // ═══════════════════════════════════════════════════════════

  static Future<bool> isModuleActif() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('module_geolocalisation') ?? false;
  }

  // ═══════════════════════════════════════════════════════════
  // 📍 OBTENIR LA POSITION GPS ACTUELLE
  // ═══════════════════════════════════════════════════════════

  /// Pourquoi la dernière tentative a échoué — pour des messages HONNÊTES :
  ///  'permission'  → la localisation est réellement refusée (réglages)
  ///  'service'     → les services de localisation sont désactivés
  ///  'introuvable' → temporairement introuvable (GPS faible, intérieur…)
  static String? raisonDernierEchec;

  /// Obtenir la position GPS.
  ///
  /// [tentatives] : nombre de recherches avant d'abandonner (3 par défaut
  /// pour un pointage ; 1 pour un simple affichage « Hors site »).
  ///
  /// ⚠️ LEÇON DU 17/10 (iPad) : on ne fait PLUS confiance aux seuls
  /// drapeaux de permission. Sur Safari, une simple recherche de position
  /// ÉCHOUÉE (kCLErrorLocationUnknown = « je ne sais pas où tu es », GPS
  /// faible ou intérieur) fait répondre le module web « permission refusée
  /// définitivement ». La VÉRITÉ, c'est la vraie tentative de position
  /// ci-dessous : c'est elle qui décide.
  static Future<Position?> obtenirPosition({int tentatives = 3}) async {
    raisonDernierEchec = null;

    // 1. Services de localisation activés ? (sur web, toujours « oui »)
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        raisonDernierEchec = 'service';
        print('❌ Service GPS désactivé sur l\'appareil');
        return null;
      }
    } catch (_) {
      // Certains navigateurs ne savent pas répondre : on continue.
    }

    // 2. Demande de permission (utile pour afficher la fenêtre système)…
    //    …mais son verdict ne tranche RIEN (voir la leçon du 17/10).
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
    } catch (_) {}

    // 3. LA VÉRITÉ : la vraie tentative de position, avec retentatives.
    for (var essai = 1; essai <= tentatives; essai++) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        raisonDernierEchec = null;
        print('✅ Position GPS obtenue: ${position.latitude}, ${position.longitude}');
        print('   Précision: ${position.accuracy.toStringAsFixed(1)}m');
        return position;
      } on PermissionDeniedException {
        // Refus RÉEL du système ou du navigateur… ou un échec de GPS mal
        // résumé en « refus » : une seconde tentative sert de garde-fou.
        raisonDernierEchec = 'permission';
        print('⚠️ GPS : refus de localisation (tentative $essai/$tentatives)');
        if (essai < tentatives) {
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        // Timeout, « position introuvable » (kCLErrorLocationUnknown)…
        // → ennuis PASSAGERS : on retente avant d'abandonner.
        raisonDernierEchec = 'introuvable';
        print('⚠️ GPS : position introuvable (tentative $essai/$tentatives) : $e');
        if (essai < tentatives) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    print('❌ Position GPS indisponible (raison : $raisonDernierEchec)');
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 DÉTECTER LE MOCK GPS (ANTI-TRICHE)
  // ═══════════════════════════════════════════════════════════

  static Future<bool> estMockLocation(Position position) async {
    try {
      // Sur Android, Geolocator détecte automatiquement les mock locations
      return position.isMocked;
    } catch (e) {
      print('⚠️ Impossible de vérifier mock location: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🌍 RÉCUPÉRER LES ZONES GÉOFENCÉES D'UNE ENTREPRISE
  // ═══════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> chargerZones(String enterpriseId) async {
    try {
      // ⭐ LIVRAISON 16 — ⚠️ la lecture directe ne renvoyait RIEN (la table est
      //    sous RLS sans règle de lecture) et le code concluait alors « aucune
      //    zone » → « hors zone non bloquant » → TOUT pointage était autorisé.
      //    Le contrôle de zone disparaissait sans le moindre message.
      final reponse = await _supabase.rpc('encheck_zones_lister', params: {
        'p_jeton': TrustedPunchService.jeton,
      });

      if (reponse is Map && reponse['ok'] == true) {
        final zones = (reponse['zones'] as List? ?? [])
            .map((z) => Map<String, dynamic>.from(z as Map))
            .toList();
        print('✅ ${zones.length} zone(s) de pointage chargée(s)');
        return zones;
      }
      print('⚠️ Zones refusées par le serveur : ${reponse is Map ? reponse['reason'] : reponse}');
      return [];
    } catch (e) {
      print('❌ Erreur chargement zones: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📐 CALCULER LA DISTANCE ENTRE DEUX POINTS GPS (HAVERSINE)
  // ═══════════════════════════════════════════════════════════

  static double calculerDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const double earthRadiusMeters = 6371000; // Rayon de la Terre en mètres

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * asin(sqrt(a));

    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  static double sin(double radians) => _sin(radians);
  static double cos(double radians) => _cos(radians);

  static double _sin(double x) {
    // Approximation Taylor pour sin
    double result = x;
    double term = x;
    for (int i = 1; i < 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  static double _cos(double x) {
    // Approximation Taylor pour cos
    double result = 1;
    double term = 1;
    for (int i = 1; i < 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ VÉRIFIER SI L'EMPLOYÉ EST DANS UNE ZONE
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> verifierZone({
    required String enterpriseId,
    required Position position,
  }) async {
    try {
      // Détecter mock location
      bool isMock = await estMockLocation(position);
      if (isMock) {
        return {
          'autorise': false,
          'raison': 'mock_gps',
          'message': 'Fausse position GPS détectée',
          'geofence_id': null,
          'distance_meters': null,
          'is_within_zone': false,
        };
      }

      // Charger les zones de l'entreprise
      List<Map<String, dynamic>> zones = await chargerZones(enterpriseId);

      if (zones.isEmpty) {
        // Aucune zone définie = pas de restriction
        return {
          'autorise': true,
          'raison': 'aucune_zone',
          'message': 'Aucune zone géofencée définie',
          'geofence_id': null,
          'distance_meters': null,
          'is_within_zone': null,
        };
      }

      // Vérifier chaque zone
      Map<String, dynamic>? zoneLaPlusProche;
      double? distanceMinimale;

      for (var zone in zones) {
        double distance = calculerDistance(
          lat1: position.latitude,
          lon1: position.longitude,
          lat2: zone['latitude'],
          lon2: zone['longitude'],
        );

        if (distanceMinimale == null || distance < distanceMinimale) {
          distanceMinimale = distance;
          zoneLaPlusProche = zone;
        }

        // Si dans la zone
        if (distance <= zone['radius_meters']) {
          return {
            'autorise': true,
            'raison': 'dans_zone',
            'message': 'Dans la zone "${zone['name']}"',
            'geofence_id': zone['id'],
            'distance_meters': distance.round(),
            'is_within_zone': true,
            'zone': zone,
          };
        }
      }

      // Hors de toutes les zones
      bool isBlocking = zoneLaPlusProche?['is_blocking'] ?? false;

      return {
        'autorise': !isBlocking,
        'raison': isBlocking ? 'hors_zone_bloquant' : 'hors_zone_non_bloquant',
        'message': isBlocking
            ? 'Vous êtes hors de la zone autorisée (${distanceMinimale?.round()}m de "${zoneLaPlusProche?['name']}")'
            : 'Pointage hors zone (${distanceMinimale?.round()}m)',
        'geofence_id': zoneLaPlusProche?['id'],
        'distance_meters': distanceMinimale?.round(),
        'is_within_zone': false,
        'zone': zoneLaPlusProche,
      };
    } catch (e) {
      print('❌ Erreur vérification zone: $e');
      // En cas d'erreur, on autorise pour ne pas bloquer l'employé
      return {
        'autorise': true,
        'raison': 'erreur',
        'message': 'Erreur vérification zone',
        'geofence_id': null,
        'distance_meters': null,
        'is_within_zone': null,
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 💾 ENREGISTRER LE POINTAGE AVEC DONNÉES GÉOFENCING
  // ═══════════════════════════════════════════════════════════

  static Future<String?> enregistrerPointageAvecGeo({
    required String employeeId,
    required String enterpriseId,
    required String checkType,
    required String method,
    Position? position,
    Map<String, dynamic>? verificationZone,
  }) async {
    try {
      // ⭐ LIVRAISON 09 : le SERVEUR fixe l'heure, plus le téléphone
      final resultat = await TrustedPunchService.pointer(
        employeeId:     employeeId,
        enterpriseId:   enterpriseId,
        checkType:      checkType,
        method:         method,
        latitude:       position?.latitude,
        longitude:      position?.longitude,
        gpsAccuracy:    position?.accuracy,
        geofenceId:     verificationZone?['geofence_id']     as String?,
        distanceMeters: verificationZone?['distance_meters'] as int?,
        isWithinZone:   verificationZone?['is_within_zone']  as bool?,
      );

      if (resultat['ok'] == true) return resultat['attendance_id'] as String?;
      print('❌ Pointage refusé : ${resultat['reason']}');
      return null;
    } catch (e) {
      print('❌ Erreur enregistrement pointage avec geo: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📊 FORMATER LA DISTANCE POUR L'AFFICHAGE
  // ═══════════════════════════════════════════════════════════

  static String formaterDistance(int? distanceMeters) {
    if (distanceMeters == null) return '—';
    if (distanceMeters < 1000) return '${distanceMeters}m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }

  // ═══════════════════════════════════════════════════════════
  // 🎨 OBTENIR LA COULEUR SELON LE STATUT
  // ═══════════════════════════════════════════════════════════

  static String getStatutCouleur(bool? isWithinZone) {
    if (isWithinZone == null) return '#8B6914'; // Pas de zone définie
    return isWithinZone ? '#28a745' : '#dc3545'; // Vert ou Rouge
  }

  static String getStatutTexte(bool? isWithinZone) {
    if (isWithinZone == null) return 'Non vérifié';
    return isWithinZone ? 'Dans la zone' : 'Hors zone';
  }
}
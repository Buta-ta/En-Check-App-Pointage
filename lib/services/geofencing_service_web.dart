// lib/services/geofencing_service_web.dart
// Version Web du GeofencingService

import 'dart:async';
import 'dart:html' as html;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'trusted_punch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' show cos, sqrt, asin, pi, sin;

class Position {
  final double latitude;
  final double longitude;
  final double accuracy;
  final bool isMocked;

  const Position({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0.0,
    this.isMocked = false,
  });
}

class GeofencingService {
  static final _supabase = Supabase.instance.client;

  static Future<bool> isModuleActif() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('module_geolocalisation') ?? false;
  }

  static Future<Position?> obtenirPosition() async {
    try {
      final completer = Completer<Position?>();

      html.window.navigator.geolocation.getCurrentPosition().then((pos) {
        completer.complete(Position(
          latitude: pos.coords!.latitude!.toDouble(),
          longitude: pos.coords!.longitude!.toDouble(),
          accuracy: pos.coords!.accuracy?.toDouble() ?? 0.0,
          isMocked: false,
        ));
      }).catchError((e) {
        print('❌ Erreur géolocalisation web: $e');
        completer.complete(null);
      });

      return completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
    } catch (e) {
      print('❌ Erreur obtention position GPS web: $e');
      return null;
    }
  }

  static Future<bool> estMockLocation(Position position) async => false;

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

  static double calculerDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const double earthRadiusMeters = 6371000;
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

  static double _degreesToRadians(double degrees) => degrees * pi / 180;

  static Future<Map<String, dynamic>> verifierZone({
    required String enterpriseId,
    required Position position,
  }) async {
    try {
      List<Map<String, dynamic>> zones = await chargerZones(enterpriseId);

      if (zones.isEmpty) {
        return {
          'autorise': true,
          'raison': 'aucune_zone',
          'message': 'Aucune zone géofencée définie',
          'geofence_id': null,
          'distance_meters': null,
          'is_within_zone': null,
        };
      }

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

      bool isBlocking = zoneLaPlusProche?['is_blocking'] ?? false;

      return {
        'autorise': !isBlocking,
        'raison': isBlocking ? 'hors_zone_bloquant' : 'hors_zone_non_bloquant',
        'message': isBlocking
            ? 'Vous êtes hors de la zone autorisée (${distanceMinimale?.round()}m)'
            : 'Pointage hors zone (${distanceMinimale?.round()}m)',
        'geofence_id': zoneLaPlusProche?['id'],
        'distance_meters': distanceMinimale?.round(),
        'is_within_zone': false,
        'zone': zoneLaPlusProche,
      };
    } catch (e) {
      print('❌ Erreur vérification zone: $e');
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

  static Future<String?> enregistrerPointageAvecGeo({
    required String employeeId,
    required String enterpriseId,
    required String checkType,
    required String method,
    Position? position,
    Map<String, dynamic>? verificationZone,
  }) async {
    try {
      // ⭐ LIVRAISON 09 : le SERVEUR fixe l'heure, plus le navigateur
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
      print('❌ Erreur enregistrement pointage: $e');
      return null;
    }
  }

  static String formaterDistance(int? distanceMeters) {
    if (distanceMeters == null) return '—';
    if (distanceMeters < 1000) return '${distanceMeters}m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }

  static String getStatutCouleur(bool? isWithinZone) {
    if (isWithinZone == null) return '#8B6914';
    return isWithinZone ? '#28a745' : '#dc3545';
  }

  static String getStatutTexte(bool? isWithinZone) {
    if (isWithinZone == null) return 'Non vérifié';
    return isWithinZone ? 'Dans la zone' : 'Hors zone';
  }
}
// lib/stubs/geolocator_stub.dart
// Stub Geolocator pour Flutter Web

enum LocationPermission { denied, deniedForever, whileInUse, always }
enum LocationAccuracy { lowest, low, medium, high, best, bestForNavigation }

class Position {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final bool isMocked;
  final double altitudeAccuracy;
  final double headingAccuracy;
  final double speedAccuracy;
  final int? floor;

  Position({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.timestamp,
    this.isMocked = false,
    this.altitudeAccuracy = 0.0,
    this.headingAccuracy = 0.0,
    this.speedAccuracy = 0.0,
    this.floor,
  });
}

class Geolocator {
  static Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  static Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;

  static Future<bool> isLocationServiceEnabled() async => false;

  static Future<Position> getCurrentPosition({
    LocationAccuracy? desiredAccuracy,
    Duration? timeLimit,
  }) async {
    return Position(
      latitude: 0.0,
      longitude: 0.0,
      accuracy: 0.0,
      altitude: 0.0,
      speed: 0.0,
      heading: 0.0,
      timestamp: DateTime.now(),
    );
  }
}
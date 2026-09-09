// lib/services/photo_service_interface.dart
// Point d'entrée unique avec conditional export

export 'photo_service_web.dart'
if (dart.library.io) 'photo_service.dart';
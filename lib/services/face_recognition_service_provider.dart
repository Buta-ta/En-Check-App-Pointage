// lib/services/face_recognition_service_provider.dart
// Conditional export pour FaceRecognitionService

export 'face_recognition_service_stub.dart'
if (dart.library.io) 'face_recognition_service.dart'
if (dart.library.html) 'face_recognition_service_web.dart';
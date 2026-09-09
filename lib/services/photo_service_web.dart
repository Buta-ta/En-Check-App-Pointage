// lib/services/photo_service_web.dart
// Version Web — sans dart:io ni camera

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'trusted_punch_service.dart';   // ⭐ LIVRAISON 14 : le jeton de session

class PhotoService {
  static final _supabase = Supabase.instance.client;
  static const String _bucketName = 'attendance-photos';

  // ═══════════════════════════════════════════════════════════
  // 📷 INITIALISER LA CAMÉRA — Non disponible sur Web
  // ═══════════════════════════════════════════════════════════

  static Future<dynamic> initialiserCameraFrontale() async {
    print('⚠️ Caméra non disponible sur Web');
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // 📸 CAPTURER UNE PHOTO — Non disponible sur Web
  // ═══════════════════════════════════════════════════════════

  static Future<Uint8List?> capturerPhoto(dynamic controller) async {
    print('⚠️ Capture photo non disponible sur Web');
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // ☁️ UPLOAD VERS SUPABASE STORAGE
  // (Fonctionne sur Web — pas besoin de dart:io)
  // ═══════════════════════════════════════════════════════════

  static Future<String?> uploadPhoto({
    required Uint8List photoBytes,
    required String enterpriseId,
    required String employeeId,
  }) async {
    try {
      final now = DateTime.now();
      final yearMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final timestamp = now.millisecondsSinceEpoch;
      final fileName = '${employeeId}_$timestamp.jpg';
      final filePath = '$enterpriseId/$yearMonth/$fileName';

      await _supabase.storage.from(_bucketName).uploadBinary(
        filePath,
        photoBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      );

      final url =
      _supabase.storage.from(_bucketName).getPublicUrl(filePath);

      print('✅ Photo uploadée (Web): $filePath');
      return url;
    } catch (e) {
      print('❌ Erreur upload photo (Web): $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 💾 ENREGISTRER DANS LA TABLE pointages_photos
  // ═══════════════════════════════════════════════════════════

  static Future<bool> enregistrerPhotoPointage({
    required String pointageId,
    required String photoUrl,
  }) async {
    try {
      // ⭐ LIVRAISON 14 — même règle que sur mobile : c'est le serveur qui
      //    vérifie que ce pointage appartient bien au porteur du jeton.
      final reponse = await _supabase.rpc('encheck_photo_enregistrer', params: {
        'p_jeton':       TrustedPunchService.jeton,
        'p_pointage_id': pointageId,
        'p_photo_url':   photoUrl,
      });

      if (reponse is Map && reponse['ok'] != true) {
        print('⚠️ Photo refusée par le serveur : ${reponse['reason']}');
        return false;
      }

      print('✅ Photo enregistrée (Web) pour pointage: $pointageId');
      return true;
    } catch (e) {
      print('❌ Erreur enregistrement photo (Web): $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 UPLOAD + ENREGISTREMENT
  // ═══════════════════════════════════════════════════════════

  static Future<String?> uploadEtEnregistrer({
    required Uint8List photoBytes,
    required String enterpriseId,
    required String employeeId,
    required String pointageId,
  }) async {
    try {
      final photoUrl = await uploadPhoto(
        photoBytes: photoBytes,
        enterpriseId: enterpriseId,
        employeeId: employeeId,
      );

      if (photoUrl == null) {
        print('❌ Échec upload photo (Web)');
        return null;
      }

      await enregistrerPhotoPointage(
        pointageId: pointageId,
        photoUrl: photoUrl,
      );

      return photoUrl;
    } catch (e) {
      print('❌ Erreur uploadEtEnregistrer (Web): $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 CAPTURE + SAUVEGARDE — Non disponible sur Web
  // ═══════════════════════════════════════════════════════════

  static Future<String?> capturerEtSauvegarder({
    required dynamic controller,
    required String enterpriseId,
    required String employeeId,
    required String pointageId,
  }) async {
    print('⚠️ capturerEtSauvegarder non disponible sur Web');
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // 💾 SAUVEGARDER LOCALEMENT — Limité sur Web
  // ═══════════════════════════════════════════════════════════

  static Future<String?> sauvegarderLocalement({
    required Uint8List photoBytes,
    required String enterpriseId,
    required String employeeId,
  }) async {
    // Sur Web, on tente directement l'upload si possible
    // Sinon on retourne null proprement
    print('⚠️ Sauvegarde locale non disponible sur Web');
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 SYNC PHOTOS EN ATTENTE — Non disponible sur Web
  // ═══════════════════════════════════════════════════════════

  static Future<void> syncPhotosEnAttente() async {
    print('⚠️ Sync photos offline non supporté sur Web');
  }

  // ═══════════════════════════════════════════════════════════
  // 🧹 LIBÉRER LA CAMÉRA — Non disponible sur Web
  // ═══════════════════════════════════════════════════════════

  static Future<void> libererCamera(dynamic controller) async {
    // Rien à faire sur Web
  }
}
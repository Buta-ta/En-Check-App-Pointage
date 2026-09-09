// ═══════════════════════════════════════════════════════════
// 📸 SERVICE PHOTO POINTAGE
// ═══════════════════════════════════════════════════════════
// lib/services/photo_service.dart
// Version Mobile — AJOUTER en haut si pas déjà présent :

import 'dart:io';                    // ✅ OK sur mobile uniquement
import 'dart:typed_data';
import 'package:camera/camera.dart'; // ✅ OK sur mobile uniquement
import 'package:flutter/foundation.dart' show kIsWeb;
import 'trusted_punch_service.dart';   // ⭐ LIVRAISON 14 : le jeton de session
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// LE RESTE DU FICHIER RESTE IDENTIQUE

class PhotoService {
  static final _supabase = Supabase.instance.client;
  static const String _bucketName = 'attendance-photos';

  // ═══════════════════════════════════════════════════════════
  // 📷 INITIALISER LA CAMÉRA FRONTALE
  // ═══════════════════════════════════════════════════════════

  static Future<CameraController?> initialiserCameraFrontale() async {
    try {
      final cameras = await availableCameras();

      // Chercher la caméra frontale
      CameraDescription? frontCamera;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      // Si pas de caméra frontale, prendre la première disponible
      frontCamera ??= cameras.isNotEmpty ? cameras.first : null;

      if (frontCamera == null) {
        print('❌ Aucune caméra disponible');
        return null;
      }

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium, // Bon compromis qualité/taille
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      return controller;
    } catch (e) {
      print('❌ Erreur initialisation caméra: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📸 CAPTURER UNE PHOTO
  // ═══════════════════════════════════════════════════════════

  static Future<Uint8List?> capturerPhoto(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) {
        print('❌ Caméra non initialisée');
        return null;
      }

      final XFile photo = await controller.takePicture();
      final Uint8List bytes = await photo.readAsBytes();

      // Compresser l'image
      final Uint8List? compressedBytes = await _compresserImage(bytes);

      return compressedBytes ?? bytes;
    } catch (e) {
      print('❌ Erreur capture photo: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🗜️ COMPRESSER L'IMAGE
  // ═══════════════════════════════════════════════════════════

  static Future<Uint8List?> _compresserImage(Uint8List bytes) async {
    try {
      if (kIsWeb) {
        // Sur le web, compression limitée — on retourne tel quel si < 500KB
        if (bytes.length < 500000) return bytes;

        // Sinon on tente une compression basique
        return await FlutterImageCompress.compressWithList(
          bytes,
          quality: 70,
        );
      }

      // Sur mobile/desktop
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 480,
        minHeight: 640,
        quality: 75,
        format: CompressFormat.jpeg,
      );

      print('📸 Photo compressée: ${bytes.length} → ${result.length} bytes');
      return result;
    } catch (e) {
      print('⚠️ Erreur compression (utilisation originale): $e');
      return bytes;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ☁️ UPLOAD VERS SUPABASE STORAGE
  // ═══════════════════════════════════════════════════════════

  static Future<String?> uploadPhoto({
    required Uint8List photoBytes,
    required String enterpriseId,
    required String employeeId,
  }) async {
    try {
      // Générer le chemin : enterprise_id/YYYY-MM/employee_id_timestamp.jpg
      final now = DateTime.now();
      final yearMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final timestamp = now.millisecondsSinceEpoch;
      final fileName = '${employeeId}_$timestamp.jpg';
      final filePath = '$enterpriseId/$yearMonth/$fileName';

      // Upload
      await _supabase.storage.from(_bucketName).uploadBinary(
        filePath,
        photoBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      );

      // Générer l'URL publique (signée)
      final url = _supabase.storage.from(_bucketName).getPublicUrl(filePath);

      print('✅ Photo uploadée: $filePath');
      return url;
    } catch (e) {
      print('❌ Erreur upload photo: $e');
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
      // ⭐ LIVRAISON 14 — l'écriture passe par le SERVEUR, avec le jeton de session.
      //    Avant, la clé publique écrivait en direct : n'importe qui pouvait coller
      //    une photo sur le pointage d'un autre. Le serveur vérifie désormais que
      //    le pointage appartient bien au porteur du jeton.
      final reponse = await _supabase.rpc('encheck_photo_enregistrer', params: {
        'p_jeton':       TrustedPunchService.jeton,
        'p_pointage_id': pointageId,
        'p_photo_url':   photoUrl,
      });

      if (reponse is Map && reponse['ok'] != true) {
        print('⚠️ Photo refusée par le serveur : ${reponse['reason']}');
        return false;
      }

      print('✅ Photo enregistrée pour pointage: $pointageId');
      return true;
    } catch (e) {
      print('❌ Erreur enregistrement photo: $e');
      return false;
    }
  }

// ═══════════════════════════════════════════════════════════
// 🔄 MÉTHODE COMPLÈTE : UPLOAD + ENREGISTREMENT
// (Utilisée quand on a déjà les bytes de la photo)
// ═══════════════════════════════════════════════════════════

  static Future<String?> uploadEtEnregistrer({
    required Uint8List photoBytes,
    required String enterpriseId,
    required String employeeId,
    required String pointageId,
  }) async {
    try {
      // 1. Compresser
      final compressedBytes = await _compresserImage(photoBytes);
      final finalBytes = compressedBytes ?? photoBytes;

      // 2. Upload
      final photoUrl = await uploadPhoto(
        photoBytes: finalBytes,
        enterpriseId: enterpriseId,
        employeeId: employeeId,
      );

      if (photoUrl == null) {
        print('❌ Échec upload photo');
        return null;
      }

      // 3. Enregistrer en base
      final success = await enregistrerPhotoPointage(
        pointageId: pointageId,
        photoUrl: photoUrl,
      );

      if (!success) {
        print('⚠️ Photo uploadée mais non enregistrée en base');
      }

      return photoUrl;
    } catch (e) {
      print('❌ Erreur uploadEtEnregistrer: $e');
      return null;
    }
  }

// ═══════════════════════════════════════════════════════════
// 🔄 MÉTHODE COMPLÈTE AVEC CONTROLLER
// (Utilisée quand on a un controller de caméra actif)
// ═══════════════════════════════════════════════════════════

  static Future<String?> capturerEtSauvegarder({
    required CameraController controller,
    required String enterpriseId,
    required String employeeId,
    required String pointageId,
  }) async {
    try {
      // 1. Capturer
      final photoBytes = await capturerPhoto(controller);
      if (photoBytes == null) {
        print('❌ Échec capture photo');
        return null;
      }

      // 2. Upload et enregistrer
      return await uploadEtEnregistrer(
        photoBytes: photoBytes,
        enterpriseId: enterpriseId,
        employeeId: employeeId,
        pointageId: pointageId,
      );
    } catch (e) {
      print('❌ Erreur capturerEtSauvegarder: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 💾 SAUVEGARDER LOCALEMENT (POUR MODE OFFLINE)
  // ═══════════════════════════════════════════════════════════

  static Future<String?> sauvegarderLocalement({
    required Uint8List photoBytes,
    required String enterpriseId,
    required String employeeId,
  }) async {
    try {
      if (kIsWeb) {
        // Sur le web, on ne peut pas sauvegarder localement facilement
        // On encode en base64 pour stockage temporaire
        return 'pending:${_bytesToBase64(photoBytes)}';
      }

      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/pending_photos');

      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${enterpriseId}_${employeeId}_$timestamp.jpg';
      final filePath = '${photosDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(photoBytes);

      print('💾 Photo sauvegardée localement: $filePath');
      return filePath;
    } catch (e) {
      print('❌ Erreur sauvegarde locale: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 SYNC PHOTOS EN ATTENTE
  // ═══════════════════════════════════════════════════════════

  static Future<void> syncPhotosEnAttente() async {
    try {
      if (kIsWeb) {
        print('⚠️ Sync photos offline non supporté sur le web');
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/pending_photos');

      if (!await photosDir.exists()) return;

      final files = photosDir.listSync().whereType<File>();

      for (final file in files) {
        // Extraire les infos du nom de fichier
        final fileName = file.path.split('/').last;
        final parts = fileName.replaceAll('.jpg', '').split('_');

        if (parts.length >= 3) {
          final enterpriseId = parts[0];
          final employeeId = parts[1];

          final bytes = await file.readAsBytes();
          final url = await uploadPhoto(
            photoBytes: bytes,
            enterpriseId: enterpriseId,
            employeeId: employeeId,
          );

          if (url != null) {
            await file.delete();
            print('✅ Photo synchro: $fileName');
          }
        }
      }
    } catch (e) {
      print('❌ Erreur sync photos: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🧹 LIBÉRER LA CAMÉRA
  // ═══════════════════════════════════════════════════════════

  static Future<void> libererCamera(CameraController? controller) async {
    if (controller != null && controller.value.isInitialized) {
      await controller.dispose();
      print('📷 Caméra libérée');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔧 UTILITAIRES
  // ═══════════════════════════════════════════════════════════

  static String _bytesToBase64(Uint8List bytes) {
    return Uri.encodeFull(String.fromCharCodes(bytes));
  }
}
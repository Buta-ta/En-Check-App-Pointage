import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityService {
  // ═══════════════════════════════════════════════════════════
  // 🔐 HASHER UN PIN
  // ═══════════════════════════════════════════════════════════
  static String hasherPin(String pin) {
    // Ajouter un "sel" pour plus de sécurité
    const sel = 'EnCheck_2024_Secure';
    final contenu = '$sel$pin$sel';

    // Créer le hash SHA-256
    final bytes = utf8.encode(contenu);
    final hash = sha256.convert(bytes);

    return hash.toString();
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ VÉRIFIER UN PIN
  // ═══════════════════════════════════════════════════════════
  static bool verifierPin(String pinSaisi, String hashStocke) {
    final hashSaisi = hasherPin(pinSaisi);
    return hashSaisi == hashStocke;
  }
}

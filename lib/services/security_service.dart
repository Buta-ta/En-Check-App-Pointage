import 'dart:convert';
import 'dart:math';
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
  // ═══════════════════════════════════════════════════════════
  // ⭐ LIVRAISON 13 — LE VÉRIFICATEUR HORS-LIGNE
  //
  //  Pour pointer sans réseau, l'application doit reconnaître un employé sans
  //  interroger le serveur. Avant, elle TÉLÉCHARGEait le `pin_hash` de tout le
  //  monde et comparait. C'était perdu d'avance : ce hachage est un simple
  //  SHA-256 avec un sel écrit dans le code, et un PIN de 4 chiffres s'y
  //  retrouve en 11 millisecondes. Quiconque a la clé publique pouvait donc
  //  télécharger les hachages de toute l'entreprise et les casser.
  //
  //  Désormais, à la PREMIÈRE connexion réussie, l'application fabrique son
  //  propre vérificateur : un sel tiré au hasard SUR L'APPAREIL, et un hachage
  //  répété 20 000 fois. Le hachage du serveur ne quitte jamais le serveur.
  //
  //  ⚠️ Honnêteté : ceci protège contre le VOL DES HACHAGES (l'attaque qui
  //     marchait), pas contre quelqu'un qui a le téléphone déverrouillé en
  //     main. C'est le rôle du verrouillage de l'appareil.
  // ═══════════════════════════════════════════════════════════
  static const int _iterations = 20000;

  static String _deriver(String secret, String sel) {
    var h = sha256.convert(utf8.encode('$sel|$secret|$sel'));
    final suffixe = utf8.encode('|$sel');
    for (var i = 1; i < _iterations; i++) {
      h = sha256.convert([...h.bytes, ...suffixe]);
    }
    return h.toString();
  }

  /// Fabrique un vérificateur propre à CET appareil.
  static Map<String, String> creerVerificateur(String secret) {
    final rnd = Random.secure();
    final sel = base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    return {'sel': sel, 'empreinte': _deriver(secret, sel)};
  }

  /// Vérifie un secret contre un vérificateur rangé sur l'appareil.
  static bool verifierVerificateur(String secret, String? sel, String? empreinte) {
    if (sel == null || empreinte == null) return false;
    return _deriver(secret, sel) == empreinte;
  }

  /// Empreinte d'un code de badge — pour retrouver un employé sans ranger le
  /// code lui-même. Un badge fait 256 bits : aucun risque d'inversion.
  static String indexer(String valeur) =>
      sha256.convert(utf8.encode('idx|$valeur')).toString();
}

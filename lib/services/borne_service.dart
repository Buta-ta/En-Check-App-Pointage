import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'local_database.dart';
import 'supabase_service.dart';

// ═══════════════════════════════════════════════════════════
// 🖥️ SERVICE BORNE — CONTRAT ÉTAPE 3 (26/10/2026)
// ═══════════════════════════════════════════════════════════
//
// L'autorisation de borne est créée par un superadmin (MFA) côté Admin :
// il communique ONCE l'identifiant appareil (1–128 car.) et le secret
// `bs1_…` à l'opérateur de la tablette. Cette classe :
//
//  1. Authentifie la borne : encheck_borne_authentifier(device_id, secret)
//     → jeton_borne `bk1_…` (bail ≤ 24 h). Une nouvelle authentification
//     invalide les anciens baux de CETTE borne. L'entreprise est imposée
//     par le serveur — la borne ne la choisit pas.
//  2. Télécharge le SNAPSHOT COMPLET du personnel :
//     encheck_borne_personnel → {employes, embeddings, maj, cache_expire_le}.
//     Le cache est REMPLACÉ intégralement — jamais fusionné : les sorties
//     d'effectif, révocations et suppressions ne doivent pas survivre.
//  3. Gère l'expiration du cache (cache_expire_le), le recul d'horloge
//     local, et la purge (changement d'appareil/d'entreprise, sortie du
//     mode borne, refus du serveur). JAMAIS de repli sur les anciens
//     accès (visage_lister v1, lectures directes) en cas d'erreur.
//
// ⚠️ Le secret bs1_ vit dans le COFFRE SÉCURISÉ de l'OS
// (flutter_secure_storage) — jamais les préférences ordinaires, jamais
// les logs, jamais une URL. Le jeton bk1_ est un porteur : non persisté
// dans les préférences (mémoire vive + Hive fermé, renouvelé par le secret).
// ⚠️ Un jeton borne ne permet PAS de pointer comme un salarié.
// ═══════════════════════════════════════════════════════════

class BorneService {
  static const _storage = FlutterSecureStorage();
  static const _kDeviceId = 'encheck_borne_device_id';
  static const _kSecret = 'encheck_borne_secret'; // coffre sécurisé OS
  static const _boxBorne = 'encheck_borne_local'; // jeton + métadonnées
  static const _kJeton = 'jeton_borne';
  static const _kJetonExpireLe = 'jeton_expire_le';
  static const _kCacheExpireLe = 'cache_expire_le';
  static const _kMajServeur = 'maj_serveur';
  static const _kSyncLocal = 'sync_locale';
  static const _kEnterprise = 'enterprise_id';

  static String? _jetonBorne;

  /// Jeton borne en mémoire (`bk1_…`) — jamais dans un log.
  static String? get jetonBorne => _jetonBorne;

  static Future<Box> _box() async => Hive.openBox(_boxBorne);

  // ─────────────────────────────────────────────────────────
  // 🔑 AUTHENTIFICATION DE BORNE
  // ─────────────────────────────────────────────────────────

  /// Authentifie la borne avec l'identifiant appareil et le secret `bs1_`
  /// provisionnés par le superadmin. Le secret est ensuite conservé dans le
  /// coffre sécurisé pour les renouvellements de bail.
  ///
  /// Retourne `{ok:true, jeton_borne, enterprise_id, expire_le}` ou
  /// `{ok:false, erreur}` (message honnête, jamais le secret).
  static Future<Map<String, dynamic>> authentifier({
    required String deviceId,
    required String secret,
  }) async {
    try {
      final reponse = await SupabaseService.client.rpc(
        'encheck_borne_authentifier',
        params: {
          'p_device_id': deviceId.trim(),
          'p_secret': secret.trim(),
        },
      );
      final brut = reponse is String ? jsonDecode(reponse) : reponse;
      if (brut is! Map) {
        return {'ok': false, 'erreur': 'Réponse du serveur illisible.'};
      }
      if (brut['ok'] != true) {
        // Refus générique côté serveur (secret/appareil inconnu, révoqué,
        // expiré, entreprise inactive) : on affiche tel quel, sans devinettes.
        return {
          'ok': false,
          'erreur': 'Borne refusée : ${brut['raison'] ?? 'identifiants invalides'}',
        };
      }

      final jeton = (brut['jeton_borne'] ?? '') as String;
      if (jeton.isEmpty) {
        return {'ok': false, 'erreur': 'Borne refusée : jeton absent.'};
      }

      // ✅ Succès : jeton en mémoire + Hive fermé ; secret dans le coffre OS.
      _jetonBorne = jeton;
      final box = await _box();
      await box.put(_kJeton, jeton);
      await box.put(_kJetonExpireLe, brut['expire_le']);
      await box.put(_kEnterprise, brut['enterprise_id']);
      await _storage.write(key: _kDeviceId, value: deviceId.trim());
      await _storage.write(key: _kSecret, value: secret.trim());

      final expire = DateTime.tryParse('${brut['expire_le']}');
      return {
        'ok': true,
        'jeton_borne': jeton,
        'enterprise_id': brut['enterprise_id'],
        'expire_le': brut['expire_le'],
        'expire_valide': expire != null &&
            DateTime.now().toUtc().isBefore(expire),
      };
    } catch (e) {
      // Erreur technique : jamais transformée en succès.
      return {
        'ok': false,
        'erreur': 'Connexion au serveur impossible : $e',
      };
    }
  }

  /// Un secret a-t-il déjà été provisionné sur cette tablette ?
  static Future<bool> aUnSecret() async {
    final secret = await _storage.read(key: _kSecret);
    return secret != null && secret.isNotEmpty;
  }

  /// Un bail existe-t-il encore (en mémoire ou dans le Hive fermé) ?
  static Future<bool> aUnBailValide() async {
    if (_jetonBorne != null && _jetonBorne!.isNotEmpty) {
      final box = await _box();
      final expire = DateTime.tryParse('${box.get(_kJetonExpireLe) ?? ''}');
      if (expire == null || DateTime.now().toUtc().isBefore(expire)) return true;
    }
    // Recharge depuis le Hive fermé (rechargement de page).
    final box = await _box();
    final jeton = box.get(_kJeton) as String?;
    if (jeton == null || jeton.isEmpty) return false;
    final expire = DateTime.tryParse('${box.get(_kJetonExpireLe) ?? ''}');
    if (expire != null && !DateTime.now().toUtc().isBefore(expire)) return false;
    _jetonBorne = jeton;
    return true;
  }

  /// Renouvelle le bail avec le secret du coffre sécurisé (si présent).
  static Future<Map<String, dynamic>> renouvelerBail() async {
    final deviceId = await _storage.read(key: _kDeviceId);
    final secret = await _storage.read(key: _kSecret);
    if (deviceId == null || secret == null || deviceId.isEmpty || secret.isEmpty) {
      return {
        'ok': false,
        'erreur': 'Secret de borne absent du coffre sécurisé — '
            'redemandez-le au superadmin (il est présenté une seule fois).',
      };
    }
    return authentifier(deviceId: deviceId, secret: secret);
  }

  // ─────────────────────────────────────────────────────────
  // 📦 SNAPSHOT COMPLET DU PERSONNEL
  // ─────────────────────────────────────────────────────────

  /// Télécharge le snapshot complet et REMPLACE intégralement le cache local
  /// (jamais de fusion). Contrats : p_maj_depuis ignoré côté serveur, volume
  /// maximal 1000 employés / 2000 enrôlements (refus `volume_non_pris_en_charge`,
  /// jamais de troncature), expiration `cache_expire_le`.
  ///
  /// Retourne `{ok:true, employes, embeddings}` ou `{ok:false, erreur}`.
  static Future<Map<String, dynamic>> synchroniserPersonnel() async {
    if (!await aUnBailValide()) {
      final r = await renouvelerBail();
      if (r['ok'] != true) {
        return {
          'ok': false,
          'erreur': r['erreur'] ?? 'Borne non authentifiée.',
        };
      }
    }
    try {
      final reponse = await SupabaseService.client.rpc(
        'encheck_borne_personnel',
        params: {'p_jeton_borne': _jetonBorne, 'p_maj_depuis': null},
      );
      final brut = reponse is String ? jsonDecode(reponse) : reponse;
      if (brut is! Map) {
        return {'ok': false, 'erreur': 'Réponse du personnel illisible.'};
      }
      if (brut['ok'] != true) {
        final raison = brut['raison'] as String?;
        // Refus explicite du serveur : PURGE du cache (contrat) et message
        // honnête — aucun repli sur les anciens accès.
        await purgerCache();
        return {
          'ok': false,
          'erreur': raison == 'volume_non_pris_en_charge'
              ? 'Effectif trop important pour le cache borne (max 1000 '
                  'employés / 2000 enrôlements) — contactez l\'équipe Admin.'
              : 'Personnel refusé : ${raison ?? 'raison inconnue'}',
        };
      }

      final employes = (brut['employes'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final embeddings = (brut['embeddings'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Défense en profondeur : jamais de troncature, refus explicite.
      if (employes.length > 1000 || embeddings.length > 2000) {
        await purgerCache();
        return {
          'ok': false,
          'erreur': 'Effectif trop important pour le cache borne (max 1000 '
              'employés / 2000 enrôlements) — contactez l\'équipe Admin.',
        };
      }

      // 🔁 REMPLACEMENT INTÉGRAL du cache (identités + embeddings).
      await LocalDatabase.remplacerCachePersonnel(employes, embeddings);

      // Horodatage : `maj` = date serveur du snapshot (pas un curseur delta).
      // Le recul d'horloge local est détecté plus tard via ces deux dates.
      final box = await _box();
      await box.put(_kMajServeur, brut['maj']);
      await box.put(_kCacheExpireLe, brut['cache_expire_le']);
      await box.put(_kSyncLocal, DateTime.now().toUtc().toIso8601String());
      await box.put(_kEnterprise, brut['enterprise_id']);

      return {'ok': true, 'employes': employes, 'embeddings': embeddings};
    } catch (e) {
      return {
        'ok': false,
        'erreur': 'Connexion au serveur impossible : $e',
      };
    }
  }

  // ─────────────────────────────────────────────────────────
  // ⏳ VALIDITÉ / EXPIRATION / PURGE
  // ─────────────────────────────────────────────────────────

  /// Le cache snapshot est-il encore exploitable ?
  /// - expiré selon `cache_expire_le` → non ;
  /// - recul de l'horloge locale détecté (date locale < date de synchro) → non ;
  /// - pas de synchro connue → non.
  static Future<bool> cacheValide() async {
    final box = await _box();
    final expire = DateTime.tryParse('${box.get(_kCacheExpireLe) ?? ''}');
    final syncLocal = DateTime.tryParse('${box.get(_kSyncLocal) ?? ''}');
    if (expire == null || syncLocal == null) return false;
    final maintenant = DateTime.now().toUtc();
    if (maintenant.isBefore(syncLocal)) return false; // recul d'horloge
    return maintenant.isBefore(expire);
  }

  /// Date d'expiration du cache snapshot (null si jamais synchronisé).
  static Future<DateTime?> getCacheExpireLe() async {
    final box = await _box();
    return DateTime.tryParse('${box.get(_kCacheExpireLe) ?? ''}');
  }

  /// Entreprise rattachée à la borne (imposée par le serveur).
  static Future<String?> getEnterpriseId() async {
    final box = await _box();
    return box.get(_kEnterprise) as String?;
  }

  /// Purge complète du cache borne (identités du snapshot + embeddings +
  /// jeton). Les pointages en attente de rejeu ne sont JAMAIS touchés.
  static Future<void> purgerCache() async {
    _jetonBorne = null;
    final box = await _box();
    await box.delete(_kJeton);
    await box.delete(_kJetonExpireLe);
    await box.delete(_kCacheExpireLe);
    await box.delete(_kSyncLocal);
    await box.delete(_kMajServeur);
    await LocalDatabase.purgerCacheBorne();
  }

  /// Sortie du mode borne / changement d'appareil ou d'entreprise.
  static Future<void> seDeconnecter() async {
    await purgerCache();
  }
}
}

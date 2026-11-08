import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

typedef RpcAnnoncesAccueil = Future<dynamic> Function(String enterpriseId);

const _typesAnnonceAccueil = <String>{'image', 'gif', 'video'};

DateTime? _parserDateAnnonce(Object? value) {
  if (value == null) return null;
  var valueText = value.toString().trim();
  if (valueText.contains(' ') && !valueText.contains('T')) {
    valueText = valueText.replaceFirst(' ', 'T');
  }
  if (RegExp(r'[+-]\d{2}$').hasMatch(valueText)) valueText = '$valueText:00';
  return DateTime.tryParse(valueText);
}

/// Média publié par l'écran « Annonces d'accueil » de l'application Admin.
class AnnonceAccueil {
  const AnnonceAccueil({
    required this.id,
    required this.type,
    required this.url,
    required this.dureeAffichageMs,
    required this.ordrePublication,
    required this.updatedAt,
  });

  final String id;
  final String type;
  final String url;
  final int dureeAffichageMs;
  final int ordrePublication;
  final DateTime? updatedAt;

  String get signature =>
      '$id|$type|$url|$dureeAffichageMs|${updatedAt?.toIso8601String() ?? ''}';

  /// Le paramètre de version contourne le cache HTTP si l'Admin remplace un
  /// fichier à la même URL et met à jour `updated_at`.
  String get urlVersionnee {
    if (updatedAt == null) return url;
    final uri = Uri.parse(url);
    return uri
        .replace(queryParameters: {
          ...uri.queryParameters,
          'v': updatedAt!.millisecondsSinceEpoch.toString(),
        })
        .toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'url': url,
        'duree_affichage_ms': dureeAffichageMs,
        'ordre_publication': ordrePublication,
        'updated_at': updatedAt?.toIso8601String(),
      };

  static AnnonceAccueil? fromJson(Object? value, {int index = 0}) {
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    final id = data['id']?.toString().trim() ?? '';
    final type = data['type']?.toString().trim().toLowerCase() ?? '';
    final url = data['url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    final rawDuration = data['duree_affichage_ms'];
    final duration = rawDuration is num
        ? rawDuration.toInt()
        : int.tryParse(rawDuration?.toString() ?? '');

    if (id.isEmpty ||
        !_typesAnnonceAccueil.contains(type) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        duration == null ||
        duration <= 0) {
      return null;
    }

    final ordreRaw = data['ordre_publication'];
    final ordre = ordreRaw is num
        ? ordreRaw.toInt()
        : int.tryParse(ordreRaw?.toString() ?? '') ?? index;
    final updatedAt = _parserDateAnnonce(data['updated_at']);
    return AnnonceAccueil(
      id: id,
      type: type,
      url: url,
      // Le contrat Admin publie des durées de 3 à 15 secondes. Borner
      // l'affichage côté client protège aussi d'une valeur accidentelle.
      dureeAffichageMs: duration.clamp(3000, 15000).toInt(),
      ordrePublication: ordre,
      updatedAt: updatedAt,
    );
  }
}

/// Lecture de la RPC publique et cache des seules métadonnées par entreprise.
/// Les médias restent chargés à la demande depuis leurs URLs publiques HTTPS.
class AnnoncesAccueilService {
  AnnoncesAccueilService({RpcAnnoncesAccueil? rpc}) : _rpc = rpc ?? _appelerRpc;

  final RpcAnnoncesAccueil _rpc;

  static Future<dynamic> _appelerRpc(String enterpriseId) =>
      SupabaseService.client.rpc(
        'encheck_accueil_publicites',
        params: {'p_enterprise_id': enterpriseId},
      );

  static String _cacheKey(String enterpriseId) =>
      'encheck_annonces_accueil_$enterpriseId';

  Future<List<AnnonceAccueil>?> charger(String enterpriseId) async {
    try {
      final response = await _rpc(enterpriseId);
      final decoded = response is String ? jsonDecode(response) : response;
      if (decoded is! Map) return null;
      final payload = Map<String, dynamic>.from(decoded);

      // Une entreprise inactive/inconnue est un résultat valide sans médias.
      if (payload['ok'] != true) return <AnnonceAccueil>[];
      final returnedEnterprise = payload['entreprise_id']?.toString();
      if (returnedEnterprise != null &&
          returnedEnterprise.toLowerCase() != enterpriseId.toLowerCase()) {
        return null;
      }
      final rows = payload['publicites'];
      if (rows is! List) return null;

      final annonces = <AnnonceAccueil>[];
      for (var index = 0; index < rows.length; index++) {
        final annonce = AnnonceAccueil.fromJson(rows[index], index: index);
        if (annonce != null) annonces.add(annonce);
      }
      // La RPC a déjà trié la campagne : garder exactement l'ordre reçu.
      return annonces;
    } catch (_) {
      // Réseau, RPC absente ou réponse illisible : le caller conserve le cache
      // et l'accueil continue d'afficher sa photo locale par défaut.
      return null;
    }
  }

  Future<List<AnnonceAccueil>?> chargerCache(String enterpriseId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_cacheKey(enterpriseId));
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return null;
      final annonces = <AnnonceAccueil>[];
      for (var index = 0; index < decoded.length; index++) {
        final annonce = AnnonceAccueil.fromJson(decoded[index], index: index);
        if (annonce != null) annonces.add(annonce);
      }
      return annonces;
    } catch (_) {
      return null;
    }
  }

  Future<void> enregistrerCache(
    String enterpriseId,
    List<AnnonceAccueil> annonces,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _cacheKey(enterpriseId),
        jsonEncode(annonces.map((annonce) => annonce.toJson()).toList()),
      );
    } catch (_) {
      // Le cache améliore le mode hors-ligne mais ne doit jamais bloquer
      // l'identification ou le pointage.
    }
  }
}

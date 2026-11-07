// lib/services/motif_service.dart
// ═══════════════════════════════════════════════════════════
// 🧵 MOTIFS D'INTERFACE — texture choisie pour l'application
// ═══════════════════════════════════════════════════════════
//
//  Le bouton Paramètres ouvre l'écran Apparence. Le choix du motif est
//  enregistré sur l'appareil et appliqué immédiatement. Aucune provenance
//  culturelle n'est affichée sans source vérifiée.
//
//  Les images déjà embarquées dans assets/motifs/ sont utilisées telles
//  quelles : aucune analyse ni recoloration à l'exécution.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'checklist_service.dart';

class MotifCulturel {
  final String id;
  final String nom;
  final String asset;

  /// Extrait horizontal d'UNE rangée du même textile, pour l'accueil.
  /// Ces petits WebP sont des crops optimisés, jamais de nouveaux dessins.
  final String friseAsset;
  final double friseRatio;

  final Color couleurBouton;
  final Color couleurAccent;

  /// Teinte douce pour les cartes (l'identité du motif, en retenue).
  final Color couleurTint;

  const MotifCulturel({
    required this.id,
    required this.nom,
    required this.asset,
    required this.friseAsset,
    required this.friseRatio,
    required this.couleurBouton,
    required this.couleurAccent,
    required this.couleurTint,
  });

  /// Texture géométrique disponible, identifiant historique conservé.
  static const raphia = MotifCulturel(
    id: 'raphia',
    nom: 'Motif textile 1',
    asset: 'assets/motifs/raphia.webp',
    friseAsset: 'assets/motifs/frises/raphia.webp',
    friseRatio: 4 / 3,
    couleurBouton: Color(0xFF3D2B1F),
    couleurAccent: Color(0xFFC98A2B),
    couleurTint: Color(0xFFF7EFE0),
  );

  /// Texture géométrique disponible, identifiant historique conservé.
  static const adinkra = MotifCulturel(
    id: 'adinkra',
    nom: 'Motif textile 2',
    asset: 'assets/motifs/adinkra.webp',
    friseAsset: 'assets/motifs/frises/adinkra.webp',
    friseRatio: 400 / 95,
    couleurBouton: Color(0xFF214348),
    couleurAccent: Color(0xFFB4593A),
    couleurTint: Color(0xFFD0DEDD),
  );

  /// Texture géométrique disponible, identifiant historique conservé.
  static const bogolan = MotifCulturel(
    id: 'bogolan',
    nom: 'Motif textile 3',
    asset: 'assets/motifs/bogolan.webp',
    friseAsset: 'assets/motifs/frises/bogolan.webp',
    friseRatio: 400 / 75,
    couleurBouton: Color(0xFF2E2118),
    couleurAccent: Color(0xFF8B5E34),
    couleurTint: Color(0xFFF2EADD),
  );

  /// Texture géométrique disponible, identifiant historique conservé.
  static const zoulou = MotifCulturel(
    id: 'zoulou',
    nom: 'Motif textile 4',
    asset: 'assets/motifs/zoulou.webp',
    friseAsset: 'assets/motifs/frises/zoulou.webp',
    friseRatio: 2.4,
    couleurBouton: Color(0xFF1F4E4A),
    couleurAccent: Color(0xFF2E7D6B),
    couleurTint: Color(0xFFE9F1EE),
  );

  static const List<MotifCulturel> tous = [raphia, adinkra, bogolan, zoulou];
  static const String idDefaut = 'adinkra';

  /// Retombe sur le motif d'interface par défaut si l'id est inconnu.
  static MotifCulturel parId(String? id) {
    for (final motif in tous) {
      if (motif.id == id) return motif;
    }
    return adinkra;
  }
}

class MotifService {
  static const String _cle = 'motif_culturel_id';

  /// Motif actuellement affiché — les widgets écoutent ce notificateur
  /// pour se repeindre dès que l'entreprise change de motif.
  static final ValueNotifier<MotifCulturel> actif =
      ValueNotifier<MotifCulturel>(MotifCulturel.adinkra);

  /// Charge le motif enregistré sur l'appareil.
  static Future<void> charger() async {
    final prefs = await SharedPreferences.getInstance();
    actif.value = MotifCulturel.parId(prefs.getString(_cle));
  }

  /// Enregistre le motif choisi par l'entreprise.
  static Future<void> enregistrer(MotifCulturel motif) async {
    actif.value = motif;
    // 🧭 Checklist de démarrage : le motif culturel est choisi.
    ChecklistService.marquerMotifChoisi();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, motif.id);
  }
}

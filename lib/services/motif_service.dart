// lib/services/motif_service.dart
// ═══════════════════════════════════════════════════════════
// 🧵 MOTIFS CULTURELS — un textile africain choisi par l'entreprise
// ═══════════════════════════════════════════════════════════
//
//  Le bouton ⚙️ Paramètres de l'accueil ouvre le panneau « Motif culturel ».
//  Le RAPHIA (tissu Kuba) est le motif PAR DÉFAUT. Le choix est enregistré
//  sur l'appareil (shared_preferences) et appliqué immédiatement.
//
//  Les images sont les vraies étoffes de l'app En-Check Admin
//  (public/images), copiées dans assets/motifs/.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'checklist_service.dart';

class MotifCulturel {
  final String id;
  final String nom;
  final String asset;
  final Color couleurBouton;
  final Color couleurAccent;

  /// Teinte douce pour les cartes (l'identité du motif, en retenue).
  final Color couleurTint;

  /// Pays d'origine du textile (affiché dans le cadre latéral).
  final String pays;

  /// Peuple à qui appartient le motif (affiché dans le cadre latéral).
  final String peuple;

  const MotifCulturel({
    required this.id,
    required this.nom,
    required this.asset,
    required this.couleurBouton,
    required this.couleurAccent,
    required this.couleurTint,
    required this.pays,
    required this.peuple,
  });

  /// 🧺 Raphia tressé (Kuba) — LE MOTIF PAR DÉFAUT.
  static const raphia = MotifCulturel(
    id: 'raphia',
    nom: 'Raphia',
    asset: 'assets/motifs/raphia.webp',
    couleurBouton: Color(0xFF3D2B1F),
    couleurAccent: Color(0xFFC98A2B),
    couleurTint: Color(0xFFF7EFE0),
    pays: 'Congo',
    peuple: 'Kuba',
  );

  /// Adinkra peint (Ghana) — l'univers « temps et travail ».
  static const adinkra = MotifCulturel(
    id: 'adinkra',
    nom: 'Adinkra',
    asset: 'assets/motifs/adinkra.webp',
    couleurBouton: Color(0xFF1B2A4A),
    couleurAccent: Color(0xFFB4593A),
    couleurTint: Color(0xFFF4EAE3),
    pays: 'Ghana',
    peuple: 'Akan',
  );

  /// Bogolan (Mali) — la boue et le coton.
  static const bogolan = MotifCulturel(
    id: 'bogolan',
    nom: 'Bogolan',
    asset: 'assets/motifs/bogolan.webp',
    couleurBouton: Color(0xFF2E2118),
    couleurAccent: Color(0xFF8B5E34),
    couleurTint: Color(0xFFF2EADD),
    pays: 'Mali',
    peuple: 'Bambara',
  );

  /// Perles zoulou — géométries colorées.
  static const zoulou = MotifCulturel(
    id: 'zoulou',
    nom: 'Zoulou',
    asset: 'assets/motifs/zoulou.webp',
    couleurBouton: Color(0xFF1F4E4A),
    couleurAccent: Color(0xFF2E7D6B),
    couleurTint: Color(0xFFE9F1EE),
    pays: 'Afrique du Sud',
    peuple: 'Zoulou',
  );

  static const List<MotifCulturel> tous = [raphia, adinkra, bogolan, zoulou];
  static const String idDefaut = 'raphia';

  /// Retombe toujours sur le Raphia si l'id enregistré est inconnu.
  static MotifCulturel parId(String? id) {
    for (final motif in tous) {
      if (motif.id == id) return motif;
    }
    return raphia;
  }
}

/// « Motifs culturels du Congo » / « Motifs culturels d'Afrique du Sud »…
String titreMotifsCulturels(String pays) {
  final debutVoyelle = RegExp(r'^[AEIOUYÀÂÄÉÈÊËÎÏÔÖÙÛÜ]', caseSensitive: false);
  final particule = debutVoyelle.hasMatch(pays) ? "d'" : 'du ';
  return 'Motifs culturels $particule$pays';
}

class MotifService {
  static const String _cle = 'motif_culturel_id';

  /// Motif actuellement affiché — les widgets écoutent ce notificateur
  /// pour se repeindre dès que l'entreprise change de motif.
  static final ValueNotifier<MotifCulturel> actif =
      ValueNotifier<MotifCulturel>(MotifCulturel.raphia);

  /// Charge le motif enregistré sur l'appareil (Raphia par défaut).
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

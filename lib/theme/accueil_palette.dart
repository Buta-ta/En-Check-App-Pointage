import 'package:flutter/material.dart';

import '../services/motif_service.dart';

/// Couleurs de l'accueil, mesurées sur la maquette du 5 novembre.
///
/// Les neutres (papier, cartes, textes) restent identiques d'un motif à
/// l'autre. Les accents suivent le textile choisi dans Paramètres, en clair
/// comme en sombre. Aucune analyse d'image n'est faite à l'exécution : les
/// correspondances sont fixes, déterministes et ne coûtent aucun calcul.
class AccueilPalette {
  const AccueilPalette({
    required this.fond,
    required this.surface,
    required this.carteDouce,
    required this.texte,
    required this.texteFort,
    required this.texteSecondaire,
    required this.texteTertiaire,
    required this.bordure,
    required this.filet,
    required this.navFond,
    required this.navInactif,
    required this.plaque,
    required this.plaqueTexte,
    required this.primaire,
    required this.surPrimaire,
    required this.cerclePrimaire,
    required this.iconePrimaire,
    required this.cercleDoux,
    required this.iconeDouce,
    required this.lien,
    required this.navActif,
  });

  final Color fond;
  final Color surface;
  final Color carteDouce;
  final Color texte;
  final Color texteFort;
  final Color texteSecondaire;
  final Color texteTertiaire;
  final Color bordure;
  final Color filet;
  final Color navFond;
  final Color navInactif;
  final Color plaque;
  final Color plaqueTexte;

  /// Carte Départ et accents principaux : cette couleur change avec le motif.
  final Color primaire;
  final Color surPrimaire;
  final Color cerclePrimaire;
  final Color iconePrimaire;
  final Color cercleDoux;
  final Color iconeDouce;
  final Color lien;
  final Color navActif;

  static const _neutresClairs = AccueilPalette(
    fond: Color(0xFFF5F2E9),
    surface: Color(0xFFFFFFFF),
    carteDouce: Color(0xFFF6F4ED),
    texte: Color(0xFF1D1C1B),
    texteFort: Color(0xFF111110),
    texteSecondaire: Color(0xFF43423E),
    texteTertiaire: Color(0xFF4D4D4E),
    bordure: Color(0xFFCBC8BF),
    filet: Color(0xFFE6E2DA),
    navFond: Color(0xFFF9F7F0),
    navInactif: Color(0xFF5E5E5A),
    plaque: Color(0xFFECE7DC),
    plaqueTexte: Color(0xFF615E57),
    primaire: Color(0xFF3A686D),
    surPrimaire: Color(0xFFF7FBFA),
    cerclePrimaire: Color(0xFFEAE4D4),
    iconePrimaire: Color(0xFF233D3F),
    cercleDoux: Color(0xFFD0DEDD),
    iconeDouce: Color(0xFF203E42),
    lien: Color(0xFF2D4B4C),
    navActif: Color(0xFF214348),
  );

  static const _neutresSombres = AccueilPalette(
    fond: Color(0xFF121312),
    surface: Color(0xFF1D1E1C),
    carteDouce: Color(0xFF222320),
    texte: Color(0xFFEEEBE4),
    texteFort: Color(0xFFF5F2EC),
    texteSecondaire: Color(0xFFC2BEB5),
    texteTertiaire: Color(0xFFB5B1A8),
    bordure: Color(0xFF4A4842),
    filet: Color(0xFF2C2C29),
    navFond: Color(0xFF181917),
    navInactif: Color(0xFFA7A39A),
    plaque: Color(0xFF2A2A27),
    plaqueTexte: Color(0xFFBDB8AE),
    primaire: Color(0xFF3D6F74),
    surPrimaire: Color(0xFFF7FBFA),
    cerclePrimaire: Color(0xFFE6E0D0),
    iconePrimaire: Color(0xFF233D3F),
    cercleDoux: Color(0xFF2C4245),
    iconeDouce: Color(0xFFCFE4E2),
    lien: Color(0xFF9FCBC6),
    navActif: Color(0xFFA3CFCA),
  );

  /// Accents clairs par identifiant de motif. L'Adinkra bleu-vert est la
  /// référence de la maquette ; les autres reprennent les teintes des étoffes.
  static const _accentsClairs = <String, List<Color>>{
    'adinkra': [
      Color(0xFF3A686D), Color(0xFFF7FBFA), Color(0xFFEAE4D4),
      Color(0xFF233D3F), Color(0xFFD0DEDD), Color(0xFF203E42),
      Color(0xFF2D4B4C), Color(0xFF214348),
    ],
    'raphia': [
      Color(0xFF6B4E36), Color(0xFFFCF8F3), Color(0xFFF1E3C8),
      Color(0xFF3D2B1F), Color(0xFFE7DACB), Color(0xFF3D2B1F),
      Color(0xFF6A4A2E), Color(0xFF4A3424),
    ],
    'bogolan': [
      Color(0xFF7A4A30), Color(0xFFFCF7F3), Color(0xFFF0E0CC),
      Color(0xFF3A2316), Color(0xFFEAD6C8), Color(0xFF4A2B1A),
      Color(0xFF7A4628), Color(0xFF5A331E),
    ],
    'zoulou': [
      Color(0xFF2F6B5F), Color(0xFFF6FBF9), Color(0xFFF0E2CF),
      Color(0xFF1C3F38), Color(0xFFCFE2DB), Color(0xFF1B4A41),
      Color(0xFF245A4F), Color(0xFF1D4F45),
    ],
  };

  static const _accentsSombres = <String, List<Color>>{
    'adinkra': [
      Color(0xFF3D6F74), Color(0xFFF7FBFA), Color(0xFFE6E0D0),
      Color(0xFF233D3F), Color(0xFF2C4245), Color(0xFFCFE4E2),
      Color(0xFF9FCBC6), Color(0xFFA3CFCA),
    ],
    'raphia': [
      Color(0xFF71533A), Color(0xFFFCF8F3), Color(0xFFEEDFC2),
      Color(0xFF3D2B1F), Color(0xFF42362B), Color(0xFFEBD9C2),
      Color(0xFFD9B98F), Color(0xFFDDBF97),
    ],
    'bogolan': [
      Color(0xFF7E4F34), Color(0xFFFCF7F3), Color(0xFFECDCC6),
      Color(0xFF3A2316), Color(0xFF46322A), Color(0xFFEDD3C0),
      Color(0xFFE0AE8A), Color(0xFFE3B595),
    ],
    'zoulou': [
      Color(0xFF327265), Color(0xFFF6FBF9), Color(0xFFECDDC9),
      Color(0xFF1C3F38), Color(0xFF27443E), Color(0xFFCBE6DD),
      Color(0xFF97D0C2), Color(0xFF9DD3C6),
    ],
  };

  static AccueilPalette pour(MotifCulturel motif, bool sombre) {
    final base = sombre ? _neutresSombres : _neutresClairs;
    final accents = (sombre ? _accentsSombres : _accentsClairs)[motif.id] ??
        (sombre ? _accentsSombres : _accentsClairs)['adinkra']!;
    return AccueilPalette(
      fond: base.fond,
      surface: base.surface,
      carteDouce: base.carteDouce,
      texte: base.texte,
      texteFort: base.texteFort,
      texteSecondaire: base.texteSecondaire,
      texteTertiaire: base.texteTertiaire,
      bordure: base.bordure,
      filet: base.filet,
      navFond: base.navFond,
      navInactif: base.navInactif,
      plaque: base.plaque,
      plaqueTexte: base.plaqueTexte,
      primaire: accents[0],
      surPrimaire: accents[1],
      cerclePrimaire: accents[2],
      iconePrimaire: accents[3],
      cercleDoux: accents[4],
      iconeDouce: accents[5],
      lien: accents[6],
      navActif: accents[7],
    );
  }
}

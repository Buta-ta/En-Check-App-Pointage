import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════
// 🎨 THÈME EN-CHECK (CORRIGÉ)
// ═══════════════════════════════════════════════════════════

class EnCheckTheme {
  static bool isDarkMode = false;

  static void toggleTheme() {
    isDarkMode = !isDarkMode;
  }

  // Couleurs statiques pour compatibilité avec l'ancien code
  // Ces couleurs sont utilisées directement (EnCheckColors.terreChaude)
  // Elles représentent le thème clair par défaut
  static const Color sableClair = Color(0xFFE5D4C0);
  static const Color sableDore = Color(0xFFC4A574);
  static const Color brunProfond = Color(0xFF3D2B1F);
  static const Color noirElegant = Color(0xFF1C1C1C);
  static const Color terreChaude = Color(0xFF8B6914);
  static const Color orDoux = Color(0xFFD4AF37);
  static const Color blanc = Color(0xFFFFFBF5);
  static const Color gris = Color(0xFF9E9E9E);
  static const Color succes = Color(0xFF4A7C59);
  static const Color erreur = Color(0xFF9B2C2C);
}

// Classe utilitaire pour les couleurs statiques
// C'est ce que ton code utilise actuellement (EnCheckColors.terreChaude)
class EnCheckColors {
  static const Color sableClair = Color(0xFFE5D4C0);
  static const Color sableDore = Color(0xFFC4A574);
  static const Color brunProfond = Color(0xFF3D2B1F);
  static const Color noirElegant = Color(0xFF1C1C1C);
  static const Color terreChaude = Color(0xFF8B6914);
  static const Color orDoux = Color(0xFFD4AF37);
  static const Color blanc = Color(0xFFFFFBF5);
  static const Color gris = Color(0xFF9E9E9E);
  static const Color succes = Color(0xFF4A7C59);
  static const Color erreur = Color(0xFF9B2C2C);
}

class EnCheckTextStyles {
  static const TextStyle titrePrincipal = TextStyle(
    color: EnCheckColors.brunProfond,
    fontSize: 36,
    fontWeight: FontWeight.w300,
    letterSpacing: 8,
  );

  static const TextStyle titreSecondaire = TextStyle(
    color: EnCheckColors.terreChaude,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 3,
  );

  static const TextStyle grosChiffres = TextStyle(
    color: EnCheckColors.brunProfond,
    fontSize: 44,
    fontWeight: FontWeight.w200,
    letterSpacing: 2,
  );

  static const TextStyle texteNormal = TextStyle(
    color: EnCheckColors.brunProfond,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle texteBouton = TextStyle(
    color: EnCheckColors.blanc,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 2,
  );
}

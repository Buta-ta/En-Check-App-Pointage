// lib/screens/welcome_screen.dart
// ═══════════════════════════════════════════════════════════
// 🏠 ACCUEIL — code entreprise (page 1 de la refonte design)
// ═══════════════════════════════════════════════════════════
//
//  MAQUETTE VALIDÉE le 27/10 : frise raphia (motif par défaut) en haut,
//  plaque logo « En-Check — On gère ! », carte CODE ENTREPRISE, bouton
//  « Se connecter », modes appareil (privé / kiosque), ligne technique.
//  Le bouton ⚙️ ouvre le panneau « Motif culturel » (Raphia, Adinkra,
//  Bogolan, Zoulou — Raphia = défaut).
//
//  ⚠️ La logique de connexion (_verifierCode) est inchangée : lecture du
//  code dans `enterprises`, sauvegarde des modules, puis PointageScreen.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/appareil_service.dart';
import '../services/motif_service.dart';
import '../services/supabase_service.dart';
import '../widgets/frise_motif.dart';
import '../widgets/panneau_motif.dart';
import '../widgets/logo_empreinte.dart';
import 'pointage_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  // 📱 Mode de l'appareil : privé (défaut) ou kiosque (borne).
  String _modeAppareil = AppareilService.prive;

  @override
  void initState() {
    super.initState();
    _chargerPreferences();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _chargerPreferences() async {
    await MotifService.charger();
    final mode = await AppareilService.mode();
    if (mounted) {
      setState(() => _modeAppareil = mode);
    }
  }

  Future<void> _verifierCode() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    final code = _codeController.text.trim().toUpperCase();

    try {
      final response =
      await SupabaseService.client
          .from('enterprises')
          .select()
          .eq('code', code)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        final prefs = await SharedPreferences.getInstance();

        // Infos de base
        await prefs.setString('enterprise_id', response['id']);
        await prefs.setString('enterprise_name', response['name']);

        if (response['logo_url'] != null) {
          await prefs.setString('enterprise_logo', response['logo_url']);
        }
        if (response['matricule_prefix'] != null) {
          await prefs.setString('matricule_prefix', response['matricule_prefix']);
        }

        // 🔐 SAUVEGARDER LES MODULES
        await prefs.setBool('module_qr_scanner', response['module_qr_scanner'] ?? false);
        await prefs.setBool('module_photo_pointage', response['module_photo_pointage'] ?? false);
        await prefs.setBool('module_planning', response['module_planning'] ?? false);
        await prefs.setBool('module_retards', response['module_retards'] ?? false);

        // 🌍 NOUVEAU - Module geofencing
        await prefs.setBool('module_geolocalisation', response['module_geolocalisation'] ?? false);

        // 📷 NOUVEAU - Modules futurs (préparation)
        await prefs.setBool('module_reconnaissance_faciale', response['module_reconnaissance_faciale'] ?? false);
        await prefs.setBool('module_carte_temps_reel', response['module_carte_temps_reel'] ?? false);

        await prefs.setString('license_type', response['license_type'] ?? 'basic');

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PointageScreen()),
          );
        }
      } else {
        setState(() => _error = 'Code entreprise introuvable');
      }
    } catch (e) {
      // Dire « Erreur de connexion internet » pour un refus d'autorisation
      // envoyait l'administrateur vérifier sa connexion alors que le correctif
      // est un GRANT SQL côté Supabase. messageErreur() fait la distinction.
      setState(() => _error = SupabaseService.messageErreur(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _choisirModeAppareil(String mode) async {
    setState(() => _modeAppareil = mode);
    await AppareilService.definirMode(mode);
  }

  // ═══════════════════════════════════════════════════════════
  // 🎨 INTERFACE
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EnCheckColors.cremePapier,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Frise culturelle + bouton Paramètres ⚙️ ──
              Stack(
                children: [
                  ValueListenableBuilder<MotifCulturel>(
                    valueListenable: MotifService.actif,
                    builder: (context, motif, _) => FriseMotif(motif: motif),
                  ),
                  Positioned(
                    top: 12,
                    right: 16,
                    child: Material(
                      color: Colors.white.withOpacity(0.85),
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => ouvrirPanneauMotif(context),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.settings,
                            color: EnCheckColors.brunProfond,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Plaque logo « En-Check — On gère ! » ──
              Transform.translate(
                offset: const Offset(0, -46),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 26, 12),
                    decoration: BoxDecoration(
                      color: EnCheckColors.blanc,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LogoEmpreinte(taille: 64),
                        const SizedBox(width: 14),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'En-Check',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: EnCheckColors.brunProfond,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'On gère !',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: EnCheckColors.orFonce,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Carte CODE ENTREPRISE ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                  decoration: BoxDecoration(
                    color: EnCheckColors.blanc,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CODE ENTREPRISE',
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                          color: EnCheckColors.brunProfond,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _codeController,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 26,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w700,
                          color: EnCheckColors.brunProfond,
                        ),
                        decoration: InputDecoration(
                          hintText: 'NOVA-7K2',
                          hintStyle: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 24,
                            letterSpacing: 5,
                            fontWeight: FontWeight.w600,
                            color: EnCheckColors.gris.withOpacity(0.55),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF7F2EA),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          errorText: _error,
                          errorStyle: const TextStyle(
                            color: EnCheckColors.erreur,
                            fontSize: 13,
                          ),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _verifierCode(),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Veuillez entrer le code de votre entreprise pour configurer l'appareil.",
                        style: TextStyle(
                          fontSize: 12,
                          color: EnCheckColors.gris,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ValueListenableBuilder<MotifCulturel>(
                          valueListenable: MotifService.actif,
                          builder: (context, motif, _) => ElevatedButton(
                            onPressed: _loading ? null : _verifierCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: motif.couleurBouton,
                              foregroundColor: EnCheckColors.blanc,
                              disabledBackgroundColor:
                                  motif.couleurBouton.withOpacity(0.6),
                              elevation: 0,
                              side: BorderSide(
                                color: motif.couleurAccent.withOpacity(0.55),
                                width: 1.4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Se connecter',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Modes de l'appareil ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _chipMode(
                      icon: Icons.person_outline,
                      label: 'Mode privé',
                      actif: _modeAppareil == AppareilService.prive,
                      onTap: () =>
                          _choisirModeAppareil(AppareilService.prive),
                    ),
                    _chipMode(
                      icon: Icons.desktop_windows_outlined,
                      label: 'Mode kiosque',
                      actif: _modeAppareil == AppareilService.kiosque,
                      onTap: () =>
                          _choisirModeAppareil(AppareilService.kiosque),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // ── Ligne technique ──
              Text(
                'v1.0.0 • Chiffrement AES-256 • Serveur UE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  color: EnCheckColors.gris.withOpacity(0.9),
                  letterSpacing: 0.2,
                ),
              ),

              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipMode({
    required IconData icon,
    required String label,
    required bool actif,
    required VoidCallback onTap,
  }) {
    return Material(
      color: actif ? EnCheckColors.brunProfond : Colors.transparent,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: actif
                  ? EnCheckColors.orDoux
                  : EnCheckColors.brunProfond.withOpacity(0.35),
              width: 1.3,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: actif ? EnCheckColors.blanc : EnCheckColors.brunProfond,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color:
                      actif ? EnCheckColors.blanc : EnCheckColors.brunProfond,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

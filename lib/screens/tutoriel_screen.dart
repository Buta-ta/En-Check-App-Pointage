// lib/screens/tutoriel_screen.dart
// ═══════════════════════════════════════════════════════════
// 🧭 TUTORIEL — le parcours de première utilisation (3 écrans)
// ═══════════════════════════════════════════════════════════
//
//  Joué UNE SEULE FOIS par appareil (mémorisé), « Passer »
//  pour l'ignorer, et rejouable depuis Paramètres →
//  « Revoir le guide ». Photos des vraies personnes (scènes),
//  logo En-Check en haut, frise du motif culturel en page 3.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/checklist_service.dart';
import '../services/motif_service.dart';
import '../theme/app_theme.dart';
import '../widgets/frise_motif.dart';
import '../widgets/logo_empreinte.dart';

class TutorielScreen extends StatefulWidget {
  const TutorielScreen({super.key, this.relecture = false});

  /// Vrai quand on revient depuis Paramètres (« Revoir le guide »).
  final bool relecture;

  @override
  State<TutorielScreen> createState() => _TutorielScreenState();
}

class _TutorielScreenState extends State<TutorielScreen> {
  final _controleur = PageController();
  int _page = 0;
  String _nomEntreprise = '';

  @override
  void initState() {
    super.initState();
    _chargerNom();
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  Future<void> _chargerNom() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _nomEntreprise = prefs.getString('enterprise_name') ?? '');
    }
  }

  Future<void> _terminer() async {
    await ChecklistService.marquerTutorielVu();
    if (mounted) Navigator.of(context).pop();
  }

  void _suivant() {
    _controleur.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EnCheckColors.sableClair,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _controleur,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _ecranBienvenue(),
                _ecranCommentPointer(),
                _ecranPret(),
              ],
            ),
            // En haut : le logo En-Check + « Passer ».
            Positioned(
              top: 6,
              left: 20,
              right: 12,
              child: Row(
                children: [
                  const LogoEmpreinte(taille: 34),
                  const SizedBox(width: 10),
                  const Text(
                    'En-Check',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: EnCheckColors.brunProfond,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _terminer,
                    child: Text(
                      widget.relecture ? 'Fermer' : 'Passer',
                      style: const TextStyle(
                        fontSize: 14,
                        color: EnCheckColors.gris,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // En bas : pastilles de progression + bouton.
            Positioned(
              left: 24,
              right: 24,
              bottom: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: _page == i ? 22 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: _page == i
                                ? EnCheckColors.terreChaude
                                : EnCheckColors.gris.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _page == 2 ? _terminer : _suivant,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EnCheckColors.brunProfond,
                        foregroundColor: EnCheckColors.sableDore,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        _page == 2 ? "C'est parti" : 'Suivant',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Écran 1 : bienvenue ─────────────────────────────────────
  Widget _ecranBienvenue() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 76, 24, 128),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/scenes/scene_pointage.jpg',
                height: 240,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.12),
                errorBuilder: (_, __, ___) =>
                    Container(height: 240, color: EnCheckColors.brunProfond),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              _nomEntreprise.isEmpty
                  ? 'Bienvenue'
                  : 'Bienvenue chez $_nomEntreprise',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: EnCheckColors.brunProfond,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Cette borne sert à pointer vos arrivées et départs.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: EnCheckColors.gris,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Écran 2 : comment pointer ───────────────────────────────
  Widget _ecranCommentPointer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 76, 24, 128),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Comment pointer',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: EnCheckColors.brunProfond,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 18),
            _etape('assets/scenes/tuto_appui.jpg',
                '1. Appuyez sur Arrivée ou Départ'),
            _etape('assets/scenes/tuto_code.jpg',
                '2. Entrez votre matricule et votre code'),
            _etape(
                'assets/scenes/tuto_glisser.jpg', '3. Glissez pour valider'),
          ],
        ),
      ),
    );
  }

  Widget _etape(String asset, String libelle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EnCheckColors.blanc,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: EnCheckColors.terreChaude.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              asset,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 72,
                color: EnCheckColors.sableDore.withOpacity(0.3),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              libelle,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: EnCheckColors.brunProfond,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Écran 3 : tout est prêt ─────────────────────────────────
  Widget _ecranPret() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 76, 24, 128),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/scenes/scene_equipe.jpg',
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(height: 190, color: EnCheckColors.brunProfond),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Tout est prêt',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: EnCheckColors.brunProfond,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 16),
            _rappel(Icons.pause_circle_outline, "Pause en haut de l'écran"),
            _rappel(Icons.history, 'Votre Historique et vos journées'),
            _rappel(Icons.tune, 'Paramètres : choisissez votre motif culturel'),
            const SizedBox(height: 18),
            ValueListenableBuilder<MotifCulturel>(
              valueListenable: MotifService.actif,
              builder: (context, motif, _) =>
                  FriseMotif(motif: motif, hauteur: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rappel(IconData icone, String libelle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icone, color: EnCheckColors.terreChaude, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              libelle,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: EnCheckColors.brunProfond,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

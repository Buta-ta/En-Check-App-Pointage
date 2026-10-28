// lib/widgets/panneau_motif.dart
// ═══════════════════════════════════════════════════════════
// 🧵 PANNEAU « MOTIF CULTUREL » — partagé (accueil + pointage)
// ═══════════════════════════════════════════════════════════
//
//  Le bouton ⚙️/« Paramètres » ouvre ce panneau. Raphia (Kuba) est le
//  motif PAR DÉFAUT ; le choix est enregistré sur l'appareil.
//  ⌨️ Touche Échap (clavier physique) = fermer le panneau.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import '../theme/app_theme.dart';
import '../services/motif_service.dart';
import '../screens/tutoriel_screen.dart';

Future<void> ouvrirPanneauMotif(BuildContext context) async {
  MotifCulturel choix = MotifService.actif.value;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Focus(
            autofocus: true,
            onKeyEvent: (noeud, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.pop(sheetContext);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              decoration: const BoxDecoration(
                color: EnCheckColors.blanc,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Motif culturel',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: EnCheckColors.brunProfond,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close, color: EnCheckColors.gris),
                      ),
                    ],
                  ),
                  const Text(
                    'Choisissez le motif de votre entreprise',
                    style: TextStyle(fontSize: 13.5, color: EnCheckColors.gris),
                  ),
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.45,
                    children: [
                      for (final motif in MotifCulturel.tous)
                        _vignetteMotif(
                          motif,
                          selectionne: motif.id == choix.id,
                          onTap: () => setSheetState(() => choix = motif),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        await MotifService.enregistrer(choix);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: choix.couleurBouton,
                        foregroundColor: EnCheckColors.blanc,
                        elevation: 0,
                        side: BorderSide(
                          color: choix.couleurAccent.withOpacity(0.55),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Enregistrer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TutorielScreen(relecture: true),
                        ),
                      );
                    },
                    child: const Text(
                      'Revoir le guide',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: EnCheckColors.gris,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _vignetteMotif(
  MotifCulturel motif, {
  required bool selectionne,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selectionne
                        ? EnCheckColors.orDoux
                        : EnCheckColors.brunProfond.withOpacity(0.18),
                    width: selectionne ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.asset(
                    motif.asset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: motif.couleurBouton),
                  ),
                ),
              ),
              if (motif.id == MotifCulturel.idDefaut)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: EnCheckColors.orDoux,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '★ Défaut',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: EnCheckColors.brunProfond,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          motif.nom,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selectionne ? FontWeight.w800 : FontWeight.w600,
            color: EnCheckColors.brunProfond,
          ),
        ),
      ],
    ),
  );
}

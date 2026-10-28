// lib/widgets/checklist_demarrage.dart
// ═══════════════════════════════════════════════════════════
// 🧭 CHECKLIST « DÉMARRAGE » — la carte 3 étapes de l'accueil
// ═══════════════════════════════════════════════════════════
//
//  Visible uniquement tant qu'elle n'est pas terminée :
//  ☑ Code entreprise (toujours fait) ☑ Motif culturel choisi
//  ☑ Premier pointage. Ensuite elle disparaît toute seule.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../services/checklist_service.dart';
import '../theme/app_theme.dart';

class ChecklistDemarrage extends StatelessWidget {
  const ChecklistDemarrage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [ChecklistService.motifChoisi, ChecklistService.premierPointage]),
      builder: (context, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: EnCheckColors.terreChaude.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.explore_outlined,
                      size: 14, color: EnCheckColors.gris),
                  const SizedBox(width: 6),
                  const Text(
                    'DÉMARRAGE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: EnCheckColors.gris,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _pastille('Code entreprise', true),
                  _pastille(
                      'Motif culturel', ChecklistService.motifChoisi.value),
                  _pastille('Premier pointage',
                      ChecklistService.premierPointage.value),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _pastille(String libelle, bool fait) {
  final couleur = fait ? EnCheckColors.succes : EnCheckColors.gris;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: couleur.withOpacity(0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(fait ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 13, color: couleur),
        const SizedBox(width: 5),
        Text(
          libelle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: couleur,
          ),
        ),
      ],
    ),
  );
}

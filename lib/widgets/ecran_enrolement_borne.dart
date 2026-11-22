import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Écran de préparation à l'enrôlement facial d'un employé déjà inscrit.
/// Le retour à l'accueil Pointage reste visible, même avant le premier enrôlement.
class EcranEnrolementBorne extends StatelessWidget {
  const EcranEnrolementBorne({
    super.key,
    required this.nomEmploye,
    required this.matricule,
    required this.index,
    required this.total,
    required this.onRetourAccueil,
    required this.onCommencer,
    this.onPasser,
  });

  final String nomEmploye;
  final String matricule;
  final int index;
  final int total;
  final VoidCallback onRetourAccueil;
  final VoidCallback onCommencer;
  final VoidCallback? onPasser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surFond = theme.colorScheme.onSurface;
    final progression =
        total > 0 ? (index / total).clamp(0.0, 1.0).toDouble() : 0.0;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 124,
        leading: TextButton.icon(
          key: const Key('retour-accueil-enrolement'),
          onPressed: onRetourAccueil,
          icon: const Icon(Icons.home_outlined, size: 20),
          label: const Text('Accueil'),
          style: TextButton.styleFrom(
            foregroundColor: surFond,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        title: const Text(
          'Enrôler un employé',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: EnCheckColors.terreChaude.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.face_retouching_natural,
                        color: EnCheckColors.terreChaude,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Enrôlement facial sur cette borne',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le profil de cet employé existe déjà. Il reste à enregistrer son visage pour activer le pointage facial.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.75),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Progression',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('Employé ${index + 1} sur $total'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progression,
                      minHeight: 8,
                      backgroundColor: EnCheckColors.terreChaude.withOpacity(0.12),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        EnCheckColors.terreChaude,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: theme.dividerColor.withOpacity(0.6),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor:
                                EnCheckColors.terreChaude.withOpacity(0.12),
                            child: const Icon(
                              Icons.person_outline,
                              color: EnCheckColors.terreChaude,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Employé à enrôler',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  nomEmploye,
                                  key: const Key('nom-employe-enrolement'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (matricule.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(matricule),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      key: const Key('commencer-enrolement'),
                      onPressed: onCommencer,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text(
                        'Commencer l’enrôlement',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EnCheckColors.terreChaude,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  if (onPasser != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: onPasser,
                      icon: const Icon(Icons.skip_next_outlined),
                      label: const Text('Terminer pour l’instant et aller au pointage'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

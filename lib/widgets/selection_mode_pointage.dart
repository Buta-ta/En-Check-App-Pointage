import 'package:flutter/material.dart';

import '../services/mode_pointage_policy.dart';
import '../theme/accueil_palette.dart';

/// Choix du mode avant l'affichage de l'accueil Pointage.
/// Le dernier choix autorisé est restauré automatiquement par l'écran parent.
class SelectionModePointage extends StatelessWidget {
  const SelectionModePointage({
    super.key,
    required this.modes,
    required this.palette,
    required this.onSelection,
    this.dernierMode,
  });

  final List<MethodePointage> modes;
  final AccueilPalette palette;
  final MethodePointage? dernierMode;
  final ValueChanged<MethodePointage> onSelection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: palette.fond,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              children: [
                Icon(Icons.how_to_reg_outlined,
                    size: 42, color: palette.navActif),
                const SizedBox(height: 20),
                Text(
                  'Choisissez votre mode de pointage',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.texteFort,
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Votre dernier choix autorisé est mémorisé pour cette entreprise.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.texteSecondaire,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 28),
                for (final mode in modes) ...[
                  _CarteMode(
                    mode: mode,
                    dernierUtilise: mode == dernierMode,
                    palette: palette,
                    onTap: () => onSelection(mode),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteMode extends StatelessWidget {
  const _CarteMode({
    required this.mode,
    required this.dernierUtilise,
    required this.palette,
    required this.onTap,
  });

  final MethodePointage mode;
  final bool dernierUtilise;
  final AccueilPalette palette;
  final VoidCallback onTap;

  String get _titre => switch (mode) {
        MethodePointage.codePin => 'Code PIN',
        MethodePointage.qr => 'Scanner un badge QR',
        MethodePointage.reconnaissanceFaciale => 'Reconnaissance faciale',
        MethodePointage.enrollementBorne => 'Enrôler un employé',
      };

  String get _description => switch (mode) {
        MethodePointage.codePin => 'Saisissez votre matricule et votre code.',
        MethodePointage.qr => 'Présentez votre badge à la caméra.',
        MethodePointage.reconnaissanceFaciale =>
          'Identifiez-vous avec la caméra.',
        MethodePointage.enrollementBorne => 'Enregistrer un nouvel employé.',
      };

  IconData get _icone => switch (mode) {
        MethodePointage.codePin => Icons.pin_outlined,
        MethodePointage.qr => Icons.qr_code_scanner,
        MethodePointage.reconnaissanceFaciale => Icons.face_retouching_natural,
        MethodePointage.enrollementBorne => Icons.person_add_alt_1,
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$_titre${dernierUtilise ? ', dernier mode utilisé' : ''}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.bordure),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: palette.cercleDoux,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_icone, color: palette.iconeDouce, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _titre,
                            style: TextStyle(
                              color: palette.texteFort,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _description,
                            style: TextStyle(
                              color: palette.texteSecondaire,
                              fontSize: 13,
                            ),
                          ),
                          if (dernierUtilise) ...[
                            const SizedBox(height: 7),
                            Text(
                              'Dernier utilisé',
                              style: TextStyle(
                                color: palette.lien,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: palette.texteSecondaire),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

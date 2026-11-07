import 'package:flutter/material.dart';

import '../services/motif_service.dart';
import '../theme/accueil_palette.dart';
import '../widgets/logo_empreinte.dart';
import 'pointage_screen.dart';

/// Écran public de départ, affiché après la configuration de l'entreprise.
/// « Commencer » ouvre le parcours de pointage existant sans créer de données.
class PublicStartScreen extends StatefulWidget {
  const PublicStartScreen({super.key, this.onCommencer});

  /// Injection réservée aux tests d'interface ; en production, ouvre PointageScreen.
  final VoidCallback? onCommencer;

  @override
  State<PublicStartScreen> createState() => _PublicStartScreenState();
}

class _PublicStartScreenState extends State<PublicStartScreen> {
  @override
  void initState() {
    super.initState();
    MotifService.charger();
  }

  void _commencer() {
    final action = widget.onCommencer;
    if (action != null) {
      action();
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PointageScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<MotifCulturel>(
      valueListenable: MotifService.actif,
      builder: (context, motif, _) {
        final palette = AccueilPalette.pour(motif, sombre);
        final fondPanneau = Color.alphaBlend(
          palette.navActif.withOpacity(0.94),
          const Color(0xFF101918).withOpacity(0.90),
        );
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                motif.asset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => ColoredBox(color: palette.fond),
              ),
              const ColoredBox(color: Color(0x52000000)),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
                            decoration: BoxDecoration(
                              color: fondPanneau,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: palette.primaire.withOpacity(0.8),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55000000),
                                  blurRadius: 28,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 18,
                                  runSpacing: 12,
                                  children: [
                                    const LogoEmpreinte(taille: 76),
                                    Text(
                                      'En-Check',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: palette.surPrimaire,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.6,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  width: 64,
                                  height: 1,
                                  color: palette.primaire.withOpacity(0.85),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  'Gestion de pointage intelligente pour entreprises',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: palette.surPrimaire,
                                    fontSize: 20,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                SizedBox(
                                  width: double.infinity,
                                  height: 60,
                                  child: ElevatedButton(
                                    key: const Key('public-start-commencer'),
                                    onPressed: _commencer,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: palette.cerclePrimaire,
                                      foregroundColor: palette.iconePrimaire,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                    ),
                                    child: const Text(
                                      'Commencer',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

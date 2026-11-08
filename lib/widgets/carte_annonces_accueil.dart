import 'package:flutter/material.dart';

import '../theme/accueil_palette.dart';

/// Icône d'accès aux annonces publiques actives de l'entreprise.
/// Elle n'est montée que lorsqu'il existe au moins une annonce.
class BoutonAnnoncesAccueil extends StatelessWidget {
  const BoutonAnnoncesAccueil({
    super.key,
    required this.nombre,
    required this.palette,
    required this.onPressed,
  });

  final int nombre;
  final AccueilPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final compteur = nombre > 9 ? '9+' : '$nombre';
    final libelle =
        'Annonces, $nombre ${nombre == 1 ? 'annonce active' : 'annonces actives'}';
    return Semantics(
      button: true,
      label: libelle,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Annonces',
          child: SizedBox(
            width: 48,
            height: 48,
            child: Material(
              color: palette.surface.withOpacity(0.94),
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.campaign_rounded,
                        color: palette.primaire, size: 23),
                    Positioned(
                      top: -2,
                      right: -3,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: palette.primaire,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: palette.surface, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          compteur,
                          style: TextStyle(
                            color: palette.surPrimaire,
                            fontSize: 9,
                            height: 1,
                            fontWeight: FontWeight.w700,
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
    );
  }
}

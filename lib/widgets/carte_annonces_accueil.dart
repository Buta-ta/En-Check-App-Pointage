import 'package:flutter/material.dart';

import '../theme/accueil_palette.dart';

/// Repère discret des annonces actives diffusées dans le bandeau d'accueil.
class CarteAnnoncesAccueil extends StatelessWidget {
  const CarteAnnoncesAccueil({
    super.key,
    required this.nombre,
    required this.palette,
  });

  final int nombre;
  final AccueilPalette palette;

  @override
  Widget build(BuildContext context) {
    final pluriel = nombre == 1 ? 'annonce active' : 'annonces actives';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.bordure.withOpacity(0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.cercleDoux,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.campaign_outlined,
              color: palette.iconeDouce,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Annonces',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.texteFort,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$nombre $pluriel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.texteSecondaire,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.campaign_rounded, color: palette.primaire, size: 20),
        ],
      ),
    );
  }
}

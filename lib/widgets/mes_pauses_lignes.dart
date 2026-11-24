import 'package:flutter/material.dart';

import '../services/pause_service.dart';
import '../theme/app_theme.dart';
import '../theme/accueil_palette.dart';

/// En-tête « MES PAUSES » — titre à gauche, résumé réel à droite
/// (« 14 pauses · 13:37 », somme des durées affichées ; jamais inventé).
/// `resume` reste absent quand on ne sait pas (session absente, liste vide).
class MesPausesEnTete extends StatelessWidget {
  const MesPausesEnTete({super.key, required this.resume});

  final String? resume;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'MES PAUSES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: EnCheckColors.gris,
          ),
        ),
        const Spacer(),
        if (resume != null)
          Text(
            resume!,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
      ],
    );
  }
}

/// Légende de colonnes de la table « MES PAUSES ».
class MesPausesColonnes extends StatelessWidget {
  const MesPausesColonnes({super.key, this.avecDate = true});

  final bool avecDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (avecDate)
          const SizedBox(width: 48, child: _Legende('DATE')),
        const Expanded(child: _Legende('HORAIRES')),
        const SizedBox(width: 54, child: _Legende('DURÉE', droite: true)),
      ],
    );
  }
}

class _Legende extends StatelessWidget {
  const _Legende(this.texte, {this.droite = false});

  final String texte;
  final bool droite;

  @override
  Widget build(BuildContext context) {
    return Text(
      texte,
      textAlign: droite ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: EnCheckColors.gris,
      ),
    );
  }
}

/// Une ligne de pause en table : date (masquée sur une répétition du même
/// jour — groupement visuel), horaires en JetBrains Mono, durée alignée à
/// droite pour se lire d'un coup d'œil.
class MesPausesLigne extends StatelessWidget {
  const MesPausesLigne({
    super.key,
    required this.palette,
    required this.debut,
    required this.fin,
    required this.enCours,
    required this.dureeTxt,
    this.date = '',
    this.avecDate = true,
    this.avecFilet = false,
  });

  final AccueilPalette palette;
  final String date;
  final bool avecDate;
  final String debut;
  final String fin;
  final bool enCours;
  final String dureeTxt;
  final bool avecFilet;

  @override
  Widget build(BuildContext context) {
    final horaires = Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12.5,
          color: palette.texteSecondaire,
        ),
        children: [
          TextSpan(text: debut),
          TextSpan(
            text: ' → ',
            style: TextStyle(color: palette.texteTertiaire),
          ),
          if (enCours)
            TextSpan(
              text: fin,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                color: EnCheckColors.terreChaude,
              ),
            )
          else
            TextSpan(text: fin),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final duree = Text(
      dureeTxt,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: palette.texteFort,
      ),
    );

    return Column(
      children: [
        if (avecFilet)
          Divider(height: 1, thickness: 1, color: palette.filet),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              if (avecDate)
                SizedBox(
                  width: 48,
                  child: Text(
                    date,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.texteFort,
                    ),
                  ),
                ),
              Expanded(child: horaires),
              SizedBox(width: 54, child: duree),
            ],
          ),
        ),
      ],
    );
  }
}

/// En-tête « À VÉRIFIER » avec pictogramme d'alerte.
class MesPausesAlertesEnTete extends StatelessWidget {
  const MesPausesAlertesEnTete({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.warning_amber_rounded, size: 13, color: EnCheckColors.terreChaude),
        SizedBox(width: 6),
        Text(
          'À VÉRIFIER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: EnCheckColors.terreChaude,
          ),
        ),
      ],
    );
  }
}

/// Une ligne « à vérifier » : fond teinté pour que l'anomalie se voie
/// immédiatement. Le texte passé est le texte FIGÉ §3.9, à la lettre.
class MesPausesAlerte extends StatelessWidget {
  const MesPausesAlerte({super.key, required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: EnCheckColors.terreChaude.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texte,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: EnCheckColors.terreChaude,
        ),
      ),
    );
  }
}

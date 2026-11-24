import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/accueil_palette.dart';

/// En-tête « MES PAUSES » — titre à gauche, résumé réel à droite
/// (« 14 pauses · 13:37 », somme des durées affichées ; jamais inventé).
/// `resume` reste absent quand on ne sait pas (session absente, liste vide).
class MesPausesEnTete extends StatelessWidget {
  const MesPausesEnTete({
    super.key,
    required this.resume,
    this.deplie,
    this.avecChevron = false,
  });

  final String? resume;

  /// Liste affichée (true) ou repliée (false) — pilote la flèche.
  final bool? deplie;

  /// true = l'en-tête sert de bascule et affiche la flèche.
  final bool avecChevron;

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
        if (avecChevron) ...[
          const SizedBox(width: 8),
          Icon(
            deplie == true ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: EnCheckColors.gris,
          ),
        ],
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

/// La section « MES PAUSES » pliable : tapez l'en-tête (ou la flèche) pour
/// plier ou déplier la table. Au-delà de [seuilDeploiement] lignes, la table
/// démarre repliée — sinon elle démarre dépliée.
class MesPausesListe extends StatefulWidget {
  const MesPausesListe({
    super.key,
    required this.lignes,
    required this.resume,
    required this.message,
    this.avecDate = true,
    this.seuilDeploiement = 3,
  });

  /// Lignes de la table (des [MesPausesLigne]).
  final List<Widget> lignes;

  /// Résumé réel de l'en-tête (« 15 pauses · 14:37 »), null = sans résumé.
  final String? resume;

  /// Message d'état (aucune pause, session expirée…) — alors pas de table.
  final String? message;

  /// Colonne DATE (faux pour la feuille « Ma journée »).
  final bool avecDate;

  /// Au-delà de ce nombre de lignes, la table démarre repliée.
  final int seuilDeploiement;

  @override
  State<MesPausesListe> createState() => _MesPausesListeState();
}

class _MesPausesListeState extends State<MesPausesListe> {
  late bool _deplie = widget.lignes.length <= widget.seuilDeploiement;

  @override
  Widget build(BuildContext context) {
    final pliable = widget.lignes.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: pliable ? () => setState(() => _deplie = !_deplie) : null,
          child: MesPausesEnTete(
            resume: widget.resume,
            deplie: _deplie,
            avecChevron: pliable,
          ),
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 8),
          Text(widget.message!, style: const TextStyle(fontSize: 12.5)),
        ],
        if (pliable && _deplie) ...[
          const SizedBox(height: 8),
          MesPausesColonnes(avecDate: widget.avecDate),
          ...widget.lignes,
        ],
      ],
    );
  }
}

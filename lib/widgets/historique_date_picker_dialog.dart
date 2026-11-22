import 'package:flutter/material.dart';

import '../theme/accueil_palette.dart';

/// Sélecteur calendrier de l'historique : les jours ayant des pointages sont
/// mis en évidence pour être repérés immédiatement.
class HistoriqueDatePickerDialog extends StatefulWidget {
  const HistoriqueDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.datesAvecHistorique,
    required this.palette,
    required this.surfaceCalendrier,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<String> datesAvecHistorique;
  final AccueilPalette palette;
  final Color surfaceCalendrier;

  @override
  State<HistoriqueDatePickerDialog> createState() =>
      _HistoriqueDatePickerDialogState();
}

class _HistoriqueDatePickerDialogState
    extends State<HistoriqueDatePickerDialog> {
  late DateTime _dateChoisie;
  late DateTime _moisAffiche;

  @override
  void initState() {
    super.initState();
    _dateChoisie = _jour(widget.initialDate);
    _moisAffiche = DateTime(_dateChoisie.year, _dateChoisie.month);
  }

  DateTime _jour(DateTime date) => DateTime(date.year, date.month, date.day);

  String _cle(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool get _peutReculer =>
      _moisAffiche.year > widget.firstDate.year ||
      (_moisAffiche.year == widget.firstDate.year &&
          _moisAffiche.month > widget.firstDate.month);

  bool get _peutAvancer =>
      _moisAffiche.year < widget.lastDate.year ||
      (_moisAffiche.year == widget.lastDate.year &&
          _moisAffiche.month < widget.lastDate.month);

  void _changerMois(int delta) {
    setState(() {
      _moisAffiche = DateTime(_moisAffiche.year, _moisAffiche.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final localizations = MaterialLocalizations.of(context);
    final joursDansMois = DateTime(
      _moisAffiche.year,
      _moisAffiche.month + 1,
      0,
    ).day;
    final decalage =
        DateTime(_moisAffiche.year, _moisAffiche.month, 1).weekday % 7;

    return Dialog(
      key: const Key('historique-selecteur-calendrier'),
      backgroundColor: widget.surfaceCalendrier,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Consulter les pointages',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.texteFort,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('historique-calendrier-mois-precedent'),
                    tooltip: 'Mois précédent',
                    onPressed: _peutReculer ? () => _changerMois(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const Key('historique-calendrier-mois-suivant'),
                    tooltip: 'Mois suivant',
                    onPressed: _peutAvancer ? () => _changerMois(1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  localizations.formatMonthYear(_moisAffiche),
                  key: const Key('historique-calendrier-mois'),
                  style: TextStyle(
                    color: palette.texteFort,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final jour in localizations.narrowWeekdays)
                    Expanded(
                      child: Center(
                        child: Text(
                          jour,
                          style: TextStyle(
                            color: palette.texteSecondaire,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.builder(
                key: const Key('historique-calendrier-grille'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ((decalage + joursDansMois + 6) ~/ 7) * 7,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final jourDuMois = index - decalage + 1;
                  if (jourDuMois < 1 || jourDuMois > joursDansMois) {
                    return const SizedBox.shrink();
                  }

                  final date = DateTime(
                    _moisAffiche.year,
                    _moisAffiche.month,
                    jourDuMois,
                  );
                  final dateCivile = _jour(date);
                  final autorisee =
                      !dateCivile.isBefore(_jour(widget.firstDate)) &&
                          !dateCivile.isAfter(_jour(widget.lastDate));
                  final avecHistorique = autorisee &&
                      widget.datesAvecHistorique.contains(_cle(date));
                  final estChoisie = _jour(_dateChoisie) == dateCivile;
                  final estAujourdHui = _jour(widget.lastDate) == dateCivile;
                  final couleurTexte = !autorisee
                      ? palette.texteSecondaire.withOpacity(0.45)
                      : estChoisie || avecHistorique
                          ? (estChoisie
                              ? palette.surPrimaire
                              : palette.primaire)
                          : palette.texte;
                  final etiquette = avecHistorique
                      ? '${date.day}, pointages enregistrés'
                      : '${date.day}';

                  return Semantics(
                    button: autorisee,
                    selected: estChoisie,
                    label: etiquette,
                    child: Center(
                      child: InkWell(
                        key: Key('historique-calendrier-jour-${_cle(date)}'),
                        customBorder: const CircleBorder(),
                        onTap: autorisee
                            ? () => setState(() => _dateChoisie = dateCivile)
                            : null,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: estChoisie
                                      ? palette.primaire
                                      : avecHistorique
                                          ? palette.primaire.withOpacity(0.14)
                                          : Colors.transparent,
                                  border: estAujourdHui && !estChoisie
                                      ? Border.all(
                                          color: palette.primaire,
                                          width: 1.2,
                                        )
                                      : null,
                                ),
                                child: Text(
                                  '$jourDuMois',
                                  style: TextStyle(
                                    color: couleurTexte,
                                    fontSize: 16,
                                    fontWeight: avecHistorique || estChoisie
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (avecHistorique && !estChoisie)
                                Positioned(
                                  bottom: 2,
                                  child: Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: palette.primaire,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette.primaire.withOpacity(0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.primaire),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Pointages enregistrés',
                      style: TextStyle(
                        color: palette.texteSecondaire,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('historique-calendrier-annuler'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ANNULER'),
                  ),
                  TextButton(
                    key: const Key('historique-calendrier-choisir'),
                    onPressed: () => Navigator.of(context).pop(_dateChoisie),
                    child: const Text('CHOISIR'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

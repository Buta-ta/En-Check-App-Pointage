import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Composition de l'accueil d'après la maquette du 5 novembre (412 × 869 pt).
///
/// Ce widget ne possède volontairement AUCUN ScrollView. La photo et les
/// respirations absorbent d'abord les variations de hauteur. Les textes et les
/// commandes gardent leur place ; sur un écran extraordinairement court, un
/// dernier FittedBox évite toute coupe au lieu d'introduire un défilement.
class AccueilMaquette extends StatelessWidget {
  const AccueilMaquette({
    super.key,
    required this.entete,
    required this.salutation,
    required this.cartesAction,
    required this.aujourdhui,
    required this.navigation,
    this.alerteBorne,
    this.actionBorne,
  });

  final Widget entete;
  final Widget salutation;
  final Widget cartesAction;
  final Widget aujourdhui;
  final Widget navigation;
  final Widget? alerteBorne;
  final Widget? actionBorne;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final texte = media.textScaler.scale(1.0);
    return LayoutBuilder(
      builder: (context, contraintes) {
        final hauteur = contraintes.maxHeight;
        final nav = ((hauteur < 700 ? 64.0 : 73.0) +
                math.max(0.0, texte - 1.0) * 18.0)
            .clamp(62.0, 112.0)
            .toDouble();
        return Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: SizedBox.expand(
                    child: LayoutBuilder(
                      builder: (context, corps) => _construireCorps(
                        context,
                        corps.maxWidth,
                        corps.maxHeight,
                        texte,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: SizedBox(
                height: nav,
                width: double.infinity,
                child: navigation,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _construireCorps(
    BuildContext context,
    double largeur,
    double hauteur,
    double texte,
  ) {
    final d = _Disposition.calculer(
      largeur: largeur,
      hauteur: hauteur,
      texte: texte,
      avecAlerte: alerteBorne != null,
      avecActionBorne: actionBorne != null,
    );

    final pile = SizedBox(
      width: largeur,
      height: d.total,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _bloc('accueil-entete', d, 'entete', entete),
          _bloc('accueil-salutation', d, 'salutation', salutation),
          if (alerteBorne != null)
            _bloc('accueil-alerte', d, 'alerte', alerteBorne!),
          _bloc('accueil-actions', d, 'cartes', cartesAction),
          _bloc('accueil-aujourdhui', d, 'jour', aujourdhui),
          if (actionBorne != null)
            _bloc('accueil-action-borne', d, 'actionBorne', actionBorne!),
        ],
      ),
    );

    if (d.reduction >= 0.999) return pile;
    // Dernier garde-fou pour les hauteurs extrêmes : tout reste visible, rien
    // ne défile et aucun texte n'est coupé. Les tailles usuelles restent à 1.
    return SizedBox(
      width: largeur,
      height: hauteur,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: pile,
      ),
    );
  }

  Widget _bloc(String cle, _Disposition d, String nom, Widget enfant) {
    final y = d.position(nom);
    return Positioned(
      left: d.marge,
      right: d.marge,
      top: y,
      height: d.hauteurs[nom],
      child: SizedBox(key: Key(cle), child: enfant),
    );
  }
}

class _Disposition {
  _Disposition._(this.hauteurs, this.marge, this.total, this.reduction);

  final Map<String, double> hauteurs;
  final double marge;
  final double total;
  final double reduction;

  double position(String nom) {
    var y = 0.0;
    for (final cle in _ordre) {
      if (cle == nom) return y;
      y += hauteurs[cle] ?? 0.0;
    }
    return y;
  }

  static const _ordre = [
    'haut',
    'entete',
    'gSalut',
    'salutation',
    'gAlerte',
    'alerte',
    'cartes',
    'gJour',
    'jour',
    'gActionBorne',
    'actionBorne',
    'gNav',
  ];

  static _Disposition calculer({
    required double largeur,
    required double hauteur,
    required double texte,
    required bool avecAlerte,
    required bool avecActionBorne,
  }) {
    final e = (hauteur / 796.0).clamp(1.0, 1.22).toDouble();
    final plaque = math.max(37.0 * e, 34.0 * texte);
    final chez = math.max(40.0 * e, 18.0 + 22.0 * texte);
    final plaqueMin = math.max(30.0, 34.0 * texte);
    final salutMin = plaqueMin + chez;

    final h = <String, double>{
      'haut': 21.0 * e,
      'gSalut': 23.0 * e,
      'salutation': plaque + chez,
      'gAlerte': avecAlerte ? 10.0 * e : 0.0,
      'alerte': avecAlerte ? math.max(60.0 * e, 48.0 * texte) : 0.0,
      'cartes': math.max(131.0 * e, 83.0 + 48.0 * texte),
      'gJour': 18.0 * e,
      'jour': math.max(90.0 * e, 25.0 + 65.0 * texte),
      'gActionBorne': avecActionBorne ? 12.0 * e : 0.0,
      'actionBorne':
          avecActionBorne ? math.max(50.0 * e, 44.0 * texte) : 0.0,
      'gNav': 12.0 * e,
    };
    final min = <String, double>{
      'haut': 10.0,
      'gSalut': 12.0,
      'salutation': salutMin,
      'gAlerte': avecAlerte ? 7.0 : 0.0,
      'alerte': avecAlerte ? math.max(52.0, 48.0 * texte) : 0.0,
      'cartes': math.max(104.0, 62.0 + 48.0 * texte),
      'gJour': 10.0,
      'jour': 16.0 + 65.0 * texte,
      'gActionBorne': avecActionBorne ? 8.0 : 0.0,
      'actionBorne':
          avecActionBorne ? math.max(44.0, 44.0 * texte) : 0.0,
      'gNav': 8.0,
    };

    double somme() => h.values.fold(0.0, (a, b) => a + b);
    // Le média reste en 16:9 ; la frise culturelle de 40 px est séparée dessous.
    final marge = largeur <= 420 ? 20.0 : 24.0;
    final largeurInterne = math.max(1.0, largeur - marge * 2).toDouble();
    final entete = (largeurInterne * 9 / 16 + 40.0).toDouble();
    final surplus = hauteur - somme() - entete;
    if (surplus > 0) {
      const respirations = [
        'haut', 'gSalut', 'gAlerte', 'gJour', 'gActionBorne', 'gNav',
      ];
      final totalGaps = respirations.fold(0.0, (s, k) => s + h[k]!);
      if (totalGaps > 0) {
        for (final k in respirations) {
          h[k] = h[k]! + surplus * h[k]! / totalGaps;
        }
      }
    } else {
      final deficit = -surplus;
      final marges = <String, double>{
        for (final k in h.keys) k: math.max(0.0, h[k]! - min[k]!),
      };
      final totalMarges = marges.values.fold(0.0, (a, b) => a + b);
      final facteur = totalMarges <= 0
          ? 0.0
          : math.min(1.0, deficit / totalMarges);
      for (final k in h.keys) {
        h[k] = h[k]! - marges[k]! * facteur;
      }
    }

    final total = somme() + entete;
    final reduction = total > hauteur && total > 0
        ? math.max(0.1, hauteur / total)
        : 1.0;
    h['entete'] = entete;
    return _Disposition._(h, marge, total, reduction);
  }
}

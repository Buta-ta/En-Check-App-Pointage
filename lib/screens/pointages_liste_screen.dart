// lib/screens/pointages_liste_screen.dart
// ═══════════════════════════════════════════════════════════
// 📋 TOUS LES POINTAGES — pagination « Précédent » / « Suivant »
// ═══════════════════════════════════════════════════════════
//
//  Fiche « Affichage mobile » (§3.5) : pour un historique long, on
//  consulte tous les pointages par plusieurs pages, avec « Précédent »
//  et « Suivant ». Aucun pointage n'est supprimé, l'ordre et les
//  cartes-jours sont conservés : les cartes sont CELLES de l'historique
//  (mêmes widgets, inchangés), une par page. L'écran remplit toute la
//  largeur du téléphone et ne défile pas.
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/sans_etirement.dart';

class PointagesListeScreen extends StatefulWidget {
  const PointagesListeScreen({super.key, required this.cartes});

  /// Une carte-jour par journée, dans l'ordre de l'historique.
  final List<Widget> cartes;

  @override
  State<PointagesListeScreen> createState() => _PointagesListeScreenState();
}

class _PointagesListeScreenState extends State<PointagesListeScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final int total = widget.cartes.length;
    return Scaffold(
      backgroundColor: EnCheckColors.sableClair,
      appBar: AppBar(
        backgroundColor: EnCheckColors.brunProfond,
        foregroundColor: EnCheckColors.blanc,
        elevation: 0,
        title: const Text(
          'POINTAGES',
          style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w300),
        ),
        centerTitle: true,
      ),
      body: SansEtirement(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: total == 0
                    ? const SizedBox(
                        height: 200,
                        child: Center(
                          child: Text('Aucun pointage',
                              style: TextStyle(
                                  color: EnCheckColors.gris, fontSize: 18)),
                        ),
                      )
                    : widget.cartes[_page],
              ),
            ),
            _barrePagination(total),
          ],
        ),
      ),
    );
  }

  Widget _barrePagination(int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: EnCheckColors.blanc,
        border: const Border(
            top: BorderSide(color: EnCheckColors.sableClair, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _page > 0
                  ? () => setState(() => _page = _page - 1)
                  : null,
              icon: const Icon(Icons.arrow_back, size: 17),
              label: const Text('Précédent',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: EnCheckColors.brunProfond,
                side: BorderSide(
                    color: EnCheckColors.brunProfond.withOpacity(0.35)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Page ${_page + 1}/$total',
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: EnCheckColors.brunProfond,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _page < total - 1
                  ? () => setState(() => _page = _page + 1)
                  : null,
              icon: const Icon(Icons.arrow_forward, size: 17),
              label: const Text('Suivant',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: EnCheckColors.brunProfond,
                side: BorderSide(
                    color: EnCheckColors.brunProfond.withOpacity(0.35)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

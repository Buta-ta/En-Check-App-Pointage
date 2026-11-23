// Verrou des TEXTES FIGÉS §3.9 du rapport validé le 22/11/2026.
//
// Chaque texte ci-dessous est un CONTRAT : ce test échoue si quelqu'un en
// reformule un seul. Les statiques de `PauseService` sont la source unique
// (les écrans les délèguent — jamais de copie locale du texte).
import 'package:flutter_test/flutter_test.dart';
import 'package:en_check/services/pause_service.dart';

void main() {
  group('dateCourte — « 5/11 » (§3.9)', () {
    test('jour du texte figé', () {
      expect(PauseService.dateCourte('2026-11-05'), '5/11');
    });

    test('autres jours', () {
      expect(PauseService.dateCourte('2026-11-04'), '4/11');
      expect(PauseService.dateCourte('2026-12-31'), '31/12');
    });

    test('inconnu = tiret, jamais inventé', () {
      expect(PauseService.dateCourte(null), '—');
      expect(PauseService.dateCourte('pas-une-date'), '—');
    });
  });

  group('dureeHM — « 2:05 » (§3.9)', () {
    test('valeurs des textes figés', () {
      expect(PauseService.dureeHM(125), '2:05'); // « Pause longue (2:05) »
      expect(PauseService.dureeHM(98), '1:38'); //  « Pause 1:38 »
      expect(PauseService.dureeHM(196), '3:16'); //  « Travaillé 3:16 »
      expect(PauseService.dureeHM(294), '4:54'); //  « Présence 4:54 »
    });

    test('minutes à deux chiffres, jamais négatif', () {
      expect(PauseService.dureeHM(5), '0:05');
      expect(PauseService.dureeHM(0), '0:00');
      expect(PauseService.dureeHM(-3), '0:00');
    });
  });

  group('lignesAVerifier — §2.6/§3.9 (affichage non bloquant)', () {
    test('« Pause longue (2:05) le 5/11 — à vérifier »', () {
      final lignes = PauseService.lignesAVerifier([
        {
          'anomalie': 'trop_longue',
          'duree_minutes': 125,
          'jour': '2026-11-05',
          'ouverte': false,
        },
      ], '2026-11-23');
      expect(lignes, ['Pause longue (2:05) le 5/11 — à vérifier']);
    });

    test('le dépassement partage la même ligne', () {
      final lignes = PauseService.lignesAVerifier([
        {
          'anomalie': 'depassement',
          'duree_minutes': 98,
          'jour': '2026-11-05',
          'ouverte': false,
        },
      ], '2026-11-23');
      expect(lignes, ['Pause longue (1:38) le 5/11 — à vérifier']);
    });

    test('« Journée du 4/11 non terminée — à vérifier » (sans_reprise)', () {
      final lignes = PauseService.lignesAVerifier([
        {
          'anomalie': 'sans_reprise',
          'duree_minutes': 60,
          'jour': '2026-11-04',
          'ouverte': false,
        },
      ], '2026-11-23');
      expect(lignes, ['Journée du 4/11 non terminée — à vérifier']);
    });

    test('ouverte depuis la veille = non terminée aussi', () {
      final lignes = PauseService.lignesAVerifier([
        {
          'anomalie': null,
          'duree_minutes': null,
          'jour': '2026-11-04',
          'ouverte': true,
        },
      ], '2026-11-23');
      expect(lignes, ['Journée du 4/11 non terminée — à vérifier']);
    });

    test('ouverte AUJOURD\'HUI : pas de ligne (rien à reprocher)', () {
      final lignes = PauseService.lignesAVerifier([
        {
          'anomalie': null,
          'duree_minutes': null,
          'jour': '2026-11-23',
          'ouverte': true,
        },
      ], '2026-11-23');
      expect(lignes, isEmpty);
    });

    test('normale : aucune ligne — jamais d\'alerte inventée', () {
      final lignes = PauseService.lignesAVerifier([
        {
          'anomalie': null,
          'duree_minutes': 45,
          'jour': '2026-11-05',
          'ouverte': false,
        },
      ], '2026-11-23');
      expect(lignes, isEmpty);
    });

    test('anomalie sans durée connue : la ligne est omise', () {
      final lignes = PauseService.lignesAVerifier([
        {
          'anomalie': 'trop_longue',
          'duree_minutes': null,
          'jour': '2026-11-05',
          'ouverte': false,
        },
      ], '2026-11-23');
      expect(lignes, isEmpty);
    });
  });
}

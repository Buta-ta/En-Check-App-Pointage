// test/pauses_zones_test.dart
// Règles de zones de pause (§3.2 du rapport validé 22/11/2026) : le code de
// l'app doit tomber D'ACCORD avec le juge serveur — ces tests figent les
// frontières exactes (strictement supérieur à la tolérance, plafond absolu
// prioritaire, sans grille = aucune comparaison).
import 'package:flutter_test/flutter_test.dart';
import 'package:en_check/services/pause_service.dart';

void main() {
  group('zonePause — Longue (depassement)', () {
    test('écart exactement ÉGAL à la tolérance → normale (strictement >)', () {
      expect(
        PauseService.zonePause(
          dureeMinutes: 75, // créneau 60, tolérance 15 → écart 15
          prevueMinutes: 60,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'normale',
      );
    });

    test('écart de 21 min sur un créneau de 90 → depassement', () {
      // « En pause depuis 1:51 · dépassement de 21 min » (texte §3.9).
      expect(
        PauseService.zonePause(
          dureeMinutes: 111,
          prevueMinutes: 90,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'depassement',
      );
    });

    test('sous le créneau → normale', () {
      expect(
        PauseService.zonePause(
          dureeMinutes: 30,
          prevueMinutes: 60,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'normale',
      );
    });
  });

  group('zonePause — Suspecte (trop_longue)', () {
    test('durée supérieure au plafond → trop_longue (prioritaire)', () {
      expect(
        PauseService.zonePause(
          dureeMinutes: 121,
          prevueMinutes: 90,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'trop_longue',
      );
    });

    test('120 min pile = pas suspecte (strictement > le plafond)', () {
      expect(
        PauseService.zonePause(
          dureeMinutes: 120,
          prevueMinutes: 90,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'depassement', // 120 − 90 = 30 > 15
      );
    });

    test('trop_longue même sans grille (plafond absolu)', () {
      // Preuve serveur : Reine, sans grille, 150 min → trop_longue.
      expect(
        PauseService.zonePause(
          dureeMinutes: 150,
          prevueMinutes: null,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'trop_longue',
      );
    });
  });

  group('zonePause — sans grille', () {
    test('sans créneau : rien à comparer → normale', () {
      expect(
        PauseService.zonePause(
          dureeMinutes: 119,
          prevueMinutes: null,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'normale',
      );
    });

    test('créneau nul = pas de grille → normale', () {
      expect(
        PauseService.zonePause(
          dureeMinutes: 119,
          prevueMinutes: 0,
          toleranceMinutes: 15,
          maxMinutes: 120,
        ),
        'normale',
      );
    });
  });

  group('rappelSensGrille — le rappel suit la grille, pas un délai fixe', () {
    test('dépassement du créneau → rappel', () {
      final debut = DateTime.now().toUtc().subtract(const Duration(minutes: 96));
      expect(
        PauseService.rappelSensGrille(
          debutUtc: debut,
          prevueMinutes: 60,
          toleranceMinutes: 15,
        ),
        isTrue, // 96 − 60 = 36 > 15
      );
    });

    test('dans la tolérance → pas de rappel', () {
      final debut = DateTime.now().toUtc().subtract(const Duration(minutes: 70));
      expect(
        PauseService.rappelSensGrille(
          debutUtc: debut,
          prevueMinutes: 60,
          toleranceMinutes: 15,
        ),
        isFalse, // 70 − 60 = 10 ≤ 15
      );
    });

    test('sans créneau → ancien délai de 75 min', () {
      final court = DateTime.now().toUtc().subtract(const Duration(minutes: 74));
      final long_ = DateTime.now().toUtc().subtract(const Duration(minutes: 76));
      expect(
        PauseService.rappelSensGrille(
          debutUtc: court,
          prevueMinutes: null,
          toleranceMinutes: 15,
        ),
        isFalse,
      );
      expect(
        PauseService.rappelSensGrille(
          debutUtc: long_,
          prevueMinutes: null,
          toleranceMinutes: 15,
        ),
        isTrue,
      );
    });
  });
}

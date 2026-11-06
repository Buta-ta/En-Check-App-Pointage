import 'package:flutter_test/flutter_test.dart';
import 'package:en_check/services/historique_periode.dart';

void main() {
  group('Période de consultation de l’historique employé', () {
    final maintenant = DateTime(2026, 11, 6, 15, 42);

    test('accepte aujourd’hui et les six jours précédents', () {
      expect(HistoriquePeriode.autorise(maintenant, maintenant), isTrue);
      expect(
        HistoriquePeriode.autorise(DateTime(2026, 10, 31, 23, 59), maintenant),
        isTrue,
      );
      expect(
        HistoriquePeriode.premierJourAutorise(maintenant),
        DateTime(2026, 10, 31),
      );
    });

    test('refuse les dates futures et les dates plus anciennes que la période', () {
      expect(HistoriquePeriode.autorise(DateTime(2026, 11, 7), maintenant), isFalse);
      expect(HistoriquePeriode.autorise(DateTime(2026, 10, 30), maintenant), isFalse);
    });
  });

  group('Matricule « Ma journée »', () {
    test('utilise le préfixe réel, sans coder le matricule exemple', () {
      expect(HistoriquePeriode.matriculeComplet('0002', 'ENN'), 'ENN-0002');
      expect(HistoriquePeriode.matriculeComplet(' enn-0002 ', 'ENN'), 'ENN-0002');
      expect(HistoriquePeriode.matriculeComplet('0002', 'ACME'), 'ACME-0002');
      expect(HistoriquePeriode.matriculeComplet('ENN-0002', ''), 'ENN-0002');
    });
  });
}

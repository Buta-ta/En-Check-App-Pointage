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

  test('filtre sans modifier la source et trie un seul événement par ligne', () {
    final date = DateTime(2026, 11, 6);
    final source = <Map<String, dynamic>>[
      {
        'check_type': 'out',
        'check_time': DateTime(2026, 11, 6, 12).toIso8601String(),
        'client_ref': 'sortie-midi',
      },
      {
        'check_type': 'in',
        'check_time': DateTime(2026, 11, 6, 8).toIso8601String(),
        'client_ref': 'entree-matin',
      },
      {
        'check_type': 'in',
        'check_time': DateTime(2026, 11, 5, 23, 59).toIso8601String(),
        'client_ref': 'veille',
      },
      {'check_type': 'in', 'check_time': 'date-invalide', 'client_ref': 'inconnue'},
    ];

    final jour = HistoriquePeriode.pointagesDuJour(source, date);
    expect(jour.map((p) => p['client_ref']), ['entree-matin', 'sortie-midi']);
    expect(jour.length, 2);
    expect(source.length, 4);
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

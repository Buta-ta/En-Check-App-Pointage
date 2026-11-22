import 'package:en_check/services/motif_service.dart';
import 'package:en_check/theme/accueil_palette.dart';
import 'package:en_check/widgets/historique_date_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('repère les jours avec historique et permet de les choisir',
      (tester) async {
    DateTime? dateRetenue;
    final palette = AccueilPalette.pour(MotifCulturel.adinkra, false);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                dateRetenue = await showDialog<DateTime>(
                  context: context,
                  builder: (_) => HistoriqueDatePickerDialog(
                    initialDate: DateTime(2026, 11, 17),
                    firstDate: DateTime(2026, 11, 11),
                    lastDate: DateTime(2026, 11, 17),
                    datesAvecHistorique: const {
                      '2026-11-13',
                      '2026-11-15',
                    },
                    palette: palette,
                    surfaceCalendrier: palette.surface,
                  ),
                );
              },
              child: const Text('Ouvrir calendrier'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir calendrier'));
    await tester.pumpAndSettle();

    expect(find.text('Pointages enregistrés'), findsOneWidget);
    expect(
      find.byKey(const Key('historique-calendrier-jour-2026-11-13')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('historique-calendrier-jour-2026-11-15')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('historique-calendrier-jour-2026-11-13')),
    );
    await tester.tap(find.byKey(const Key('historique-calendrier-choisir')));
    await tester.pumpAndSettle();

    expect(dateRetenue, DateTime(2026, 11, 13));
  });
}

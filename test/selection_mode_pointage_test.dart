import 'package:en_check/services/mode_pointage_policy.dart';
import 'package:en_check/services/motif_service.dart';
import 'package:en_check/theme/accueil_palette.dart';
import 'package:en_check/widgets/selection_mode_pointage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rappelle le dernier mode sans le sélectionner à la place',
      (tester) async {
    MethodePointage? selection;
    var accueilAppuye = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SelectionModePointage(
          modes: const [MethodePointage.qr, MethodePointage.codePin],
          dernierMode: MethodePointage.codePin,
          palette: AccueilPalette.pour(MotifCulturel.adinkra, false),
          onSelection: (mode) => selection = mode,
          onAccueil: () => accueilAppuye = true,
        ),
      ),
    );

    expect(find.text('Choisissez votre mode de pointage'), findsOneWidget);
    expect(find.text('Scanner un badge QR'), findsOneWidget);
    expect(find.text('Code PIN'), findsOneWidget);
    expect(find.text('Dernier utilisé'), findsOneWidget);
    expect(selection, isNull);

    await tester.tap(find.text('Scanner un badge QR'));
    expect(selection, MethodePointage.qr);

    await tester.tap(find.byKey(const Key('selection-mode-accueil')));
    expect(accueilAppuye, isTrue);
  });
}

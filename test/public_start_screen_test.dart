import 'package:en_check/screens/public_start_screen.dart';
import 'package:en_check/services/public_start_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('écran public : identité, slogan, seul bouton Commencer',
      (tester) async {
    SharedPreferences.setMockInitialValues({'enterprise_id': 'entreprise-test'});
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var commencements = 0;

    await tester.pumpWidget(MaterialApp(
      home: PublicStartScreen(onCommencer: () => commencements++),
    ));
    await tester.pumpAndSettle();

    expect(find.text('En-Check'), findsOneWidget);
    expect(find.text('Gestion de pointage intelligente pour entreprises'),
        findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Accueil'), findsNothing);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(
      await PublicStartService.estDejaUtilise('entreprise-test'),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('public-start-commencer')));
    await tester.pumpAndSettle();
    expect(commencements, 1);
    expect(
      await PublicStartService.estDejaUtilise('entreprise-test'),
      isTrue,
    );
  });
}

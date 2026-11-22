import 'package:en_check/services/public_start_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('« Commencer » est mémorisé séparément par entreprise sur cet appareil',
      () async {
    SharedPreferences.setMockInitialValues({});

    expect(await PublicStartService.estDejaUtilise('entreprise-a'), isFalse);
    await PublicStartService.marquerUtilise('entreprise-a');

    expect(await PublicStartService.estDejaUtilise('entreprise-a'), isTrue);
    expect(await PublicStartService.estDejaUtilise('entreprise-b'), isFalse);
  });
}

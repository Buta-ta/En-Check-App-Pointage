import 'package:en_check/services/mode_pointage_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le PIN reste principal par défaut, le QR devient principal s’il est actif',
      () {
    expect(
      ModePointagePolicy.principal(qrActif: false),
      MethodePointage.codePin,
    );
    expect(
      ModePointagePolicy.principal(qrActif: true),
      MethodePointage.qr,
    );
  });

  test('sans option active, le PIN reste seul et aucun Autre mode ne s’affiche',
      () {
    expect(
      ModePointagePolicy.autresModes(
        qrActif: false,
        reconnaissanceFacialeActive: false,
        borneActive: false,
      ),
      isEmpty,
    );
  });

  test('le QR principal n’est pas répété dans Autres modes et garde le PIN en repli',
      () {
    final autres = ModePointagePolicy.autresModes(
      qrActif: true,
      reconnaissanceFacialeActive: false,
      borneActive: false,
    );

    expect(autres, [MethodePointage.codePin]);
    expect(autres, isNot(contains(MethodePointage.qr)));
  });

  test('la reconnaissance et le mode borne restent des options secondaires',
      () {
    final autres = ModePointagePolicy.autresModes(
      qrActif: true,
      reconnaissanceFacialeActive: true,
      borneActive: true,
    );

    expect(
      autres,
      containsAll([
        MethodePointage.codePin,
        MethodePointage.reconnaissanceFaciale,
        MethodePointage.enrollementBorne,
      ]),
    );
    expect(autres, isNot(contains(MethodePointage.qr)));
  });
}

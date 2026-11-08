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

  test('sans autre méthode, seul le PIN est proposé', () {
    expect(
      ModePointagePolicy.modesDisponibles(
        qrActif: false,
        reconnaissanceFacialeActive: false,
      ),
      [MethodePointage.codePin],
    );
  });

  test('QR et PIN sont des choix distincts et ordonnés avec QR en premier', () {
    expect(
      ModePointagePolicy.modesDisponibles(
        qrActif: true,
        reconnaissanceFacialeActive: false,
      ),
      [MethodePointage.qr, MethodePointage.codePin],
    );
  });

  test('le mode facial libre s’ajoute aux autres méthodes autorisées', () {
    expect(
      ModePointagePolicy.modesDisponibles(
        qrActif: true,
        reconnaissanceFacialeActive: true,
        modeFacial: 'face_free',
      ),
      [
        MethodePointage.qr,
        MethodePointage.codePin,
        MethodePointage.reconnaissanceFaciale,
      ],
    );
  });

  test('les modes faciaux obligatoires ou exclusifs ne sont pas contournés', () {
    for (final mode in ['face_required', 'face_exclusive']) {
      expect(
        ModePointagePolicy.modesDisponibles(
          qrActif: true,
          reconnaissanceFacialeActive: true,
          modeFacial: mode,
        ),
        [MethodePointage.reconnaissanceFaciale],
      );
    }
  });

  test('un réglage facial sans repli garde la reconnaissance comme seul choix',
      () {
    expect(
      ModePointagePolicy.modesDisponibles(
        qrActif: true,
        reconnaissanceFacialeActive: true,
        modeFacial: 'face_free',
        repliFacialAutorise: false,
      ),
      [MethodePointage.reconnaissanceFaciale],
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
  });
}

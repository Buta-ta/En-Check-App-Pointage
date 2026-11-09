import 'package:en_check/services/mode_pointage_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ne sélectionne automatiquement un mode que s’il est le seul autorisé',
      () {
    expect(
      ModePointagePolicy.modeAutoSelectionne(
        [MethodePointage.reconnaissanceFaciale],
      ),
      MethodePointage.reconnaissanceFaciale,
    );
    expect(
      ModePointagePolicy.modeAutoSelectionne([
        MethodePointage.codePin,
        MethodePointage.reconnaissanceFaciale,
      ]),
      isNull,
    );
  });

  test('restaure un mode mémorisé uniquement s’il reste disponible', () {
    final disponibles = [
      MethodePointage.codePin,
      MethodePointage.reconnaissanceFaciale,
    ];

    expect(
      ModePointagePolicy.choixMemorise(
        modesDisponibles: disponibles,
        valeurMemorisee: 'reconnaissanceFaciale',
      ),
      MethodePointage.reconnaissanceFaciale,
    );
    expect(
      ModePointagePolicy.choixMemorise(
        modesDisponibles: disponibles,
        valeurMemorisee: 'qr',
      ),
      isNull,
    );
  });

  test('le bouton d’enrôlement borne exige une borne et le mode facial choisi',
      () {
    expect(
      ModePointagePolicy.afficherActionEnrolement(
        borneActive: true,
        modeChoisi: MethodePointage.reconnaissanceFaciale,
      ),
      isTrue,
    );
    expect(
      ModePointagePolicy.afficherActionEnrolement(
        borneActive: true,
        modeChoisi: MethodePointage.codePin,
      ),
      isFalse,
    );
    expect(
      ModePointagePolicy.afficherActionEnrolement(
        borneActive: false,
        modeChoisi: MethodePointage.reconnaissanceFaciale,
      ),
      isFalse,
    );
  });

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

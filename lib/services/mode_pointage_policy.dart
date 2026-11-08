/// Règles des modes d'identification proposés sur l'accueil du pointage.
enum MethodePointage {
  codePin,
  qr,
  reconnaissanceFaciale,
  enrollementBorne,
}

class ModePointagePolicy {
  const ModePointagePolicy._();

  /// Le QR devient le geste principal lorsqu'il est activé ; sinon, le PIN
  /// demeure le mode principal par défaut.
  static MethodePointage principal({required bool qrActif}) =>
      qrActif ? MethodePointage.qr : MethodePointage.codePin;

  /// Modes de pointage réellement sélectionnables avant l'accueil.
  ///
  /// Un mode facial `required` ou `exclusive` reste seul au sélecteur : les
  /// éventuels replis autorisés restent proposés par le parcours facial lui-
  /// même, conformément à la configuration Admin. Le mode d'enrôlement borne
  /// n'est pas une méthode de pointage et n'est donc jamais listé ici.
  static List<MethodePointage> modesDisponibles({
    required bool qrActif,
    required bool reconnaissanceFacialeActive,
    String? modeFacial,
    bool repliFacialAutorise = true,
  }) {
    if (reconnaissanceFacialeActive &&
        (modeFacial == 'face_exclusive' ||
            modeFacial == 'face_required' ||
            !repliFacialAutorise)) {
      return [MethodePointage.reconnaissanceFaciale];
    }

    return [
      if (qrActif) MethodePointage.qr,
      MethodePointage.codePin,
      if (reconnaissanceFacialeActive)
        MethodePointage.reconnaissanceFaciale,
    ];
  }

  /// Le mode principal n'est jamais répété dans « Autres modes ».
  /// Le PIN reste accessible en repli lorsque le QR est le mode principal.
  static List<MethodePointage> autresModes({
    required bool qrActif,
    required bool reconnaissanceFacialeActive,
    required bool borneActive,
  }) => [
        if (qrActif) MethodePointage.codePin,
        if (reconnaissanceFacialeActive)
          MethodePointage.reconnaissanceFaciale,
        if (borneActive) MethodePointage.enrollementBorne,
      ];
}

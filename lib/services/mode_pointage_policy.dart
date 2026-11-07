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

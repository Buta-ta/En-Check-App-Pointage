/// Règles des modes d'identification proposés sur l'accueil du pointage.
enum MethodePointage {
  codePin,
  qr,
  reconnaissanceFaciale,
  enrollementBorne,
}

class ModePointagePolicy {
  const ModePointagePolicy._();

  /// Restaure seulement un mode mémorisé qui est encore autorisé.
  /// La préférence reste attachée à l'entreprise (clé gérée par l'écran) ;
  /// une option désactivée ne peut ainsi contourner la configuration courante.
  static MethodePointage? choixMemorise({
    required List<MethodePointage> modesDisponibles,
    required String? valeurMemorisee,
  }) {
    for (final mode in modesDisponibles) {
      if (mode.name == valeurMemorisee) return mode;
    }
    return null;
  }

  /// L'enrôlement n'est pertinent que sur une borne où la reconnaissance
  /// faciale a réellement été choisie comme mode actif.
  static bool afficherActionEnrolement({
    required bool borneActive,
    required MethodePointage? modeChoisi,
  }) =>
      borneActive && modeChoisi == MethodePointage.reconnaissanceFaciale;

  /// Le QR devient le geste principal lorsqu'il est activé ; sinon, le PIN
  /// demeure le mode principal par défaut.
  static MethodePointage principal({required bool qrActif}) =>
      qrActif ? MethodePointage.qr : MethodePointage.codePin;

  /// Modes de pointage réellement sélectionnables avant l'accueil.
  ///
  /// Le mode facial `exclusive` reste seul au sélecteur. Un mode `required`
  /// peut proposer le PIN/QR si la configuration autorise le repli : le visage
  /// reste le choix recommandé, mais l'absence de profils enrôlés ne bloque
  /// pas les autres méthodes explicitement permises. Le mode d'enrôlement borne
  /// n'est pas une méthode de pointage et n'est donc jamais listé ici.
  static List<MethodePointage> modesDisponibles({
    required bool qrActif,
    required bool reconnaissanceFacialeActive,
    String? modeFacial,
    bool repliFacialAutorise = true,
  }) {
    if (reconnaissanceFacialeActive &&
        (modeFacial == 'face_exclusive' || !repliFacialAutorise)) {
      return [MethodePointage.reconnaissanceFaciale];
    }

    return [
      if (qrActif) MethodePointage.qr,
      MethodePointage.codePin,
      if (reconnaissanceFacialeActive)
        MethodePointage.reconnaissanceFaciale,
    ];
  }

  /// Sélectionne automatiquement une méthode seulement si une seule est
  /// autorisée. S'il y en a plusieurs, un choix explicite est requis à chaque
  /// démarrage, même si un dernier choix est mémorisé.
  static MethodePointage? modeAutoSelectionne(
    List<MethodePointage> modesDisponibles,
  ) =>
      modesDisponibles.length == 1 ? modesDisponibles.single : null;

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

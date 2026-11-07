import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/local_database.dart';
import '../services/connectivity_service.dart';
import '../services/heure_pointage.dart'; // ⭐ LIVRAISON 19 — conversion d'heure
import '../services/pause_service.dart'; // ⏸ LOT D — les pauses
import '../services/geofencing_service.dart'; // ⏸ LOT D — mention « Hors site »
import '../services/motif_service.dart';
import '../services/historique_periode.dart';
import '../theme/accueil_palette.dart';
import '../widgets/sans_etirement.dart';

class HistoriqueScreen extends StatefulWidget {
  final Map<String, dynamic> employee;

  const HistoriqueScreen({super.key, required this.employee});

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  List<Map<String, dynamic>> pointages = [];
  bool chargement = true;

  /// Date consultée dans la période de sept jours déjà autorisée à l'employé.
  /// Le calendrier ne fait que filtrer les lignes déjà chargées.
  late DateTime _dateSelectionnee;
  bool _limiteAtteinte = false;

  /// 🔄 CONTRAT ÉTAPE 2 (25/10/2026) — fiche rafraîchie via le jeton de la
  /// session (le serveur en résout le titulaire) : poste, département et
  /// horaires à jour. `null` tant que le rafraîchissement n'a pas abouti.
  Map<String, dynamic>? _ficheFraiche;
  String? _nomEntreprise;

  /// Raison métier d'un refus de session (jeton expiré, ancien jeton…),
  /// affichée honnêtement au lieu de laisser croire que tout va bien.
  String? _sessionRaison;

  /// La fiche AFFICHÉE : rafraîchie si possible, sinon celle transmise par
  /// l'écran précédent — mêmes identifiants, le rafraîchissement par jeton
  /// n'étant accepté que pour le même employé.
  Map<String, dynamic> get _fiche => _ficheFraiche ?? widget.employee;

  bool get _estSombre => Theme.of(context).brightness == Brightness.dark;

  AccueilPalette get _palette =>
      AccueilPalette.pour(MotifService.actif.value, _estSombre);

  Color get _accentAmbre => _estSombre
      ? const Color(0xFFE0BE82)
      : EnCheckColors.terreChaude;

  /// Message à afficher quand la lecture a échoué. Sans lui, un refus
  /// d'autorisation sur la table `attendances` produisait une liste vide et
  /// l'écran affichait « Aucun pointage » : l'employé croyait sa journée
  /// perdue alors que le serveur refusait simplement la lecture.
  String? erreur;

  // ═══════════════════════════════════════════════════════════
  //  ⏸ LES PAUSES — fiche « LOT D » (16/10/2026)
  //  La carte pause vit ICI : c'est l'écran où l'employé s'est identifié
  //  (matricule + PIN) — le bon endroit pour « Je pars en pause » et
  //  « ▶ Je reprends ».
  // ═══════════════════════════════════════════════════════════
  Map<String, dynamic>? _pauseEtat;    // pause ouverte (debut, motif…)
  Map<String, dynamic>? _pausePrevue;  // créneau du planning (calculé par la base)
  bool _pausePret = false;
  bool _horsSite = false;              // 📍 mention informative, JAMAIS bloquante
  bool _pauseActionEnCours = false;    // verrou anti-double-tap
  Timer? _rappelTimer;
  bool _rappelAffiche = false;

  /// Les pointages de la journée EN COURS, du plus ancien au plus récent.
  ///
  /// Le découpage se fait sur minuit LOCAL (HeurePointage), pas sur minuit
  /// UTC : sans cette précaution, un pointage de 00:30 à Cotonou serait
  /// rangé dans la veille et la journée paraîtrait vide.
  List<Map<String, dynamic>> get _pointagesDuJour {
    final aujourdhui = HeurePointage.jourDePointage(
      {'check_time': DateTime.now().toIso8601String()},
    );

    final duJour = pointages
        .where((p) => HeurePointage.jourDePointage(p) == aujourdhui)
        .toList()
      ..sort(HeurePointage.parInstantCroissant);

    return duJour;
  }

  @override
  void initState() {
    super.initState();
    _dateSelectionnee = HistoriquePeriode.jour(HeurePointage.maintenant());
    _chargerHistorique();
    _chargerPause();
    _rafraichirProfil();
    _chargerNomEntreprise();
  }

  /// 🔄 Contrat étape 2 : la fiche de la session se rafraîchit par le jeton
  /// (encheck_employe_profil). Refus métier → message honnête ; erreur
  /// technique → silencieux (l'historique affiche déjà les siennes) ;
  /// hors-ligne → on garde la fiche transmise.
  Future<void> _rafraichirProfil() async {
    if (!ConnectivityService.isOnline) return;
    final rafraichi = await SupabaseService.rafraichirProfilDeSession(
      employeeIdAttendu: _fiche['id'] as String,
      onRefus: (raison) {
        if (!mounted) return;
        setState(() => _sessionRaison = raison);
      },
    );
    if (rafraichi != null && mounted) {
      setState(() => _ficheFraiche = rafraichi);
    }
  }

  Future<void> _chargerNomEntreprise() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nom = prefs.getString('enterprise_name')?.trim();
      if (mounted && nom != null && nom.isNotEmpty) {
        setState(() => _nomEntreprise = nom);
      }
    } catch (_) {
      // Le nom local est un complément d'affichage, jamais une condition d'accès.
    }
  }

  /// 💬 Libellé honnête selon la raison de refus de session.
  String _messageSession(String raison) {
    switch (raison) {
      case 'reauthentification_requise':
        return 'Session ancienne : reconnectez-vous avec votre matricule et '
            'votre PIN pour actualiser votre fiche.';
      case 'jeton_expire':
        return 'Session expirée : reconnectez-vous pour actualiser vos données.';
      case 'jeton_revoque':
        return 'Session fermée : reconnectez-vous pour continuer.';
      case 'employe_inactif':
        return 'Compte désactivé : contactez votre responsable.';
      case 'entreprise_inactive':
        return 'Entreprise désactivée : contactez votre responsable.';
      default:
        return 'Impossible de vérifier la session : reconnectez-vous.';
    }
  }

  @override
  void dispose() {
    _rappelTimer?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  ⏸ LES PAUSES — chargement + gestes (fiche LOT D)
  // ═══════════════════════════════════════════════════════════

  /// Charge : la pause ouverte, le créneau prévu (calculé PAR LA BASE),
  /// la mention « Hors site » (indicative) — puis programme le rappel de
  /// reprise si la pause dure déjà depuis trop longtemps.
  Future<void> _chargerPause() async {
    try {
      final employeId = _fiche['id'] as String;
      final entrepriseId = _fiche['enterprise_id']?.toString();

      final etat = await PauseService.etatPause(employeId);

      Map<String, dynamic>? prevue;
      if (entrepriseId != null && entrepriseId.isNotEmpty) {
        prevue = await PauseService.pausePrevue(
            employeeId: employeId, enterpriseId: entrepriseId);
      }

      // « 📍 Hors site » : purement informatif — la pause reste possible
      // partout (fiche LOT D : le géo-fencage ne bloque JAMAIS le bouton).
      var horsSite = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('module_geolocalisation') == true &&
            entrepriseId != null &&
            entrepriseId.isNotEmpty) {
          final position =
              await GeofencingService.obtenirPosition(tentatives: 1);
          if (position != null) {
            final zone = await GeofencingService.verifierZone(
                enterpriseId: entrepriseId, position: position);
            horsSite = zone['is_within_zone'] == false;
          }
        }
      } catch (_) {
        // Pas de GPS / permission refusée : on n'affiche simplement rien.
      }

      if (!mounted) return;
      setState(() {
        _pauseEtat = etat;
        _pausePrevue = prevue;
        _horsSite = horsSite;
        _pausePret = true;
      });
      _programmerRappel();
    } catch (e) {
      print('⚠️ chargement de la pause : $e');
      if (mounted) setState(() => _pausePret = true);
    }
  }

  /// true = service en cours, false = absence certaine, null = invérifiable.
  bool? _etatServiceDuJour() {
    if (erreur != null || chargement) return null;
    if (!ConnectivityService.isOnline && pointages.isEmpty) return null;
    final duJour = _pointagesDuJour;
    if (duJour.isEmpty) return false;
    return duJour.last['check_type'] == 'in';
  }

  /// « Je pars en pause » — marche aussi hors-ligne (file d'attente locale).
  Future<void> _partirEnPause() async {
    if (_pauseActionEnCours) return; // verrou anti-double-tap (fiche LOT D)
    // ⭐ CHOIX VALIDÉ DU FONDATEUR (4 nov 2026, option 2) : sans service
    // confirmé, on AVERTIT puis la personne confirme ou annule. Si l'état
    // est invérifiable, on le dit au lieu d'affirmer une absence.
    final etatService = _etatServiceDuJour();
    if (etatService != true) {
      final continuer = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(etatService == false
              ? 'Pas de service en cours'
              : 'Service non vérifié'),
          content: Text(etatService == false
              ? "Vous n'avez pas de service en cours. "
                  "Voulez-vous quand même partir en pause ?"
              : "Impossible de vérifier votre service en cours. "
                  "Voulez-vous partir en pause ?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continuer')),
          ],
        ),
      );
      if (continuer != true || !mounted) return;
    }
    setState(() => _pauseActionEnCours = true);
    try {
      final etat = await PauseService.partirEnPause(
        employeeId: _fiche['id'] as String,
        enterpriseId: _fiche['enterprise_id']?.toString(),
        motif: _pauseEtat?['motif'] as String?,
      );
      if (!mounted) return;
      setState(() {
        _pauseEtat = etat;
        _rappelAffiche = false;
        _pauseActionEnCours = false;
      });
      _programmerRappel();
      final horsLigne = !ConnectivityService.isOnline;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          horsLigne
              ? '⏸ Pause enregistrée hors-ligne : elle sera synchronisée.'
              : '⏸ Pause enregistrée. Bonne pause !',
          style: TextStyle(color: _palette.surPrimaire),
        ),
        backgroundColor: _estSombre ? _palette.primaire : EnCheckColors.terreChaude,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _pauseActionEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Impossible d'enregistrer la pause : $e"),
      ));
    }
  }

  /// « ▶ Je reprends » — marche aussi hors-ligne.
  Future<void> _reprendrePause() async {
    if (_pauseActionEnCours) return;
    setState(() => _pauseActionEnCours = true);
    try {
      await PauseService.reprendre(
        employeeId: _fiche['id'] as String,
        enterpriseId: _fiche['enterprise_id']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        if (_pauseEtat != null) _pauseEtat!['debut'] = null;
        _rappelAffiche = false;
        _pauseActionEnCours = false;
      });
      _rappelTimer?.cancel();
      final horsLigne = !ConnectivityService.isOnline;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(horsLigne
            ? '▶ Reprise enregistrée hors-ligne : elle sera synchronisée.'
            : '▶ Reprise enregistrée. Bon service !'),
        backgroundColor: EnCheckColors.succes,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _pauseActionEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Impossible d'enregistrer la reprise : $e"),
      ));
    }
  }

  /// Motif FACULTATIF — retoucher la même pastille efface le motif.
  Future<void> _choisirMotif(String? motif) async {
    final etat = _pauseEtat;
    if (etat == null || etat['debut'] == null) return;
    final nouveau = (etat['motif'] == motif) ? null : motif;
    setState(() {
      etat['motif'] = nouveau;
      _pauseEtat = etat;
    });
    await PauseService.changerMotif(
        employeeId: _fiche['id'] as String, motif: nouveau);
  }

  /// Rappel LOCAL de reprise (75 min) : bannière + SnackBar, jamais une
  /// alarme, jamais un SMS, jamais une notification payante (fiche LOT D).
  void _programmerRappel() {
    _rappelTimer?.cancel();
    final etat = _pauseEtat;
    if (etat == null || etat['debut'] == null) return;
    final debut = HeurePointage.instantDe(etat['debut'] as String);
    if (debut == null) return;

    void afficher() {
      if (_rappelAffiche || !mounted) return;
      setState(() => _rappelAffiche = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Toujours en pause ? Touche « Je reprends » si tu es de retour.',
          style: TextStyle(color: _palette.surPrimaire),
        ),
        backgroundColor: _estSombre ? _palette.primaire : EnCheckColors.terreChaude,
      ));
    }

    if (PauseService.rappelDepasse(debut)) {
      afficher();
      return;
    }
    final echeance =
        debut.add(const Duration(minutes: PauseService.rappelMinutes));
    _rappelTimer = Timer(echeance.difference(DateTime.now().toUtc()), afficher);
  }

  // ═══════════════════════════════════════════════════════════
  //  ⏸ LA CARTE PAUSE (fiche LOT D)
  // ═══════════════════════════════════════════════════════════

  Widget _pastilleHorsSite() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _accentAmbre.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '📍 Hors site',
          style: TextStyle(fontSize: 11, color: _accentAmbre),
        ),
      );

  Widget _construireCartePause() {
    // Variables locales non-nulles : pas de promotion hasardeuse.
    final etat = _pauseEtat;
    final debutIso = etat == null ? null : etat['debut'] as String?;
    final motifActif = etat == null ? null : etat['motif'] as String?;

    // État réel du service : la ligne d'entrée elle-même n'est rendue qu'une
    // fois dans la liste chronologique ci-dessous.
    String? serviceDepuis;
    final duJour = _pointagesDuJour;
    if (duJour.isNotEmpty && duJour.last['check_type'] == 'in') {
      final heure = HeurePointage.heureDePointage(duJour.last);
      serviceDepuis = heure.length >= 5 ? heure.substring(0, 5) : heure;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: debutIso != null
              ? _accentAmbre.withOpacity(0.55)
              : EnCheckColors.succes.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (debutIso != null) ...[
            Row(
              children: [
                Icon(Icons.pause_circle, color: _accentAmbre, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'En pause depuis '
                    '${PauseService.heureCourteDe(debutIso)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (_horsSite) _pastilleHorsSite(),
              ],
            ),

            // L'annonce du planning — calculée PAR LA BASE
            // (`encheck_pause_prevue`), jamais par l'app.
            if (_pausePrevue?['trouvee'] == true) ...[
              const SizedBox(height: 8),
              Text(
                'Pause prévue ${_pausePrevue!['debut']}–${_pausePrevue!['fin']}',
                style: TextStyle(
                  fontSize: 12,
                  color: _palette.texteSecondaire,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // 🕒 Rappel de reprise (75 min) — local et gratuit.
            if (_rappelAffiche) ...[
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accentAmbre.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.alarm, size: 16, color: _accentAmbre),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Toujours en pause ? Touche « Je reprends » si tu es de retour.',
                        style: TextStyle(fontSize: 12, color: _accentAmbre),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Text('Motif facultatif :',
                style: TextStyle(
                    fontSize: 12, color: _palette.texteSecondaire)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final motif in PauseService.motifs)
                  ChoiceChip(
                    label: Text(motif),
                    selected: motifActif == motif,
                    selectedColor: _accentAmbre.withOpacity(0.2),
                    onSelected: (_) => _choisirMotif(motif),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pauseActionEnCours ? null : _reprendrePause,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Je reprends'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EnCheckColors.succes,
                  foregroundColor: EnCheckColors.blanc,
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  serviceDepuis != null
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: serviceDepuis != null
                      ? EnCheckColors.succes
                      : _palette.texteSecondaire,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    serviceDepuis != null
                        ? 'Service en cours'
                        : 'Pas de service en cours',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (_horsSite) _pastilleHorsSite(),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pauseActionEnCours ? null : _partirEnPause,
                icon: const Icon(Icons.pause),
                label: const Text('Je pars en pause'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _estSombre ? _accentAmbre : EnCheckColors.terreChaude,
                  foregroundColor: _estSombre
                      ? const Color(0xFF2A241A)
                      : EnCheckColors.blanc,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
// 📥 CHARGEMENT AVEC FUSION INTELLIGENTE (CORRIGÉ)
// ═══════════════════════════════════════════════════════════
  Future<void> _chargerHistorique() async {
    setState(() {
      chargement = true;
      erreur = null;
      _limiteAtteinte = false;
    });

    try {
      List<Map<String, dynamic>> tousLesPointages = [];

      // 1. Charger depuis Supabase si en ligne
      if (ConnectivityService.isOnline) {
        try {
          // ⭐ PTG-01.4 : le contrat d'accès (RPC) autorise jusqu'à 500
          // événements par appel — on demande 500 pour ne masquer aucun
          // pointage des 7 jours, sans jamais contourner la sécurité.
          final supabaseData = await SupabaseService.getHistoriquePointages(
              _fiche['id'],
              limite: 500);
          tousLesPointages.addAll(supabaseData);
          if (supabaseData.length >= 500) _limiteAtteinte = true;
        } catch (e) {
          print('Erreur chargement Supabase: $e');
        }
        // getHistoriquePointages avale son exception et renvoie [] : sans ce
        // relevé, l'échec était invisible et ressemblait à une journée vide.
        erreur = SupabaseService.derniereErreur;
      }

      // 2. Charger les pointages pending locaux
      try {
        final pendingData = await LocalDatabase.getPointagesPendingParEmploye(_fiche['id']);

        // ✅ FUSION : Ajouter les pending, mais éviter les doublons si déjà synchronisés
        for (var localPointage in pendingData) {
          // ⭐ LIVRAISON 19 — le doublon se détecte sur l'INSTANT RÉEL, et
          //    d'abord sur la référence `client_ref` créée AU MOMENT du
          //    pointage : c'est une égalité exacte, insensible au réglage du
          //    téléphone comme aux quelques secondes qui séparent l'ancrage
          //    serveur de l'horloge de la tablette (l'ancienne règle « moins de
          //    2 secondes » était trop courte pour ces cas-là).
          final existeDeja = tousLesPointages.any(
            (p) => HeurePointage.memePointage(localPointage, p),
          );

          if (!existeDeja) {
            localPointage['sync_pending'] = true;
            tousLesPointages.add(localPointage);
          }
        }
      } catch (e) {
        print('Erreur chargement pointages locaux: $e');
      }

      // 3. Trier par date (plus récent en premier)
      // ⭐ LIVRAISON 19 — sur l'instant réel, avec la même règle que partout
      //    ailleurs dans l'application (services/heure_pointage.dart).
      tousLesPointages.sort(HeurePointage.parInstantDecroissant);

      setState(() {
        pointages = tousLesPointages;
        chargement = false;
      });
    } catch (e) {
      print('Erreur chargement historique: $e');
      setState(() {
        chargement = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📸 CONSTRUIRE L'AVATAR (PHOTO OU INITIALES)
  // ═══════════════════════════════════════════════════════════
  Widget _construireAvatar({double taille = 80}) {
    final photoUrl = _fiche['photo_url'];
    final prenom = _fiche['first_name'] ?? '';
    final nom = _fiche['last_name'] ?? '';
    final initiales = '${prenom.isNotEmpty ? prenom[0] : ''}${nom.isNotEmpty ? nom[0] : ''}';

    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        color: EnCheckColors.sableDore,
        shape: BoxShape.circle,
        border: Border.all(color: EnCheckColors.blanc, width: 3),
        boxShadow: [
          BoxShadow(
            color: EnCheckColors.noirElegant.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipOval(
        child:
        photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
          photoUrl,
          fit: BoxFit.cover,
          width: taille,
          height: taille,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            // Une seule animation de chargement par page (PTG-01) : pendant
            // le chargement de la photo, on montre les initiales — pas un
            // second « spinner ».
            return _construireInitiales(initiales, taille: taille);
          },
          errorBuilder: (context, error, stackTrace) {
            return _construireInitiales(initiales, taille: taille);
          },
        )
            : _construireInitiales(initiales, taille: taille),
      ),
    );
  }

  Widget _construireInitiales(String initiales, {double taille = 80}) {
    return Container(
      color: EnCheckColors.sableDore,
      child: Center(
        child: Text(
          initiales.toUpperCase(),
          style: TextStyle(
            color: EnCheckColors.brunProfond,
            fontSize: taille * 0.35,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 📱 TÉLÉPHONE (fiche « Affichage mobile ») : petit appareil = largeur
    // étroite OU fenêtre très courte (paysage).
    final tailleFenetre = MediaQuery.sizeOf(context);
    final bool estTelephone =
        tailleFenetre.width < 620 || tailleFenetre.height < 520;

    final palette = _palette;
    return Scaffold(
      backgroundColor: palette.fond,
      appBar: AppBar(
        backgroundColor: palette.navFond,
        foregroundColor: palette.texte,
        elevation: 0,
        title: const Text(
          'HISTORIQUE',
          style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w500),
        ),
        centerTitle: true,
        actions: [
          if (!_estAujourdHui)
            IconButton(
              tooltip: "Revenir à aujourd'hui",
              onPressed: _revenirAujourdhui,
              icon: const Icon(Icons.today_outlined),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          IconButton(
            key: const Key('historique-bouton-calendrier'),
            tooltip: 'Choisir un jour dans les 7 derniers jours',
            onPressed: _ouvrirCalendrier,
            icon: const Icon(Icons.calendar_month_outlined),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
      body: SansEtirement(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          // ═══════════════════════════════════════════
          // 👤 EN-TÊTE EMPLOYÉ AVEC PHOTO
          // ═══════════════════════════════════════════
          ListenableBuilder(
            listenable: MotifService.actif,
            builder: (context, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              // 🧵 Décor : le motif culturel choisi, derrière la section
              // profil (photo, nom, matricule, métier/département).
              decoration: BoxDecoration(
                color: EnCheckColors.brunProfond,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                image: DecorationImage(
                  image: AssetImage(MotifService.actif.value.asset),
                  fit: BoxFit.fitWidth,
                  repeat: ImageRepeat.repeatY,
                  colorFilter: const ColorFilter.mode(
                    Color(0x8C2A1B12),
                    BlendMode.srcATop,
                  ),
                ),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xC92A1B12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: Column(
                children: [
                _construireAvatar(taille: estTelephone ? 64 : 80),
                SizedBox(height: estTelephone ? 10 : 12),

                Text(
                  '${_fiche['first_name']} ${_fiche['last_name']}',
                  style: TextStyle(
                    color: EnCheckColors.blanc,
                    fontSize: estTelephone ? 20 : 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  _fiche['matricule'] ?? '',
                  style: const TextStyle(
                    color: EnCheckColors.sableDore,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),

                SizedBox(height: estTelephone ? 10 : 12),

                if (_fiche['position'] != null ||
                    _fiche['department'] != null || _nomEntreprise != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: EnCheckColors.blanc.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (_fiche['position'] != null &&
                            _fiche['position'].toString().isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.work_outline,
                                color: EnCheckColors.sableDore,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _fiche['position'],
                                style: const TextStyle(
                                  color: EnCheckColors.blanc,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                        if (_fiche['position'] != null &&
                            _fiche['position'].toString().isNotEmpty &&
                            _fiche['department'] != null &&
                            _fiche['department'].toString().isNotEmpty)
                          const SizedBox(height: 6),

                        if (_fiche['department'] != null &&
                            _fiche['department'].toString().isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.business_outlined,
                                color: EnCheckColors.sableDore,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _fiche['department'],
                                style: TextStyle(
                                  color: EnCheckColors.blanc.withOpacity(0.8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        if (_nomEntreprise != null) ...[
                          if ((_fiche['position'] != null &&
                                  _fiche['position'].toString().isNotEmpty) ||
                              (_fiche['department'] != null &&
                                  _fiche['department'].toString().isNotEmpty))
                            const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.domain_outlined,
                                  color: EnCheckColors.sableDore, size: 15),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _nomEntreprise!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: EnCheckColors.blanc.withOpacity(0.82),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ═══════════════════════════════════════════
          // ⏸ LES PAUSES (fiche LOT D) — la carte « Ma journée »
          // ═══════════════════════════════════════════
          if (_pausePret && _estAujourdHui) ...[
            _construireCartePause(),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 12),

          // 💬 Contrat étape 2 : un refus de session (expirée, ancien jeton…)
          // s'affiche honnêtement, au lieu de laisser croire que la fiche
          // affichée est toujours la vérité.
          if (_sessionRaison != null) ...[
            _construireBandeauSession(),
            const SizedBox(height: 12),
          ],

          if (chargement)
            SizedBox(
              height: 220,
              child: Center(
                child: CircularProgressIndicator(color: _palette.lien),
              ),
            )
          else if (pointages.isEmpty && erreur != null)
            SizedBox(height: 260, child: _construireErreur())
          else if (pointages.isEmpty)
            SizedBox(height: 220, child: _construireVide())
          else
            _zoneSeptJours(),
          ],
          ),
        ),
      ),
    );
  }

  /// 💬 Bandeau de session — contrat étape 2 (25/10/2026).
  Widget _construireBandeauSession() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _accentAmbre.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentAmbre.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock, color: _accentAmbre, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _messageSession(_sessionRaison!),
              style: TextStyle(
                color: _palette.texte,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construireVide() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history,
              size: 80, color: _palette.texteSecondaire.withOpacity(0.5)),
          const SizedBox(height: 20),
          Text('Aucun pointage',
              style: TextStyle(color: _palette.texteSecondaire, fontSize: 18)),
        ],
      ),
    );
  }

  /// « Aucun pointage » voulait dire deux choses différentes : la journée est
  /// vide, ou le serveur a refusé la lecture. Cet écran tranche. Les pointages
  /// déjà enregistrés localement restent affichés au-dessus s'il y en a — on
  /// n'arrive ici que quand la liste est entièrement vide.
  Widget _construireErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 70, color: _palette.texteSecondaire.withOpacity(0.5)),
            const SizedBox(height: 20),
            Text(
              'Historique indisponible',
              style: TextStyle(
                  color: _palette.texteSecondaire,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              erreur!,
              style: TextStyle(
                  color: _palette.texteSecondaire.withOpacity(0.8),
                  fontSize: 14,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _chargerHistorique,
              icon: Icon(Icons.refresh, color: _palette.lien),
              label: Text('Réessayer', style: TextStyle(color: _palette.lien)),
            ),
          ],
        ),
      ),
    );
  }

  bool get _estAujourdHui => HistoriquePeriode.jour(_dateSelectionnee) ==
      HistoriquePeriode.jour(HeurePointage.maintenant());

  String _cleJourLocal(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _ouvrirCalendrier() async {
    final maintenant = HeurePointage.maintenant();
    final palette = _palette;
    final surfaceCalendrier =
        _estSombre ? palette.surface : EnCheckColors.cremePapier;
    final choisi = await showDatePicker(
      context: context,
      initialDate: _dateSelectionnee,
      firstDate: HistoriquePeriode.premierJourAutorise(maintenant),
      lastDate: HistoriquePeriode.jour(maintenant),
      selectableDayPredicate: (date) =>
          HistoriquePeriode.autorise(date, maintenant),
      helpText: 'Consulter les pointages du jour',
      cancelText: 'ANNULER',
      confirmText: 'CHOISIR',
      builder: (context, child) {
        final theme = Theme.of(context);
        final couleurs = theme.colorScheme.copyWith(
          primary: palette.primaire,
          onPrimary: palette.surPrimaire,
          secondary: palette.lien,
          surface: surfaceCalendrier,
          onSurface: palette.texte,
          onSurfaceVariant: palette.texteSecondaire,
          surfaceContainerLowest: surfaceCalendrier,
          surfaceContainerLow: surfaceCalendrier,
          surfaceContainer: surfaceCalendrier,
          surfaceContainerHigh: surfaceCalendrier,
          surfaceContainerHighest: surfaceCalendrier,
        );
        return Theme(
          data: theme.copyWith(
            colorScheme: couleurs,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: palette.lien),
            ),
            datePickerTheme: theme.datePickerTheme.copyWith(
              backgroundColor: surfaceCalendrier,
              headerBackgroundColor: palette.primaire,
              headerForegroundColor: palette.surPrimaire,
              dividerColor: palette.filet,
              cancelButtonStyle:
                  TextButton.styleFrom(foregroundColor: palette.lien),
              confirmButtonStyle:
                  TextButton.styleFrom(foregroundColor: palette.lien),
            ),
          ),
          child: child!,
        );
      },
    );
    if (choisi == null || !mounted) return;
    setState(() => _dateSelectionnee = HistoriquePeriode.jour(choisi));
  }

  void _revenirAujourdhui() {
    setState(() =>
        _dateSelectionnee = HistoriquePeriode.jour(HeurePointage.maintenant()));
  }

  List<Map<String, dynamic>> _pointagesDateSelectionnee() =>
      HistoriquePeriode.pointagesDuJour(pointages, _dateSelectionnee);

  List<Map<String, dynamic>> _pointagesDateInconnue() => pointages
      .where((p) => HeurePointage.jourDePointage(p) == HeurePointage.jourInconnu)
      .toList();

  Widget _zoneSeptJours() {
    final lignes = _pointagesDateSelectionnee();
    final datesIllisibles = _pointagesDateInconnue();
    final enfants = <Widget>[];
    if (lignes.isEmpty) {
      final date = _dateSelectionnee;
      final dateTexte = '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/${date.year}';
      enfants.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined,
                size: 52, color: _palette.lien.withOpacity(0.75)),
            const SizedBox(height: 12),
            Text(
              'Aucun pointage le $dateTexte.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _palette.texteSecondaire, fontSize: 16),
            ),
          ],
        ),
      ));
    } else {
      enfants.add(_construireJour(_cleJourLocal(_dateSelectionnee), lignes));
    }
    if (datesIllisibles.isNotEmpty) {
      enfants.add(const Padding(
        padding: EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          'Ces événements ont une date illisible et ne sont pas inclus dans la journée sélectionnée.',
          style: TextStyle(color: EnCheckColors.erreur, fontSize: 12, height: 1.35),
        ),
      ));
      enfants.add(_construireEvenementsInconnus(datesIllisibles));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        key: const Key('historique-liste-evenements'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: enfants,
      ),
    );
  }

  Widget _construireEvenementsInconnus(
      List<Map<String, dynamic>> evenements) {
    return Container(
      key: const Key('historique-evenements-date-inconnue'),
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnCheckColors.erreur.withOpacity(0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Date inconnue · ${evenements.length} événement${evenements.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: EnCheckColors.erreur,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (var i = 0; i < evenements.length; i++)
            _construireEvenement(evenements[i], i, dateInconnue: true),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ⏰ CALCULER LES HEURES TRAVAILLÉES (CORRECTION FINALE - PRÉCISION SECONDES)
  // ═══════════════════════════════════════════════════════════
  Map<String, dynamic> _calculerHeures(List<Map<String, dynamic>> pointagesJour) {
    // ⭐ LIVRAISON 19 — tri sur l'instant réel, par la fonction commune :
    //    une ligne du serveur (UTC) et une ligne encore en file d'attente
    //    (heure murale de la tablette) se classent sur le même axe de temps.
    //    Voir services/heure_pointage.dart.
    pointagesJour.sort(HeurePointage.parInstantCroissant);

    Duration totalDuree = Duration.zero;
    List<Map<String, dynamic>> sessions = [];
    Map<String, dynamic>? entreeEnCours;
    bool sortiManquante = false;

    for (var pointage in pointagesJour) {
      final type = pointage['check_type'];
      final heure = HeurePointage.instant(pointage);

      if (type == 'in') {
        if (entreeEnCours != null) {
          sessions.add({'entree': entreeEnCours, 'sortie': null, 'duree': null});
          sortiManquante = true;
        }
        entreeEnCours = pointage;
      } else if (type == 'out') {
        if (entreeEnCours != null) {
          final heureEntree = HeurePointage.instant(entreeEnCours);
          // ⭐ LIVRAISON 19 — une durée ne se calcule qu'entre deux instants
          //    lisibles : sinon on affiche « ? » au lieu d'un chiffre faux.
          if (heure != null && heureEntree != null) {
            final duree = heure.difference(heureEntree);
            totalDuree += duree;

            sessions.add({
              'entree': entreeEnCours,
              'sortie': pointage,
              'duree': duree
            });
          } else {
            sessions.add({'entree': entreeEnCours, 'sortie': pointage, 'duree': null});
          }
          entreeEnCours = null;
        } else {
          sessions.add({'entree': null, 'sortie': pointage, 'duree': null});
        }
      }
    }

    if (entreeEnCours != null) {
      sessions.add({'entree': entreeEnCours, 'sortie': null, 'duree': null});
      sortiManquante = true;
    }

    return {
      'sessions': sessions,
      'totalDuree': totalDuree,
      'sortiManquante': sortiManquante
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 📊 FORMATER LA DURÉE (AFFICHAGE EXACT AVEC SECONDES)
  // ═══════════════════════════════════════════════════════════
  String _formaterDuree(Duration duree) {
    final totalSecondes = duree.inSeconds;

    // ⭐ LIVRAISON 19 — une durée négative signale des pointages incohérents
    //    (une sortie datée avant son entrée) : on n'affiche JAMAIS un temps
    //    négatif à un employé.
    if (totalSecondes <= 0) return '0sec';

    final heures = totalSecondes ~/ 3600;
    final minutes = (totalSecondes % 3600) ~/ 60;
    final secondes = totalSecondes % 60;

    if (heures == 0 && minutes == 0) {
      return '${secondes}sec';
    }

    if (heures == 0) {
      if (secondes == 0) return '${minutes}min';
      return '${minutes}min ${secondes}sec';
    }

    if (minutes == 0 && secondes == 0) return '${heures}h';
    if (secondes == 0) return '${heures}h${minutes.toString().padLeft(2, '0')}';

    return '${heures}h${minutes.toString().padLeft(2, '0')}min ${secondes}sec';
  }

  // ⭐ LIVRAISON 19 — la conversion d'heure ne se fait PLUS ici : elle vit dans
  //    un seul fichier (services/heure_pointage.dart). L'ancienne version
  //    affichait l'heure telle quelle, donc « 07:30 » pour un pointage de 08:30
  //    à Cotonou (UTC+1) — et l'inverse à Montréal (UTC-4).
  Widget _construireJour(
      String jour, List<Map<String, dynamic>> pointagesJour) {
    final date = DateTime.tryParse(jour);
    final maintenant = HeurePointage.maintenant();
    final hier = DateTime(maintenant.year, maintenant.month, maintenant.day - 1);
    String titreJour;
    if (date == null) {
      titreJour = 'Journée inconnue';
    } else if (_cleJourLocal(date) == _cleJourLocal(maintenant)) {
      titreJour = "Aujourd'hui";
    } else if (_cleJourLocal(date) == _cleJourLocal(hier)) {
      titreJour = 'Hier';
    } else {
      const jours = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
      const mois = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];
      titreJour = '${jours[date.weekday % 7]} ${date.day} ${mois[date.month - 1]}';
    }

    final calcul = _calculerHeures(List.from(pointagesJour));
    final totalDuree = calcul['totalDuree'] as Duration;
    final sortiManquante = calcul['sortiManquante'] as bool;

    return Container(
      key: const Key('historique-carte-jour'),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _palette.bordure.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: EnCheckColors.brunProfond.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titreJour, style: TextStyle(
                      color: _palette.texte,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    )),
                    const SizedBox(height: 3),
                    Text(
                      '${pointagesJour.length} événement${pointagesJour.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: _palette.texteSecondaire, fontSize: 12),
                    ),
                  ],
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (sortiManquante) ...[
                    const Icon(Icons.warning_amber_rounded,
                        color: EnCheckColors.erreur, size: 19),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (sortiManquante ? EnCheckColors.erreur : _palette.lien).withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formaterDuree(totalDuree),
                      style: TextStyle(
                        color: sortiManquante ? EnCheckColors.erreur : _palette.lien,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          Divider(height: 1, color: _palette.filet),
          for (var i = 0; i < pointagesJour.length; i++)
            _construireEvenement(pointagesJour[i], i),
          if (_limiteAtteinte)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Historique limité aux 500 derniers événements autorisés.',
                style: TextStyle(
                    color: _palette.texteSecondaire, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _construireEvenement(
      Map<String, dynamic> pointage, int index,
      {bool dateInconnue = false}) {
    final estEntree = pointage['check_type'] == 'in';
    final enAttente = pointage['sync_pending'] == true;
    final couleur = estEntree ? _palette.lien : _accentAmbre;
    final heure = HeurePointage.heureDePointage(pointage);
    final heureCourte = heure.length >= 5 ? heure.substring(0, 5) : heure;

    return Container(
      key: Key('historique-evenement-${dateInconnue ? 'inconnu-' : ''}$index'),
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: index == 0
            ? null
            : Border(top: BorderSide(color: _palette.filet)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: couleur.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(estEntree ? Icons.login_rounded : Icons.logout_rounded,
                size: 18, color: couleur),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(estEntree ? 'Entrée' : 'Sortie', style: TextStyle(
                  color: _palette.texte,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                )),
                if (enAttente || dateInconnue) ...[
                  const SizedBox(height: 2),
                  Text(
                    enAttente ? 'En attente de synchronisation' : 'Heure non vérifiable',
                    style: TextStyle(
                      color: enAttente ? _accentAmbre : EnCheckColors.erreur,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            heureCourte,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: _palette.texte,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrainsMono',
            ),
          ),
        ],
      ),
    );
  }

}
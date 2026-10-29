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
import '../widgets/sans_etirement.dart';
import 'pointages_liste_screen.dart';

class HistoriqueScreen extends StatefulWidget {
  final Map<String, dynamic> employee;

  const HistoriqueScreen({super.key, required this.employee});

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  List<Map<String, dynamic>> pointages = [];
  bool chargement = true;

  /// 🔄 CONTRAT ÉTAPE 2 (25/10/2026) — fiche rafraîchie via le jeton de la
  /// session (le serveur en résout le titulaire) : poste, département et
  /// horaires à jour. `null` tant que le rafraîchissement n'a pas abouti.
  Map<String, dynamic>? _ficheFraiche;

  /// Raison métier d'un refus de session (jeton expiré, ancien jeton…),
  /// affichée honnêtement au lieu de laisser croire que tout va bien.
  String? _sessionRaison;

  /// La fiche AFFICHÉE : rafraîchie si possible, sinon celle transmise par
  /// l'écran précédent — mêmes identifiants, le rafraîchissement par jeton
  /// n'étant accepté que pour le même employé.
  Map<String, dynamic> get _fiche => _ficheFraiche ?? widget.employee;

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
    _chargerHistorique();
    _chargerPause();
    _rafraichirProfil();
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

  /// « ⏸ Je pars en pause » — marche aussi hors-ligne (file d'attente locale).
  Future<void> _partirEnPause() async {
    if (_pauseActionEnCours) return; // verrou anti-double-tap (fiche LOT D)
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
        content: Text(horsLigne
            ? '⏸ Pause enregistrée hors-ligne : elle sera synchronisée.'
            : '⏸ Pause enregistrée. Bonne pause !'),
        backgroundColor: EnCheckColors.terreChaude,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Toujours en pause ? Touche ▶ Je reprends si tu es de retour.'),
        backgroundColor: EnCheckColors.terreChaude,
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
          color: EnCheckColors.terreChaude.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '📍 Hors site',
          style:
              TextStyle(fontSize: 11, color: EnCheckColors.terreChaude),
        ),
      );

  Widget _construireCartePause() {
    // Variables locales non-nulles : pas de promotion hasardeuse.
    final etat = _pauseEtat;
    final debutIso = etat == null ? null : etat['debut'] as String?;
    final motifActif = etat == null ? null : etat['motif'] as String?;

    // « Service en cours depuis … » = le dernier pointage du jour est une
    // arrivée (entrée). Sinon la carte le dit honnêtement.
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
              ? EnCheckColors.terreChaude.withOpacity(0.55)
              : EnCheckColors.succes.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (debutIso != null) ...[
            Row(
              children: [
                const Icon(Icons.pause_circle,
                    color: EnCheckColors.terreChaude, size: 18),
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
                style: const TextStyle(
                  fontSize: 12,
                  color: EnCheckColors.gris,
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
                  color: EnCheckColors.terreChaude.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.alarm, size: 16, color: EnCheckColors.terreChaude),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Toujours en pause ? Touche ▶ Je reprends si tu es de retour.',
                        style: TextStyle(
                            fontSize: 12, color: EnCheckColors.terreChaude),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Text('Motif facultatif :',
                style: TextStyle(fontSize: 12, color: EnCheckColors.gris)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final motif in PauseService.motifs)
                  ChoiceChip(
                    label: Text(motif),
                    selected: motifActif == motif,
                    selectedColor: EnCheckColors.terreChaude.withOpacity(0.2),
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
                label: const Text('▶ Je reprends'),
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
                      : EnCheckColors.gris,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    serviceDepuis != null
                        ? 'Service en cours depuis $serviceDepuis'
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
                label: const Text('⏸ Je pars en pause'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EnCheckColors.terreChaude,
                  foregroundColor: EnCheckColors.blanc,
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
    });

    try {
      List<Map<String, dynamic>> tousLesPointages = [];

      // 1. Charger depuis Supabase si en ligne
      if (ConnectivityService.isOnline) {
        try {
          final supabaseData = await SupabaseService.getHistoriquePointages(_fiche['id']);
          tousLesPointages.addAll(supabaseData);
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
            return Center(
              child: CircularProgressIndicator(
                color: EnCheckColors.brunProfond,
                strokeWidth: 2,
                value:
                loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _construireInitiales(initiales);
          },
        )
            : _construireInitiales(initiales),
      ),
    );
  }

  Widget _construireInitiales(String initiales) {
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

    return Scaffold(
      backgroundColor: EnCheckColors.sableClair,
      appBar: AppBar(
        backgroundColor: EnCheckColors.brunProfond,
        foregroundColor: EnCheckColors.blanc,
        elevation: 0,
        title: const Text(
          'HISTORIQUE',
          style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w300),
        ),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final page = SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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

                if (_fiche['position'] != null || _fiche['department'] != null)
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
                      ],
                    ),
                  ),
              ],
            ),
            ),
          ),

          const SizedBox(height: 16),

          // ═══════════════════════════════════════════
          // ⏸ LES PAUSES (fiche LOT D) — la carte « Ma journée »
          // ═══════════════════════════════════════════
          if (_pausePret) ...[
            _construireCartePause(),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 20),

          // Le résumé du jour, ce que l'employé vient chercher en premier.
          // Masqué pendant le chargement et quand la liste est vide : l'écran
          // « Aucun pointage » le dit déjà.
          if (!chargement && pointages.isNotEmpty) ...[
            _construireResumeJour(),
            const SizedBox(height: 16),
          ],

          // 💬 Contrat étape 2 : un refus de session (expirée, ancien jeton…)
          // s'affiche honnêtement, au lieu de laisser croire que la fiche
          // affichée est toujours la vérité.
          if (_sessionRaison != null) ...[
            _construireBandeauSession(),
            const SizedBox(height: 12),
          ],

          chargement
              ? const SizedBox(
                  height: 220,
                  child: Center(
                    child: CircularProgressIndicator(color: EnCheckColors.terreChaude),
                  ),
                )
              : (pointages.isEmpty && erreur != null)
              ? _construireErreur()
              : pointages.isEmpty
              ? _construireVide()
              : estTelephone
              ? _zoneListeTelephone(constraints)
              : _construireListe(),
                ],
              ),
            ),
          );
          // 📱 TÉLÉPHONE : la page ne s'étire jamais pendant les gestes.
          return estTelephone ? SansEtirement(child: page) : page;
        },
        ),
      );
    }

  /// 💬 Bandeau de session — contrat étape 2 (25/10/2026).
  Widget _construireBandeauSession() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EnCheckColors.terreChaude.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnCheckColors.terreChaude.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, color: EnCheckColors.terreChaude, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _messageSession(_sessionRaison!),
              style: const TextStyle(
                color: EnCheckColors.brunProfond,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Le résumé de la journée en cours, en haut de l'écran.
  ///
  /// Pourquoi l'ajouter alors que la liste en dessous regroupe déjà les
  /// pointages par jour ? Parce que l'employé qui consulte « Ma journée »
  /// veut une réponse immédiate (« suis-je pointé ? à quelle heure ? »),
  /// pas une liste à faire défiler.
  Widget _construireResumeJour() {
    final duJour = _pointagesDuJour;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnCheckColors.terreChaude.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_outlined,
                  color: EnCheckColors.terreChaude, size: 18),
              const SizedBox(width: 8),
              const Text(
                "AUJOURD'HUI",
                style: TextStyle(
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: EnCheckColors.terreChaude,
                ),
              ),
              const Spacer(),
              Text(
                '${duJour.length} pointage${duJour.length > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 12, color: EnCheckColors.gris),
              ),
            ],
          ),

          if (duJour.isEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              "Aucun pointage enregistré aujourd'hui.",
              style: TextStyle(color: EnCheckColors.gris, fontSize: 13),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: duJour.map((pointage) {
                final estEntree = pointage['check_type'] == 'in';
                final couleur =
                    estEntree ? EnCheckColors.succes : EnCheckColors.terreChaude;
                // « HH:MM:SS » → « HH:MM » : la seconde n'intéresse pas
                // l'employé qui consulte sa journée.
                final heure = HeurePointage.heureDePointage(pointage);
                final heureCourte =
                    heure.length >= 5 ? heure.substring(0, 5) : heure;

                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: couleur.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        estEntree ? Icons.login : Icons.logout,
                        size: 14,
                        color: couleur,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        heureCourte,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        estEntree ? 'Entrée' : 'Sortie',
                        style: const TextStyle(
                            fontSize: 11, color: EnCheckColors.gris),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construireVide() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: EnCheckColors.gris.withOpacity(0.5)),
          const SizedBox(height: 20),
          const Text('Aucun pointage', style: TextStyle(color: EnCheckColors.gris, fontSize: 18)),
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
            Icon(Icons.cloud_off, size: 70, color: EnCheckColors.gris.withOpacity(0.5)),
            const SizedBox(height: 20),
            const Text(
              'Historique indisponible',
              style: TextStyle(color: EnCheckColors.gris, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              erreur!,
              style: TextStyle(color: EnCheckColors.gris.withOpacity(0.8), fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _chargerHistorique,
              icon: const Icon(Icons.refresh, color: EnCheckColors.terreChaude),
              label: const Text('Réessayer', style: TextStyle(color: EnCheckColors.terreChaude)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construireListe() {
    final entrees = _groupesParJour();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entrees.length,
      itemBuilder: (context, index) {
        final entree = entrees[index];

        return _construireJour(entree.key, entree.value);
      },
    );
  }

  /// ⭐ LIVRAISON 19 — la journée se découpe sur minuit LOCAL. Avant, elle se
  ///    découpait sur minuit UTC : un pointage de 00:30 à Cotonou était rangé
  ///    dans la veille, et le total d'heures de la journée avec lui.
  List<MapEntry<String, List<Map<String, dynamic>>>> _groupesParJour() {
    final parJour = <String, List<Map<String, dynamic>>>{};

    for (var pointage in pointages) {
      final jour = HeurePointage.jourDePointage(pointage);
      parJour.putIfAbsent(jour, () => []).add(pointage);
    }

    return parJour.entries.toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 📱 TÉLÉPHONE — fiche « Affichage mobile » (§3.4-3.5)
  // ═══════════════════════════════════════════════════════════
  //
  //  L'historique garde son style ; sur téléphone, la liste complète est
  //  derrière un bouton clairement nommé et se consulte par pages
  //  « Précédent » / « Suivant » (aucun pointage supprimé, ordre et
  //  cartes-jours conservés) — sans défilement.
  // ═══════════════════════════════════════════════════════════

  Widget _zoneListeTelephone(BoxConstraints constraints) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (constraints.maxHeight < 600)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _bandeDefilementHist(),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _ouvrirTousPointages,
              icon: const Icon(Icons.list_alt, size: 18),
              label: Text(
                'Voir tous les pointages (${pointages.length})',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: EnCheckColors.terreChaude,
                side: BorderSide(
                    color: EnCheckColors.terreChaude.withOpacity(0.55),
                    width: 1.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _ouvrirTousPointages() {
    final groupes = _groupesParJour();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PointagesListeScreen(
          cartes: [
            for (final g in groupes) _construireJour(g.key, g.value),
          ],
        ),
      ),
    );
  }

  Widget _bandeDefilementHist() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: EnCheckColors.terreChaude.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.unfold_more, size: 14, color: EnCheckColors.terreChaude),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Contenu plus grand que l'écran : faites défiler.",
              style:
                  TextStyle(fontSize: 11.5, color: EnCheckColors.brunProfond),
            ),
          ),
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
  Widget _construireJour(String jour, List<Map<String, dynamic>> pointagesJour) {
    final date = DateTime.tryParse(jour);
    final maintenant = DateTime.now();
    final hier = DateTime(maintenant.year, maintenant.month, maintenant.day - 1);

    String titreJour;
    if (date == null) {
      // ⭐ LIVRAISON 19 — horodatage illisible : on le DIT, au lieu de le ranger
      //    au hasard dans la journée d'aujourd'hui.
      titreJour = 'Journée inconnue';
    } else if (date.year == maintenant.year &&
        date.month == maintenant.month &&
        date.day == maintenant.day) {
      titreJour = "Aujourd'hui";
    } else if (date.year == hier.year && date.month == hier.month && date.day == hier.day) {
      titreJour = "Hier";
    } else {
      final jours = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
      final mois = [
        'Jan',
        'Fév',
        'Mar',
        'Avr',
        'Mai',
        'Juin',
        'Juil',
        'Août',
        'Sep',
        'Oct',
        'Nov',
        'Déc',
      ];
      titreJour = '${jours[date.weekday % 7]} ${date.day} ${mois[date.month - 1]}';
    }

    final calcul = _calculerHeures(List.from(pointagesJour));
    final sessions = calcul['sessions'] as List<Map<String, dynamic>>;
    final totalDuree = calcul['totalDuree'] as Duration;
    final sortiManquante = calcul['sortiManquante'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: EnCheckColors.blanc,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: EnCheckColors.brunProfond.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: EnCheckColors.sableDore.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  titreJour,
                  style: const TextStyle(
                    color: EnCheckColors.brunProfond,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    if (sortiManquante) ...[
                      const Icon(Icons.warning_amber, color: EnCheckColors.erreur, size: 18),
                      const SizedBox(width: 5),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                        sortiManquante
                            ? EnCheckColors.erreur.withOpacity(0.1)
                            : EnCheckColors.succes.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: sortiManquante ? EnCheckColors.erreur : EnCheckColors.succes,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _formaterDuree(totalDuree),
                            style: TextStyle(
                              color: sortiManquante ? EnCheckColors.erreur : EnCheckColors.succes,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ...sessions.map((session) => _construireSession(session)),
        ],
      ),
    );
  }

  Widget _construireSession(Map<String, dynamic> session) {
    final entree = session['entree'];
    final sortie = session['sortie'];
    final duree = session['duree'] as Duration?;

    // ⭐ LIVRAISON 19 — heure locale de la tablette, quelle que soit l'origine
    //    de la ligne (serveur en UTC ou file d'attente à l'heure murale).
    final heureEntree = entree != null ? HeurePointage.heureDePointage(entree) : '--:--:--';
    final heureSortie = sortie != null ? HeurePointage.heureDePointage(sortie) : '--:--:--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: EnCheckColors.sableClair, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                    entree != null
                        ? EnCheckColors.succes.withOpacity(0.1)
                        : EnCheckColors.gris.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.login,
                    size: 16,
                    color: entree != null ? EnCheckColors.succes : EnCheckColors.gris,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  heureEntree,
                  style: TextStyle(
                    color: entree != null ? EnCheckColors.brunProfond : EnCheckColors.gris,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              const Icon(Icons.arrow_forward, color: EnCheckColors.sableDore, size: 20),
              if (duree != null)
                Text(
                  _formaterDuree(duree),
                  style: const TextStyle(
                    color: EnCheckColors.terreChaude,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const Text(
                  '?',
                  style: TextStyle(
                    color: EnCheckColors.erreur,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  heureSortie,
                  style: TextStyle(
                    color: sortie != null ? EnCheckColors.brunProfond : EnCheckColors.erreur,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                    sortie != null
                        ? EnCheckColors.terreChaude.withOpacity(0.1)
                        : EnCheckColors.erreur.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    sortie != null ? Icons.logout : Icons.help_outline,
                    size: 16,
                    color: sortie != null ? EnCheckColors.terreChaude : EnCheckColors.erreur,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
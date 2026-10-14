import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/local_database.dart';
import '../services/connectivity_service.dart';
import '../services/heure_pointage.dart'; // ⭐ LIVRAISON 19 — conversion d'heure

class HistoriqueScreen extends StatefulWidget {
  final Map<String, dynamic> employee;

  const HistoriqueScreen({super.key, required this.employee});

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  List<Map<String, dynamic>> pointages = [];
  bool chargement = true;

  /// Message à afficher quand la lecture a échoué. Sans lui, un refus
  /// d'autorisation sur la table `attendances` produisait une liste vide et
  /// l'écran affichait « Aucun pointage » : l'employé croyait sa journée
  /// perdue alors que le serveur refusait simplement la lecture.
  String? erreur;

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
          final supabaseData = await SupabaseService.getHistoriquePointages(widget.employee['id']);
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
        final pendingData = await LocalDatabase.getPointagesPendingParEmploye(widget.employee['id']);

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
  Widget _construireAvatar() {
    final photoUrl = widget.employee['photo_url'];
    final prenom = widget.employee['first_name'] ?? '';
    final nom = widget.employee['last_name'] ?? '';
    final initiales = '${prenom.isNotEmpty ? prenom[0] : ''}${nom.isNotEmpty ? nom[0] : ''}';

    return Container(
      width: 80,
      height: 80,
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
          width: 80,
          height: 80,
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
          style: const TextStyle(
            color: EnCheckColors.brunProfond,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: Column(
        children: [
          // ═══════════════════════════════════════════
          // 👤 EN-TÊTE EMPLOYÉ AVEC PHOTO
          // ═══════════════════════════════════════════
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: EnCheckColors.brunProfond,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              children: [
                _construireAvatar(),
                const SizedBox(height: 12),

                Text(
                  '${widget.employee['first_name']} ${widget.employee['last_name']}',
                  style: const TextStyle(
                    color: EnCheckColors.blanc,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  widget.employee['matricule'] ?? '',
                  style: const TextStyle(
                    color: EnCheckColors.sableDore,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 12),

                if (widget.employee['position'] != null || widget.employee['department'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: EnCheckColors.blanc.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (widget.employee['position'] != null &&
                            widget.employee['position'].toString().isNotEmpty)
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
                                widget.employee['position'],
                                style: const TextStyle(
                                  color: EnCheckColors.blanc,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                        if (widget.employee['position'] != null &&
                            widget.employee['position'].toString().isNotEmpty &&
                            widget.employee['department'] != null &&
                            widget.employee['department'].toString().isNotEmpty)
                          const SizedBox(height: 6),

                        if (widget.employee['department'] != null &&
                            widget.employee['department'].toString().isNotEmpty)
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
                                widget.employee['department'],
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

          const SizedBox(height: 20),

          // Le résumé du jour, ce que l'employé vient chercher en premier.
          // Masqué pendant le chargement et quand la liste est vide : l'écran
          // « Aucun pointage » le dit déjà.
          if (!chargement && pointages.isNotEmpty) ...[
            _construireResumeJour(),
            const SizedBox(height: 16),
          ],

          Expanded(
            child:
            chargement
                ? const Center(
              child: CircularProgressIndicator(color: EnCheckColors.terreChaude),
            )
                : (pointages.isEmpty && erreur != null)
                ? _construireErreur()
                : pointages.isEmpty
                ? _construireVide()
                : _construireListe(),
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
    Map<String, List<Map<String, dynamic>>> parJour = {};

    for (var pointage in pointages) {
      // ⭐ LIVRAISON 19 — la journée se découpe sur minuit LOCAL. Avant, elle se
      //    découpait sur minuit UTC : un pointage de 00:30 à Cotonou était rangé
      //    dans la veille, et le total d'heures de la journée avec lui.
      final jour = HeurePointage.jourDePointage(pointage);

      if (!parJour.containsKey(jour)) {
        parJour[jour] = [];
      }
      parJour[jour]!.add(pointage);
    }

    final jours = parJour.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: jours.length,
      itemBuilder: (context, index) {
        final jour = jours[index];
        final pointagesJour = parJour[jour]!;

        return _construireJour(jour, pointagesJour);
      },
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
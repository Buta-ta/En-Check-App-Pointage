import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/local_database.dart';
import '../services/connectivity_service.dart';

class HistoriqueScreen extends StatefulWidget {
  final Map<String, dynamic> employee;

  const HistoriqueScreen({super.key, required this.employee});

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  List<Map<String, dynamic>> pointages = [];
  bool chargement = true;

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
      }

      // 2. Charger les pointages pending locaux
      try {
        final pendingData = await LocalDatabase.getPointagesPendingParEmploye(widget.employee['id']);

        // ✅ FUSION : Ajouter les pending, mais éviter les doublons si déjà synchronisés
        for (var localPointage in pendingData) {
          // Vérifier si ce pointage existe déjà dans les données Supabase (par date approximative)
          final existeDeja = tousLesPointages.any((p) {
            final dateLocal = DateTime.parse(localPointage['check_time']);
            final dateSupabase = DateTime.parse(p['check_time']);
            // Si même type et différence < 2 secondes -> considéré comme doublon
            return p['check_type'] == localPointage['check_type'] &&
                dateLocal.difference(dateSupabase).inSeconds.abs() < 2;
          });

          if (!existeDeja) {
            tousLesPointages.add(localPointage);
          }
        }
      } catch (e) {
        print('Erreur chargement pointages locaux: $e');
      }

      // 3. Trier par date (plus récent en premier)
      tousLesPointages.sort((a, b) {
        final dateA = DateTime.parse(a['check_time']);
        final dateB = DateTime.parse(b['check_time']);
        return dateB.compareTo(dateA);
      });

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

          Expanded(
            child:
            chargement
                ? const Center(
              child: CircularProgressIndicator(color: EnCheckColors.terreChaude),
            )
                : pointages.isEmpty
                ? _construireVide()
                : _construireListe(),
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
          Icon(Icons.history, size: 80, color: EnCheckColors.gris.withOpacity(0.5)),
          const SizedBox(height: 20),
          const Text('Aucun pointage', style: TextStyle(color: EnCheckColors.gris, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _construireListe() {
    Map<String, List<Map<String, dynamic>>> parJour = {};

    for (var pointage in pointages) {
      final dateTime = DateTime.parse(pointage['check_time']);
      final jour =
          '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';

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
    pointagesJour.sort((a, b) {
      final dateA = DateTime.parse(a['check_time']);
      final dateB = DateTime.parse(b['check_time']);
      return dateA.compareTo(dateB);
    });

    Duration totalDuree = Duration.zero;
    List<Map<String, dynamic>> sessions = [];
    Map<String, dynamic>? entreeEnCours;
    bool sortiManquante = false;

    for (var pointage in pointagesJour) {
      final type = pointage['check_type'];
      final heure = DateTime.parse(pointage['check_time']);

      if (type == 'in') {
        if (entreeEnCours != null) {
          sessions.add({'entree': entreeEnCours, 'sortie': null, 'duree': null});
          sortiManquante = true;
        }
        entreeEnCours = pointage;
      } else if (type == 'out') {
        if (entreeEnCours != null) {
          final heureEntree = DateTime.parse(entreeEnCours['check_time']);
          final duree = heure.difference(heureEntree);
          totalDuree += duree;

          sessions.add({
            'entree': entreeEnCours,
            'sortie': pointage,
            'duree': duree
          });
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

    if (totalSecondes == 0) return '0sec';

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

  String _formaterHeure(String dateTimeStr) {
    // ✅ CORRECTION : Parsing sans conversion UTC/Local
    // Si la chaîne n'a pas de "Z", DateTime.parse() la considère comme locale
    final dateTime = DateTime.parse(dateTimeStr);

    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
  Widget _construireJour(String jour, List<Map<String, dynamic>> pointagesJour) {
    final date = DateTime.parse(jour);
    final maintenant = DateTime.now();
    final hier = DateTime(maintenant.year, maintenant.month, maintenant.day - 1);

    String titreJour;
    if (date.year == maintenant.year &&
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

    final heureEntree = entree != null ? _formaterHeure(entree['check_time']) : '--:--:--';
    final heureSortie = sortie != null ? _formaterHeure(sortie['check_time']) : '--:--:--';

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
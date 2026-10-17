// lib/services/pause_service.dart
// ═══════════════════════════════════════════════════════════════════════════
//  ⏸  LES PAUSES — FICHE « LOT D » (16/10/2026)
// ═══════════════════════════════════════════════════════════════════════════
//
//  Le problème : quand un employé fait une pause, personne ne la voit
//  nulle part. Ce service parle aux DEUX fonctions fournies par la base
//  (migration admin 20261016000004_pauses_intelligentes.sql) :
//
//      encheck_pause_ouvrir(p_employee, p_debut, p_motif)
//      encheck_pause_fermer(p_employee, p_fin)
//
//  ⚠️ RÈGLE D'OR (leçon MADEDE) : l'app n'écrit JAMAIS dans `attendances`
//     ni dans `encheck_pauses`. Elle passe UNIQUEMENT par ces 2 RPC.
//
//  MODE HORS-LIGNE (très important)
//  ───────────────────────────────
//  Les taps fonctionnent sans réseau : chaque geste est rangé dans une FILE
//  d'attente locale (Hive) avec son INSTANT, puis renvoyé dès que le réseau
//  revient, dans l'ordre. La base est protégée contre les doublons :
//  même (employé, même instant de début) envoyé 2 fois = UNE seule pause
//  (`deja: true`). C'est pourquoi la file renvoie TOUJOURS le même instant
//  qu'au moment du tap — jamais « maintenant ».
//
//  L'INSTANT DE CONFIANCE
//  ──────────────────────
//  Comme pour les pointages (LIVRAISON 09), l'heure envoyée vient de
//  l'ancre SERVEUR + le chronomètre monotone, jamais l'heure brute du
//  téléphone. La base refuse de toute façon les heures dans le futur.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'heure_pointage.dart';
import 'trusted_punch_service.dart';

class PauseService {
  PauseService._(); // classe utilitaire : pas d'instance

  /// Rappel de reprise : après cette durée, l'app rappelle gentiment à
  /// l'employé de toucher « ▶ Je reprends » (fiche LOT D : 75 minutes).
  /// Un rappel LOCAL et GRATUIT — jamais une alarme, jamais un SMS.
  static const int rappelMinutes = 75;

  /// Les motifs proposés (facultatifs) — libellés tels qu'affichés.
  static const List<String> motifs = ['Repas', 'Personnelle', 'Urgence'];

  static SupabaseClient get _sb => Supabase.instance.client;

  // ── Stockage local (Hive) ────────────────────────────────────────────────
  //   Boîte « état » : 'etat:<employeeId>' → la pause ouverte (ou rien).
  //   Boîte « file »  : clés auto-incrémentées = l'ordre d'arrivée. Cet
  //   ordre EST l'ordre de rejeu (FIFO) : « reprendre » ne doit jamais
  //   partir avant « partir en pause ».
  static const String _boxEtat = 'encheck_pauses_etat';
  static const String _boxFile = 'encheck_pauses_file';

  static Future<Box> _boiteEtat() async => Hive.openBox(_boxEtat);
  static Future<Box> _boiteFile() async => Hive.openBox(_boxFile);

  // ═══════════════════════════════════════════════════════════════════════
  //  L'INSTANT DE CONFIANCE
  // ═══════════════════════════════════════════════════════════════════════

  /// « Maintenant » mesuré avec le même chronomètre que les pointages :
  /// l'ancre serveur + le temps écoulé (chronomètre MONOTONE, qui ne
  /// recule jamais même si quelqu'un change l'heure du téléphone).
  static DateTime instantDeConfiance() {
    final ancre = TrustedPunchService.ancreUtc;
    final ecoule = TrustedPunchService.ecouleSecondes();
    if (ancre != null && ecoule != null) {
      return ancre.add(Duration(seconds: ecoule)).toUtc();
    }
    return DateTime.now().toUtc();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ÉTAT LOCAL — « suis-je en pause ? depuis quand ? »
  // ═══════════════════════════════════════════════════════════════════════

  /// La pause ouverte de l'employé, ou `null` s'il n'est pas en pause.
  /// Forme : { debut: ISO, motif: String?, pause_id: String?, rappel_le: ISO? }
  static Future<Map<String, dynamic>?> etatPause(String employeeId) async {
    try {
      final box = await _boiteEtat();
      final brut = box.get('etat:$employeeId');
      if (brut == null) return null;
      final etat = Map<String, dynamic>.from(brut as Map);
      if (etat['debut'] == null) return null;
      return etat;
    } catch (e) {
      print('⚠️ etatPause : $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LES 2 GESTES — partir en pause / reprendre
  // ═══════════════════════════════════════════════════════════════════════

  /// « ⏸ Je pars en pause » — fonctionne avec ET sans réseau.
  ///
  /// En ligne : le geste part tout de suite. Hors-ligne : il est mis en file
  /// et renvoyé plus tard, AVEC LE MÊME instant (la base ne créera qu'une
  /// seule pause, même envoyée deux fois).
  static Future<Map<String, dynamic>> partirEnPause({
    required String employeeId,
    required String? enterpriseId,
    String? nom,
    String? matricule,
    String? motif,
  }) async {
    final file = await _boiteFile();
    final etats = await _boiteEtat();
    final debut = instantDeConfiance();

    final etat = {
      'employee_id': employeeId,
      'enterprise_id': enterpriseId,
      'nom': nom,
      'matricule': matricule,
      'debut': debut.toIso8601String(),
      'motif': motif,
      'pause_id': null,
      'rappel_le': null,
    };

    // 1. La file d'attente d'abord (c'est elle la vérité à renvoyer)…
    await _enfiler(file, {
      'type': 'ouvrir',
      'employee_id': employeeId,
      'enterprise_id': enterpriseId,
      'instant': debut.toIso8601String(),
      'motif': motif,
    });
    // 2. …puis l'état local pour l'écran.
    await etats.put('etat:$employeeId', etat);

    if (ConnectivityService.isOnline) {
      await synchroniser();
    }
    return (await etatPause(employeeId)) ?? etat;
  }

  /// « ▶ Je reprends » — fonctionne avec ET sans réseau.
  static Future<void> reprendre({
    required String employeeId,
    required String? enterpriseId,
  }) async {
    final file = await _boiteFile();
    final etats = await _boiteEtat();
    final fin = instantDeConfiance();

    await _enfiler(file, {
      'type': 'fermer',
      'employee_id': employeeId,
      'enterprise_id': enterpriseId,
      'instant': fin.toIso8601String(),
      'motif': null,
    });

    // La pause locale est refermée : l'écran retourne à « Service en cours ».
    final brut = etats.get('etat:$employeeId');
    if (brut != null) {
      final etat = Map<String, dynamic>.from(brut as Map);
      etat['debut'] = null;
      etat['fin'] = fin.toIso8601String();
      await etats.put('etat:$employeeId', etat);
    }

    if (ConnectivityService.isOnline) {
      await synchroniser();
    }
  }

  /// Le motif est FACULTATIF et modifiable tant que la pause est ouverte.
  ///
  /// Le changement est enregistré localement tout de suite (l'affichage suit),
  /// puis renvoyé : la base reconnaît le même (employé, même instant de
  /// début) et ne crée AUCUN doublon (`deja: true`).
  static Future<void> changerMotif({
    required String employeeId,
    String? motif,
  }) async {
    final file = await _boiteFile();
    final etats = await _boiteEtat();
    final brut = etats.get('etat:$employeeId');
    if (brut == null) return;
    final etat = Map<String, dynamic>.from(brut as Map);
    final debut = etat['debut'];
    if (debut == null) return; // plus en pause : rien à modifier

    etat['motif'] = motif;
    await etats.put('etat:$employeeId', etat);

    // Met à jour le geste déjà en file (même instant), ou l'ajoute.
    await _enfiler(file, {
      'type': 'ouvrir',
      'employee_id': employeeId,
      'enterprise_id': etat['enterprise_id'],
      'instant': debut,
      'motif': motif,
    });

    if (ConnectivityService.isOnline) {
      await synchroniser();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LA FILE D'ATTENTE — rejeu dans l'ordre, sans doublon
  // ═══════════════════════════════════════════════════════════════════════

  /// Ajoute un geste à la file. Si un geste de même type porte déjà le MÊME
  /// instant pour le même employé (changement de motif), on le met à jour au
  /// lieu de l'empiler — la base ne créerait de toute façon aucun doublon.
  static Future<void> _enfiler(Box file, Map<String, dynamic> geste) async {
    for (final key in file.keys.toList()) {
      final existant = Map<String, dynamic>.from(file.get(key) as Map);
      if (existant['type'] == geste['type'] &&
          existant['instant'] == geste['instant'] &&
          existant['employee_id'] == geste['employee_id']) {
        await file.put(key, geste); // même geste : mise à jour, pas de doublon
        return;
      }
    }
    await file.add(geste); // clé auto-incrémentée = ordre d'arrivée (FIFO)
  }

  /// Vide la file d'attente dès que le réseau le permet, DANS L'ORDRE.
  ///
  /// En cas de coupure en cours de route, on s'arrête NET et on garde
  /// l'ordre : aucun geste ne doit dépasser celui qui a échoué.
  static Future<void> synchroniser() async {
    if (!ConnectivityService.isOnline) return;
    try {
      final file = await _boiteFile();
      final etats = await _boiteEtat();
      final cles = file.keys.toList()
        ..sort((a, b) => (a is int && b is int)
            ? a.compareTo(b)
            : a.toString().compareTo(b.toString()));

      for (final key in cles) {
        final geste = Map<String, dynamic>.from(file.get(key) as Map);
        final type = geste['type'] as String?;

        if (type == 'ouvrir') {
          final res = await _rpcOuvrir(
            employeeId: geste['employee_id'] as String,
            debut: geste['instant'] as String,
            motif: geste['motif'] as String?,
          );

          if (res['ok'] == true) {
            await file.delete(key);
            // Si c'est la pause affichée à l'écran, on garde son identifiant.
            final etatBrut = etats.get('etat:${geste['employee_id']}');
            if (etatBrut != null) {
              final etat = Map<String, dynamic>.from(etatBrut as Map);
              if (etat['debut'] == geste['instant']) {
                etat['pause_id'] = res['pause_id'];
                await etats.put('etat:${geste['employee_id']}', etat);
              }
            }
          } else if (res['reseau'] == true) {
            return; // coupure : on garde la file, dans l'ordre
          } else {
            // Refus définitif de la base (employé inactif, heure invalide…) :
            // inutile de réessayer indéfiniment.
            print('⛔ Pause « ouvrir » refusée définitivement : ${res['erreur']}');
            await file.delete(key);
          }
        } else if (type == 'fermer') {
          final res = await _rpcFermer(
            employeeId: geste['employee_id'] as String,
            fin: geste['instant'] as String,
          );

          // « aucune pause ouverte » = le geste a déjà été fait (rejeu) :
          // rien d'alarmant, on vide simplement la file (fiche LOT D).
          final doux = res['ok'] == true ||
              res['erreur'] == 'aucune pause ouverte' ||
              res['fermee'] == false;
          if (doux) {
            await file.delete(key);
          } else if (res['reseau'] == true) {
            return;
          } else {
            print('⛔ Pause « fermer » refusée définitivement : ${res['erreur']}');
            await file.delete(key);
          }
        } else {
          await file.delete(key); // geste inconnu : on l'oublie
        }
      }
    } catch (e) {
      print('⚠️ synchronisation des pauses : $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LES 2 RPC — les seuls chemins d'écriture (jamais dans les tables)
  // ═══════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> _rpcOuvrir({
    required String employeeId,
    required String debut,
    String? motif,
  }) async {
    try {
      final res = await _sb.rpc('encheck_pause_ouvrir', params: {
        'p_employee': employeeId,
        'p_debut': debut,
        'p_motif': motif,
      });
      return res is Map
          ? Map<String, dynamic>.from(res)
          : {'ok': false, 'erreur': 'reponse_inattendue'};
    } catch (e) {
      print('❌ encheck_pause_ouvrir (réseau/serveur) : $e');
      return {'ok': false, 'reseau': true, 'erreur': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _rpcFermer({
    required String employeeId,
    required String fin,
  }) async {
    try {
      final res = await _sb.rpc('encheck_pause_fermer', params: {
        'p_employee': employeeId,
        'p_fin': fin,
      });
      return res is Map
          ? Map<String, dynamic>.from(res)
          : {'ok': false, 'erreur': 'reponse_inattendue'};
    } catch (e) {
      print('❌ encheck_pause_fermer (réseau/serveur) : $e');
      return {'ok': false, 'reseau': true, 'erreur': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  « PAUSE PRÉVUE 12:00–13:00 » — la base calcule, l'app affiche
  // ═══════════════════════════════════════════════════════════════════════

  /// Le créneau de pause prévu ce jour-là, calculé PAR LA BASE
  /// (`encheck_pause_prevue` : affectation individuelle → grille liée →
  /// défaut de l'entreprise). L'app ne lit JAMAIS les plannings elle-même.
  ///
  /// Renvoie `{trouvee: true, debut: '12:00', fin: '13:00', minutes: 60}`
  /// ou `{trouvee: false}` — jamais d'exception.
  static Future<Map<String, dynamic>> pausePrevue({
    required String employeeId,
    required String? enterpriseId,
  }) async {
    if (!ConnectivityService.isOnline) return {'trouvee': false};
    if (enterpriseId == null || enterpriseId.isEmpty) {
      return {'trouvee': false};
    }
    try {
      final jour = HeurePointage.jourDePointage(
          {'check_time': instantDeConfiance().toIso8601String()});
      final res = await _sb.rpc('encheck_pause_prevue', params: {
        'p_employee': employeeId,
        'p_enterprise': enterpriseId,
        'p_jour': jour,
      });
      return res is Map ? Map<String, dynamic>.from(res) : {'trouvee': false};
    } catch (e) {
      print('⚠️ encheck_pause_prevue : $e');
      return {'trouvee': false};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LA LISTE DES PAUSES EN COURS — pour le bandeau de l'écran principal
  // ═══════════════════════════════════════════════════════════════════════

  /// Toutes les pauses ouvertes de l'entreprise, pour LE BANDEAU VISIBLE de
  /// l'écran de pointage (fiche de visibilité, 17/10/2026).
  ///
  /// Deux sources mêlées :
  ///  • la BASE (RPC `encheck_pauses_en_cours`) quand on est en ligne — la
  ///    vérité, avec les noms ;
  ///  • l'ÉTAT LOCAL (Hive) toujours — pour voir la pause qui vient d'être
  ///    ouverte, même hors-ligne ou avant le rejeu.
  ///
  /// Règle de fusion (par employé) :
  ///  • fermée ICI (reprise déjà tapée) → ne plus l'afficher, même si la base
  ///    ne l'a pas encore reçue ;
  ///  • ouverte ICI → afficher ;
  ///  • rien ici → suivre la base.
  static Future<List<Map<String, dynamic>>> pausesOuvertes({
    required String enterpriseId,
  }) async {
    // 1. État local : les pauses connues de CETTE tablette (ouvertes OU
    //    fermées localement — la mention « fin » sert de arbitre).
    final localParEmploye = <String, Map<String, dynamic>>{};
    try {
      final box = await _boiteEtat();
      for (final key in box.keys.toList()) {
        if (!key.toString().startsWith('etat:')) continue;
        final etat = Map<String, dynamic>.from(box.get(key) as Map);
        final empId = etat['employee_id']?.toString();
        if (empId == null) continue;
        localParEmploye[empId] = etat;
      }
    } catch (e) {
      print('⚠️ pausesOuvertes (local) : $e');
    }

    // 2. La base, quand c'est possible.
    final lignes = <Map<String, dynamic>>[];
    final vues = <String>{};
    if (ConnectivityService.isOnline) {
      try {
        final res = await _sb.rpc('encheck_pauses_en_cours',
            params: {'p_enterprise': enterpriseId});
        if (res is List) {
          for (final row in res) {
            final r = Map<String, dynamic>.from(row as Map);
            final empId = r['employe_id']?.toString();
            if (empId == null) continue;
            final local = localParEmploye[empId];
            // Reprise déjà tapée sur cette tablette (pas encore rejouée) :
            // on la considère fermée tout de suite.
            if (local != null &&
                local['debut'] == null &&
                local['fin'] != null) {
              continue;
            }
            final prenom = r['prenom']?.toString() ?? '';
            final nom = r['nom']?.toString() ?? '';
            lignes.add({
              'employee_id': empId,
              'nom': ('$prenom $nom').trim(),
              'matricule': r['matricule']?.toString(),
              'debut': r['debut']?.toString(),
              'motif': r['motif']?.toString(),
              'duree_minutes': r['duree_minutes'],
              'source': 'base',
            });
            vues.add(empId);
          }
        }
      } catch (e) {
        // Fonction pas encore créée ou moment sans réseau : le bandeau
        // restera sur l'état local — jamais d'erreur à l'écran.
        print('⚠️ pausesOuvertes (base) : $e');
      }
    }

    // 3. Compléter avec les pauses ouvertes ICI que la base ne liste pas.
    for (final entry in localParEmploye.entries) {
      final etat = entry.value;
      if (etat['debut'] == null) continue; // fermée ici
      if (vues.contains(entry.key)) continue;
      final debutIso = etat['debut'] as String?;
      lignes.add({
        'employee_id': entry.key,
        'nom': etat['nom']?.toString() ?? 'Employé',
        'matricule': etat['matricule']?.toString(),
        'debut': debutIso,
        'motif': etat['motif']?.toString(),
        'duree_minutes': null,
        'source': 'local',
      });
    }

    // 4. Du plus ancien au plus récent (les oublis de reprise d'abord).
    lignes.sort((a, b) {
      final da = HeurePointage.instantDe(a['debut']) ?? DateTime.now().toUtc();
      final db = HeurePointage.instantDe(b['debut']) ?? DateTime.now().toUtc();
      return da.compareTo(db);
    });
    return lignes;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LE RAPPEL DE REPRISE (75 min) — local, gratuit, pas une alarme
  // ═══════════════════════════════════════════════════════════════════════

  /// La pause dure-t-elle déjà depuis plus de [rappelMinutes] ?
  static bool rappelDepasse(DateTime debutUtc) =>
      DateTime.now().toUtc().difference(debutUtc) >=
      const Duration(minutes: rappelMinutes);

  /// « 12:05 » (heure de l'entreprise) pour l'affichage.
  static String heureCourteDe(String isoUtc) {
    final d = HeurePointage.instantDe(isoUtc);
    final h = HeurePointage.heureDe(d);
    return h.length >= 5 ? h.substring(0, 5) : h;
  }
}

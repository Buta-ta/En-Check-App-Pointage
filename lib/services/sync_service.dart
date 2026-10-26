import 'local_database.dart';
import 'supabase_service.dart'; // ✅ Import correct
import 'borne_service.dart'; // 🖥️ CONTRAT ÉTAPE 3 — snapshot de borne
import 'connectivity_service.dart';
import 'trusted_punch_service.dart';
import 'pause_service.dart'; // ⏸ LOT D — la file d'attente des pauses

class SyncService {
  // ═══════════════════════════════════════════════════════════
  // 🔄 SYNCHRONISER LES POINTAGES EN ATTENTE
  // ═══════════════════════════════════════════════════════════
  static Future<int> synchroniserPointages() async {
    if (!ConnectivityService.isOnline) return 0;

    try {
      final pointagesPending = await LocalDatabase.getPointagesPending();
      int synchronises = 0;

      for (var pointage in pointagesPending) {
        try {
          // ⭐ LIVRAISON 09 — on envoie le DÉLAI mesuré par le chronomètre
          //    monotone, jamais l'heure brute du téléphone. Le serveur datera
          //    le pointage lui-même, et refusera toute antidatation.
          final resultat = await TrustedPunchService.pointer(
            employeeId:    pointage['employee_id'],
            enterpriseId:  pointage['enterprise_id'],
            checkType:     pointage['check_type'],
            method:        pointage['method'] ?? 'pin',
            clientRef:     pointage['client_ref'],
            delaiSecondes: pointage['delai_secondes'] as int?,
            // ⭐ la base de temps mémorisée avec le pointage. Sans elle, seul
            //    le PREMIER pointage d'une file hors-ligne serait daté
            //    correctement ; les suivants tomberaient à l'heure de la
            //    synchronisation, au lieu de leur heure réelle.
            ancreUtc:      DateTime.tryParse(
                             (pointage['ancre_utc'] as String?) ?? ''),
            // si le délai n'a pas pu être mesuré au moment du pointage, on le
            // dit au serveur (il datera à MAINTENANT et le signalera) au lieu
            // de lui faire croire à une mesure qui n'existe pas.
            heureInconnue: pointage['delai_secondes'] == null,
            // ⭐ LIVRAISON 12 — le jeton du pointage, pas celui du moment.
            //    Absent pour un pointage mis en file avant la 12 : le
            //    service prend alors le jeton courant.
            jetonImpose:   pointage['jeton'] as String?,
          );

          if (resultat['ok'] == true) {
            await LocalDatabase.supprimerPointagePending(pointage['id'] as int);
            synchronises++;
          } else if (resultat['reason'] == 'reseau' ||
                     resultat['reason'] == 'serveur_non_equipe' ||
                     // ⭐ LIVRAISON 12 — un refus lié au JETON n'est JAMAIS
                     //    définitif : c'est le signe que la session a expiré
                     //    ou que l'employé doit se reconnecter. On GARDE le
                     //    pointage. Le supprimer ici, ce serait effacer le
                     //    travail de quelqu'un parce que sa session a expiré.
                     resultat['reason'] == 'jeton_invalide' ||
                     resultat['reason'] == 'jeton_requis' ||
                     resultat['reason'] == 'jeton_d_un_autre_appareil' ||
                     resultat['reason'] == 'identite_incoherente' ||
                     resultat['reason'] == 'entreprise_incoherente') {
            // panne passagère ou session à renouveler : on garde le pointage
            print('⏳ Pointage conservé pour rejeu (${resultat['reason']})');
          } else {
            // refus DÉFINITIF du serveur (employé inconnu, données invalides…)
            // → inutile de réessayer indéfiniment
            print('⛔ Pointage refusé définitivement : ${resultat['reason']}');
            await LocalDatabase.supprimerPointagePending(pointage['id'] as int);
          }
        } catch (e) {
          print('⚠️ Erreur sync pointage ${pointage['id']}: $e');

          final errorMsg = e.toString().toLowerCase();
          if (errorMsg.contains('23505') || errorMsg.contains('duplicate') || errorMsg.contains('already exists')) {
            await LocalDatabase.supprimerPointagePending(pointage['id'] as int);
          }
        }
      }
      // ⏸ LOT D — après les pointages, la file des pauses : même logique
      // (rejeu FIFO, sans doublon). La base est protégée par (employé, instant
      // de début) unique — renvoyer la même pause ne crée rien.
      await PauseService.synchroniser();
      return synchronises;
    } catch (e) {
      print('❌ Erreur globale sync: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📥 TÉLÉCHARGER LES DONNÉES
  // ═══════════════════════════════════════════════════════════
  static Future<void> telechargerDonneesPourHorsLigne() async {
    if (!ConnectivityService.isOnline) return;

    try {
      print('📥 Préparation du mode hors-ligne...');

      final entreprises = await SupabaseService.getEntreprises();
      await LocalDatabase.cacherEntreprises(entreprises);

      // 🖥️ CONTRAT ÉTAPE 3 (26/10/2026) : le téléchargement collectif du
      // personnel passe par le SNAPSHOT de borne (encheck_borne_personnel,
      // jeton borne `bk1_`) — remplacement intégral du cache, expiration
      // cache_expire_le gérée par BorneService. Sans appareil autorisé, le
      // cache des employés ne contient QUE les profils de ceux qui se sont
      // identifiés sur cette tablette. Aucun repli sur les anciens accès.
      if (await BorneService.aUnBailValide() || await BorneService.aUnSecret()) {
        final snapshot = await BorneService.synchroniserPersonnel();
        if (snapshot['ok'] == true) {
          final employes = (snapshot['employes'] as List?)?.length ?? 0;
          print('✅ Personnel de la borne synchronisé ($employes employé(s))');
        } else {
          print('⚠️ Personnel de la borne indisponible — ${snapshot['erreur']}');
          print('   Le cache précédent a été purgé (pas de repli).');
        }
      }

      // Les appels de SupabaseService avalent leurs exceptions et renvoient du
      // vide : sans ce contrôle, un 401 « permission denied for table » passait
      // pour un téléchargement réussi.
      final erreur = SupabaseService.derniereErreur;
      if (erreur != null) {
        print('⚠️ Catalogue des entreprises incomplet — $erreur');
        print('   Les caches locaux gardent leur contenu précédent.');
      } else {
        print('✅ Mode hors-ligne prêt (catalogue des entreprises à jour)');
      }
    } catch (e) {
      print('❌ Erreur téléchargement données: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🔄 SYNCHRONISATION AUTOMATIQUE
  // ═══════════════════════════════════════════════════════════
  static Future<void> synchroniserAutomatique() async {
    if (!ConnectivityService.isOnline) return;

    try {
      print('🔄 Synchronisation automatique...');
      await synchroniserPointages();
      await telechargerDonneesPourHorsLigne();
      print('✅ Synchronisation terminée');
    } catch (e) {
      print('❌ Erreur synchronisation automatique: $e');
    }
  }
}
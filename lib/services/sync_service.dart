import 'local_database.dart';
import 'supabase_service.dart'; // ✅ Import correct
import 'connectivity_service.dart';

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
          final success = await SupabaseService.enregistrerPointage(
            employeeId: pointage['employee_id'],
            enterpriseId: pointage['enterprise_id'],
            checkType: pointage['check_type'],
            method: pointage['method'] ?? 'pin',
            checkTimeOverride: pointage['check_time'], // ✅ IMPORTANT : On envoie l'heure stockée en local
          );

          if (success) {
            await LocalDatabase.supprimerPointagePending(pointage['id'] as int);
            synchronises++;
          }
        } catch (e) {
          print('⚠️ Erreur sync pointage ${pointage['id']}: $e');

          final errorMsg = e.toString().toLowerCase();
          if (errorMsg.contains('23505') || errorMsg.contains('duplicate') || errorMsg.contains('already exists')) {
            await LocalDatabase.supprimerPointagePending(pointage['id'] as int);
          }
        }
      }
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
      print('📥 Téléchargement des données hors-ligne...');

      final entreprises = await SupabaseService.getEntreprises();
      await LocalDatabase.cacherEntreprises(entreprises);

      for (var entreprise in entreprises) {
        final employeesDynamic = await SupabaseService.getEmployeesParEntreprise(entreprise['id']);
        final employees = employeesDynamic.cast<Map<String, dynamic>>();

        await LocalDatabase.cacherEmployees(employees);

        final schedules = <Map<String, dynamic>>[];

        for (var employee in employees) {
          try {
            dynamic rawSchedule = employee['employee_schedules'];
            Map<String, dynamic>? scheduleMap;

            if (rawSchedule == null) {
              continue;
            } else if (rawSchedule is List) {
              if (rawSchedule.isNotEmpty) {
                scheduleMap = rawSchedule.first as Map<String, dynamic>;
              }
            } else if (rawSchedule is Map) {
              scheduleMap = rawSchedule as Map<String, dynamic>;
            }

            if (scheduleMap != null) {
              final cleanSchedule = Map<String, dynamic>.from(scheduleMap);
              schedules.add(cleanSchedule);
            }
          } catch (e) {
            print('⚠️ Ignoré horaire malformé pour employé ${employee['id']}: $e');
          }
        }

        if (schedules.isNotEmpty) {
          await LocalDatabase.cacherHoraires(schedules);
        }
      }

      print('✅ Données hors-ligne téléchargées avec succès');
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
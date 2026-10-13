-- ══════════════════════════════════════════════════════════════════════════
--  ⚠️  À EXÉCUTER DANS : Dashboard Supabase → SQL Editor → Run
--      Ce fichier ne se déploie pas sur Vercel.
--
--  Projet : cxggndvhwdolbtyezjde
--  But : rendre à l'employé son historique de pointage dans l'app.
-- ══════════════════════════════════════════════════════════════════════════
--
-- LE SYMPTÔME
-- ───────────
-- Le pointage fonctionne, mais l'écran « Historique » reste vide, y compris
-- pour la journée en cours.
--
-- POURQUOI
-- ────────
-- Pointer et LIRE l'historique ne passent pas par le même chemin :
--
--   • le pointage   → rpc('encheck_punch')            → fonction SECURITY
--                                                        DEFINER, elle agit
--                                                        avec ses propres
--                                                        droits  → ÇA MARCHE
--   • l'historique  → .from('attendances').select()   → lecture DIRECTE de la
--                                                        table, avec le rôle
--                                                        `anon`      → ÇA COINCE
--
-- (lib/services/supabase_service.dart : enregistrerPointageAvecId utilise le
--  RPC, getHistoriquePointages et dernierPointage lisent la table en direct.)
--
-- Si seul le GRANT sur `enterprises` a été appliqué, la table `attendances`
-- n'a toujours pas de droit de lecture pour `anon`. Postgres refuse, le Dart
-- attrape l'exception et renvoie une liste vide :
--
--     } catch (e) { print('Erreur historique: $e'); return []; }
--
-- L'écran affiche donc « Aucun pointage » — exactement comme une journée sans
-- pointage. Rien dans l'interface ne distinguait les deux. (C'est corrigé dans
-- le code : l'écran affiche maintenant « Historique indisponible » avec la
-- raison, une fois main.dart.js recompilé.)
-- ══════════════════════════════════════════════════════════════════════════


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 1 — ÉTAT ACTUEL
-- Si aucune ligne `anon | SELECT` n'apparaît pour `attendances`, c'est la
-- cause confirmée.
-- ──────────────────────────────────────────────────────────────────────────
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name   = 'attendances'
  AND grantee IN ('anon', 'authenticated')
ORDER BY grantee, privilege_type;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 2 — LE CORRECTIF
-- ──────────────────────────────────────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.attendances TO anon, authenticated;

-- Politique de lecture : ajoutée UNIQUEMENT si la RLS est déjà active sur la
-- table ET qu'aucune politique n'existe. Sans cette condition, on risquerait
-- de masquer des pointages à l'espace admin.
DO $$
BEGIN
  IF to_regclass('public.attendances') IS NULL THEN
    RAISE EXCEPTION 'public.attendances introuvable : vérifier le nom de la table.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'attendances' AND c.relrowsecurity
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = 'attendances'
  ) THEN
    EXECUTE 'CREATE POLICY encheck_pointage_lecture_attendances
               ON public.attendances FOR SELECT TO anon, authenticated
               USING (true)';
    RAISE NOTICE 'RLS active sans politique : politique de lecture ajoutée.';
  ELSE
    RAISE NOTICE 'Aucune politique à ajouter (RLS inactive, ou déjà couverte).';
  END IF;
END $$;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 3 — TEST
-- Rejoue, en rôle anon, exactement la lecture de getHistoriquePointages.
-- Remplace la valeur de employee_id par un employé qui a pointé aujourd'hui.
--
-- Tu peux la récupérer dans l'espace admin, ou laisser le SELECT du dessous
-- prendre le premier employé ayant un pointage.
-- ──────────────────────────────────────────────────────────────────────────
SET ROLE anon;

SELECT employee_id, check_time, check_type
FROM public.attendances
ORDER BY check_time DESC
LIMIT 5;

RESET ROLE;

-- Ce SELECT doit renvoyer des lignes. S'il en renvoie, l'écran Historique de
-- l'app les affichera dès le prochain rechargement.

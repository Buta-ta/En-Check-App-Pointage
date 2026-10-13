-- ══════════════════════════════════════════════════════════════════════════
-- EN-CHECK POINTAGE — ACCÈS ANONYME AUX DONNÉES PUBLIQUES
-- ══════════════════════════════════════════════════════════════════════════
--
-- QUEL PROBLÈME CE SCRIPT RÈGLE
-- ───────────────────────────────────────────────────────────────────────────
-- L'app de pointage (Flutter Web sur Vercel) n'est PAS authentifiée : elle
-- parle à Supabase avec la clé publique, donc avec le rôle Postgres `anon`.
--
-- Quand on saisit un code entreprise (PHAR050), le client appelle :
--
--     GET /rest/v1/enterprises?select=*&code=eq.PHAR050&is_active=eq.true
--
-- et reçoit `401 Unauthorized`. Côté Postgres, le journal montre :
--
--     event_message  : permission denied for table enterprises
--     sql_state_code : 42501
--     database_user  : authenticator
--
-- 42501 « permission denied for table » n'est PAS un problème de RLS :
-- une RLS sans politique renvoie simplement un résultat VIDE. C'est un
-- problème de GRANT — le rôle `anon` n'a pas reçu le droit SELECT sur
-- public.enterprises. PostgREST se connecte en `authenticator` puis fait
-- `SET ROLE anon` ; c'est ce rôle-là qui se voit refuser l'accès.
--
-- D'où vient l'erreur dans l'app : `lib/screens/welcome_screen.dart` attrape
-- TOUTE exception et affiche « Erreur de connexion internet », alors qu'il
-- s'agit d'un refus d'autorisation de la base. Le message induit en erreur.
--
-- COMMENT L'APPLIQUER
-- ───────────────────────────────────────────────────────────────────────────
-- Dashboard Supabase → SQL Editor → coller ce fichier → Run.
-- Il est idempotent : on peut le rejouer sans effet de bord.
--
-- ⚠️ CE SCRIPT N'ACTIVE JAMAIS RLS LUI-MÊME. Il n'ajoute une politique QUE
--    si la table l'a déjà. Activer RLS sur `enterprises` restreindrait aussi
--    l'espace admin (qui doit pouvoir lire les entreprises inactives) : ce
--    n'est pas l'objet de ce correctif.
-- ══════════════════════════════════════════════════════════════════════════

-- ── 0. ÉTAT DES LIEUX (lecture seule — à lancer avant, pour comparer) ──────
-- Qui a quoi sur les tables publiques :
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated')
ORDER BY table_name, grantee, privilege_type;

-- RLS est-elle active, et sur quelles tables ?
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_active,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS nb_politiques
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'v', 'p')
ORDER BY c.relname;

-- ══════════════════════════════════════════════════════════════════════════
-- 1. ACCÈS AU SCHÉMA
-- ══════════════════════════════════════════════════════════════════════════
-- Sans USAGE sur le schéma, aucun objet n'est visible, même avec un GRANT.
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════
-- 2. LE CATALOGUE ENTREPRISES — c'est LA table du 401
-- ══════════════════════════════════════════════════════════════════════════
GRANT SELECT ON TABLE public.enterprises TO anon, authenticated;

-- Politique de lecture : ajoutée UNIQUEMENT si RLS est déjà active.
-- `is_active = true` reproduit exactement le filtre que l'app applique
-- (.eq('is_active', true)) — l'app télécharge déjà le catalogue des
-- entreprises actives pour son cache hors-ligne, donc ce n'est pas une
-- exposition nouvelle.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'enterprises' AND c.relrowsecurity
  ) THEN
    EXECUTE 'DROP POLICY IF EXISTS encheck_pointage_lecture_enterprises ON public.enterprises';
    EXECUTE 'CREATE POLICY encheck_pointage_lecture_enterprises
               ON public.enterprises FOR SELECT TO anon, authenticated
               USING (is_active = true)';
    RAISE NOTICE 'enterprises : RLS active → politique de lecture encheck_pointage_lecture_enterprises créée.';
  ELSE
    RAISE NOTICE 'enterprises : RLS inactive → le GRANT SELECT suffit, aucune politique ajoutée.';
  END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 3. LES AUTRES OBJETS QUE L'APP DE POINTAGE TOUCHE EN DIRECT
-- ══════════════════════════════════════════════════════════════════════════
-- Libellés relevés dans lib/services/supabase_service.dart :
--   .from('enterprises')      → catalogue + recherche par code
--   .from('employees_public') → fiches employé + plannings embarqués
--   .from('attendances')      → historique de pointage
-- Chaque bloc est protégé : si l'objet n'existe pas, on l'ignore au lieu de
-- faire échouer tout le script.

DO $$
DECLARE
  t text;
  objets CONSTANT text[] := ARRAY['employees_public', 'attendances'];
BEGIN
  FOREACH t IN ARRAY objets LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('GRANT SELECT ON TABLE public.%I TO anon, authenticated', t);
      RAISE NOTICE 'public.% : GRANT SELECT accordé à anon, authenticated.', t;

      IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity
      ) THEN
        EXECUTE format('DROP POLICY IF EXISTS encheck_pointage_lecture_%s ON public.%I', t, t);
        EXECUTE format(
          'CREATE POLICY encheck_pointage_lecture_%s ON public.%I
             FOR SELECT TO anon, authenticated USING (true)', t, t);
        RAISE NOTICE 'public.% : RLS active → politique de lecture ajoutée.', t;
      END IF;
    ELSE
      RAISE NOTICE 'public.% : absent de ce projet, ignoré.', t;
    END IF;
  END LOOP;
END $$;

-- `employees_public` et `getEmployeeParId` embarquent des ressources liées
-- (enterprises, employee_schedules, work_schedules). PostgREST les lit avec le
-- même rôle : elles doivent donc être lisibles elles aussi.
DO $$
DECLARE
  t text;
  objets CONSTANT text[] := ARRAY['employee_schedules', 'work_schedules'];
BEGIN
  FOREACH t IN ARRAY objets LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('GRANT SELECT ON TABLE public.%I TO anon, authenticated', t);
      RAISE NOTICE 'public.% : GRANT SELECT accordé.', t;
    END IF;
  END LOOP;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 4. DROIT D'EXÉCUTION SUR LES FONCTIONS RPC DE L'APP
-- ══════════════════════════════════════════════════════════════════════════
-- Le reste du parcours (login PIN/QR, pointage, horloge serveur, visage) passe
-- par des RPC. Par défaut, une fonction créée sans clause explicite est
-- exécutable par PUBLIC — mais si l'une d'elles a été restreinte, l'app
-- échouera au moment du pointage plutôt qu'à la saisie du code. On s'assure
-- donc du droit, fonction par fonction, sans toucher aux fonctions admin.
DO $$
DECLARE
  f record;
  noms CONSTANT text[] := ARRAY[
    'encheck_entreprise_par_code',
    'encheck_server_time',
    'encheck_employee_login',
    'encheck_employee_login_qr',
    'encheck_punch',
    'encheck_photo_enregistrer',
    'encheck_config_visage',
    'encheck_visage_enroler',
    'encheck_visage_journaliser',
    'encheck_visage_lister',
    'encheck_zones_lister'
  ];
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(noms)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', f.signature);
    RAISE NOTICE 'EXECUTE accordé sur %', f.signature;
  END LOOP;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 5. BUCKETS DE STOCKAGE (photos de pointage et enrôlement facial)
-- ══════════════════════════════════════════════════════════════════════════
-- Libellés relevés dans lib/services/photo_service.dart (`attendance-photos`)
-- et lib/services/supabase_service.dart (`face-enrollments`).
-- On ne crée pas les buckets ici : ils sont déclarés dans l'espace admin.
-- On s'assure seulement que l'app peut y écrire et y lire publiquement.
DO $$
DECLARE
  b text;
  buckets CONSTANT text[] := ARRAY['attendance-photos', 'face-enrollments'];
BEGIN
  FOREACH b IN ARRAY buckets LOOP
    IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = b) THEN
      RAISE NOTICE 'Bucket % présent.', b;
    ELSE
      RAISE NOTICE 'Bucket % ABSENT : les photos de pointage échoueront. Le créer dans Storage.', b;
    END IF;
  END LOOP;
END $$;

GRANT SELECT, INSERT ON TABLE storage.objects TO anon, authenticated;

DROP POLICY IF EXISTS encheck_pointage_ecriture_photos ON storage.objects;
CREATE POLICY encheck_pointage_ecriture_photos
  ON storage.objects FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id IN ('attendance-photos', 'face-enrollments'));

DROP POLICY IF EXISTS encheck_pointage_lecture_photos ON storage.objects;
CREATE POLICY encheck_pointage_lecture_photos
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id IN ('attendance-photos', 'face-enrollments'));

-- ══════════════════════════════════════════════════════════════════════════
-- 6. VÉRIFICATION FINALE
-- ══════════════════════════════════════════════════════════════════════════
-- Cette ligne est le test décisif : elle rejoue, en rôle anon, exactement la
-- requête que l'app envoie quand on saisit PHAR050. Elle doit renvoyer une
-- ligne, et non plus « permission denied ».
SET ROLE anon;
SELECT id, code, name, is_active FROM public.enterprises WHERE is_active = true LIMIT 5;
RESET ROLE;

-- Et le catalogue tel que l'app le télécharge pour son cache hors-ligne :
SELECT count(*) AS entreprises_actives_lisibles_en_anon
FROM public.enterprises
WHERE is_active = true;

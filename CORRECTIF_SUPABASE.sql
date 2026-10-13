-- ══════════════════════════════════════════════════════════════════════════
--  ⚠️  CE FICHIER N'EST PAS DU CODE DE L'APPLICATION.
--      IL NE SE DÉPLOIE PAS SUR VERCEL.
--
--  C'EST À TOI DE L'EXÉCUTER, UNE SEULE FOIS :
--      Dashboard Supabase  →  SQL Editor  →  coller tout ce fichier  →  Run
--
--  Projet concerné : cxggndvhwdolbtyezjde
-- ══════════════════════════════════════════════════════════════════════════
--
-- POURQUOI
-- ────────
-- Quand tu saisis PHAR050, l'app appelle :
--     GET /rest/v1/enterprises?select=*&code=eq.PHAR050&is_active=eq.true
-- et reçoit 401. Ton log Supabase dit :
--     permission denied for table enterprises   (code 42501)
--
-- L'app n'est pas connectée avec un compte : elle utilise la clé publique,
-- donc le rôle Postgres « anon ». Ce rôle n'a jamais reçu le droit de LIRE
-- la table enterprises. Ce n'est pas un bug de code, et aucun redéploiement
-- Vercel ne peut le corriger.
--
-- Tu peux rejouer ce fichier autant de fois que tu veux : il ne casse rien.
-- ══════════════════════════════════════════════════════════════════════════


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 1 — C'EST CELLE QUI DÉBLOQUE LA SAISIE DU CODE ENTREPRISE
-- ──────────────────────────────────────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.enterprises TO anon, authenticated;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 2 — TEST IMMÉDIAT
-- Rejoue, en rôle anon, exactement ce que l'app fait.
-- ➜ Si des lignes s'affichent : c'était bien le problème, PHAR050 marchera.
-- ➜ Si 0 ligne s'affiche sans erreur : passe à l'étape 3 (RLS).
-- ──────────────────────────────────────────────────────────────────────────
SET ROLE anon;
SELECT id, code, name, is_active
FROM public.enterprises
WHERE is_active = true
LIMIT 5;
RESET ROLE;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 3 — LE RESTE DU PARCOURS (employés, pointage, photos, visage)
-- Chaque bloc vérifie que l'objet existe avant d'y toucher : si une table
-- n'est pas dans ton projet, elle est ignorée au lieu de faire tout échouer.
-- ──────────────────────────────────────────────────────────────────────────

-- 3a. Les tables que l'app lit en direct
DO $$
DECLARE
  t text;
  objets CONSTANT text[] := ARRAY[
    'employees_public', 'attendances', 'employee_schedules', 'work_schedules'
  ];
BEGIN
  FOREACH t IN ARRAY objets LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('GRANT SELECT ON TABLE public.%I TO anon, authenticated', t);
      RAISE NOTICE 'public.% : droit de lecture accordé.', t;
    ELSE
      RAISE NOTICE 'public.% : absent de ce projet, ignoré.', t;
    END IF;
  END LOOP;
END $$;

-- 3b. Les fonctions que l'app appelle (login PIN, login QR, pointage,
--     heure serveur, photos, reconnaissance faciale, zones GPS)
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
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(noms)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', f.signature);
    RAISE NOTICE 'Droit d''exécution accordé sur %', f.signature;
  END LOOP;
END $$;

-- 3c. Les photos de pointage et d'enrôlement facial
GRANT SELECT, INSERT ON TABLE storage.objects TO anon, authenticated;

DROP POLICY IF EXISTS encheck_pointage_ecriture_photos ON storage.objects;
CREATE POLICY encheck_pointage_ecriture_photos
  ON storage.objects FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id IN ('attendance-photos', 'face-enrollments'));

DROP POLICY IF EXISTS encheck_pointage_lecture_photos ON storage.objects;
CREATE POLICY encheck_pointage_lecture_photos
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id IN ('attendance-photos', 'face-enrollments'));


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 4 — SI L'ÉTAPE 2 A RENVOYÉ 0 LIGNE (RLS activée sans politique)
--
-- Ce bloc n'agit QUE si la RLS est déjà activée sur enterprises.
-- Il ne l'active jamais : l'activer empêcherait ton espace admin de lire
-- les entreprises désactivées.
-- ──────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'enterprises'
      AND c.relrowsecurity
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = 'enterprises'
  ) THEN
    EXECUTE 'CREATE POLICY encheck_pointage_lecture_enterprises
               ON public.enterprises FOR SELECT TO anon, authenticated
               USING (is_active = true)';
    RAISE NOTICE 'RLS était active sans politique : politique de lecture ajoutée.';
  ELSE
    RAISE NOTICE 'Aucune politique à ajouter.';
  END IF;
END $$;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 5 — VÉRIFICATION FINALE
-- ──────────────────────────────────────────────────────────────────────────
SET ROLE anon;
SELECT count(*) AS entreprises_lisibles_par_l_app
FROM public.enterprises
WHERE is_active = true;
RESET ROLE;

-- Ce nombre doit être supérieur à 0. Ensuite : recharge l'app de pointage
-- et resaisis PHAR050.

-- ══════════════════════════════════════════════════════════════════════════
--  ⚠️  À EXÉCUTER DANS : Dashboard Supabase → SQL Editor → Run
--      Ce fichier ne se déploie pas sur Vercel.
--
--  Projet : cxggndvhwdolbtyezjde
-- ══════════════════════════════════════════════════════════════════════════
--
-- L'ERREUR
-- ────────
--     POST /rest/v1/rpc/encheck_employee_login_qr   400 (Bad Request)
--     PostgrestException(message: column es.work_schedule_id does not exist,
--                        code: 42703)
--
-- 42703 = « cette colonne n'existe pas ».
--
-- D'OÙ ÇA VIENT
-- ─────────────
-- Ce n'est PAS l'app Flutter, et ce n'est PAS un problème de droits (le 401
-- précédent est bien réglé : la synchronisation annonce maintenant
-- « ✅ Données hors-ligne téléchargées avec succès »).
--
-- C'est le CORPS de la fonction SQL `encheck_employee_login_qr`, côté base.
-- Elle fait une jointure aliasée `es` sur la table `employee_schedules` et
-- y cherche une colonne `work_schedule_id`. Cette colonne n'existe pas :
-- la clé étrangère vers `work_schedules` s'appelle **`schedule_id`**.
--
-- Preuves dans le dépôt En-Check (l'espace admin, qui fonctionne) :
--   src/pages/Employes.jsx:690        employee_schedules → schedule_id,
--                                     use_custom_hours, custom_start_time, …
--   src/pages/Employes.jsx:758        scheduleData.schedule_id &&
--                                     scheduleData.work_schedules
--   src/hooks/useNotifications.js:394 s.schedule_id ? workSchedulesById[...]
--
-- L'app de pointage, elle, est correcte : elle lit `custom_start_time` sur
-- employee_schedules et `start_time` sur work_schedules
-- (lib/screens/pointage_screen.dart:2755 et :2768). Rien à changer côté Dart.
--
-- LA FONCTION `encheck_employee_login` (login par PIN) contient très
-- probablement la même requête : l'étape 2 le vérifie pour toutes les
-- fonctions du schéma, pas seulement celle-là.
-- ══════════════════════════════════════════════════════════════════════════


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 1 — CONFIRMER LE NOM DE LA COLONNE
-- Doit lister `schedule_id` et NE PAS lister `work_schedule_id`.
-- ──────────────────────────────────────────────────────────────────────────
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'employee_schedules'
ORDER BY ordinal_position;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 2 — QUELLES FONCTIONS CONTIENNENT LA RÉFÉRENCE CASSÉE ?
-- Balaye tout le schéma public, pas seulement encheck_employee_login_qr.
-- ──────────────────────────────────────────────────────────────────────────
SELECT p.proname                                   AS fonction,
       pg_get_function_identity_arguments(p.oid)   AS arguments,
       (length(pg_get_functiondef(p.oid))
        - length(replace(pg_get_functiondef(p.oid),
                         'work_schedule_id', '')))
         / length('work_schedule_id')              AS occurrences
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND pg_get_functiondef(p.oid) LIKE '%work_schedule_id%'
ORDER BY p.proname;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 3 — APERÇU AVANT / APRÈS (ne modifie rien)
-- À lire avant l'étape 4 : on remplace le mot entier `work_schedule_id`
-- par `schedule_id`, jamais un mot qui le contiendrait.
-- ──────────────────────────────────────────────────────────────────────────
SELECT p.proname AS fonction,
       trim(both E'\n' from ligne_avant)  AS avant,
       trim(both E'\n' from replace(ligne_avant, 'work_schedule_id', 'schedule_id')) AS apres
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL unnest(string_to_array(pg_get_functiondef(p.oid), E'\n')) AS ligne_avant
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND ligne_avant ~ '(^|[^A-Za-z0-9_$])work_schedule_id([^A-Za-z0-9_$]|$)';


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 4 — APPLIQUER LE CORRECTIF
--
-- Trois garde-fous avant d'écrire quoi que ce soit :
--   • si `work_schedule_id` existe vraiment, on ne touche à rien ;
--   • si `schedule_id` n'existe pas non plus, on s'arrête en erreur ;
--   • le remplacement est borné aux mots entiers, donc un paramètre nommé
--     `p_work_schedule_id` ne serait PAS renommé par accident.
--
-- pg_get_functiondef renvoie la définition complète (signature, langue,
-- SECURITY DEFINER, search_path) : la fonction est recréée à l'identique,
-- seul le nom de colonne change.
-- ──────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  f       record;
  def     text;
  corrige text;
  nb      integer := 0;
BEGIN
  IF to_regclass('public.employee_schedules') IS NULL THEN
    RAISE EXCEPTION 'public.employee_schedules introuvable : schéma inattendu.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'employee_schedules'
      AND column_name  = 'work_schedule_id'
  ) THEN
    RAISE NOTICE 'work_schedule_id EXISTE sur employee_schedules : le diagnostic ne tient pas, rien n''a été modifié.';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'employee_schedules'
      AND column_name  = 'schedule_id'
  ) THEN
    RAISE EXCEPTION 'Ni work_schedule_id ni schedule_id sur employee_schedules. Vérifier le schéma à la main avant de continuer.';
  END IF;

  FOR f IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ~ '(^|[^A-Za-z0-9_$])work_schedule_id([^A-Za-z0-9_$]|$)'
  LOOP
    SELECT pg_get_functiondef(f.oid) INTO def;

    corrige := regexp_replace(def, '^CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION');
    corrige := regexp_replace(
      corrige,
      '(^|[^A-Za-z0-9_$])work_schedule_id([^A-Za-z0-9_$]|$)',
      '\1schedule_id\2',
      'g'
    );

    EXECUTE corrige;
    nb := nb + 1;
    RAISE NOTICE '% : work_schedule_id → schedule_id, fonction recréée.', f.proname;
  END LOOP;

  IF nb = 0 THEN
    RAISE NOTICE 'Aucune fonction ne référençait work_schedule_id : rien à corriger.';
  ELSE
    RAISE NOTICE '% fonction(s) corrigée(s).', nb;
  END IF;
END $$;


-- ──────────────────────────────────────────────────────────────────────────
-- ÉTAPE 5 — VÉRIFICATION
-- 5a. Plus aucune fonction ne doit référencer la colonne inexistante.
--     Ce SELECT doit renvoyer 0 ligne.
-- ──────────────────────────────────────────────────────────────────────────
SELECT p.proname AS fonction_toujours_cassee
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND pg_get_functiondef(p.oid) ~ '(^|[^A-Za-z0-9_$])work_schedule_id([^A-Za-z0-9_$]|$)';

-- 5b. La fonction est toujours là, avec sa signature et son mode d'exécution.
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef                               AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('encheck_employee_login_qr', 'encheck_employee_login');

-- Ensuite : recharge l'app de pointage et rescanne le badge.

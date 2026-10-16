-- ═══════════════════════════════════════════════════════════════════════════
--  CORRECTIF ARBITRAGE N°2/3 — P1 (départ manuel puni) + P2 (date future)
-- ═══════════════════════════════════════════════════════════════════════════
--  ⚠️  CE FICHIER N'EST PAS DU CODE DE L'APPLICATION.
--      IL NE SE DÉPLOIE PAS SUR VERCEL.
--
--  C'EST À TOI DE L'EXÉCUTER, UNE SEULE FOIS (mais il est rejouable sans
--  effet de bord) :
--
--      Dashboard Supabase → SQL Editor → coller TOUT ce fichier → Run
--
--  Projet : cxggndvhwdolbtyezjde
--  Fiche   : FICHE POUR L'ÉQUIPE En-Check-App-Pointage — ARBITRAGE N°2/3
--            (16/10/2026), problèmes P1 et P2
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE ÇA FAIT, EN SIMPLE
-- ─────────────────────────
--
--  P1 · Le problème : quand le système doutait (« Arrivée ou Départ ? ») et
--       que l'employé cliquait DÉPART, le pointage était marqué 🚩 SUSPECT —
--       puni comme un oubli, alors que c'est une sortie parfaitement
--       légitime (cas Hippo BIYOKILA, 16/10 à 01:14).
--
--       a) l'application (corrigée dans la PR) n'envoie plus l'anomalie du
--          doute quand l'employé tranche : elle envoie le code neutre
--          `resolution_employe` ;
--       b) la fonction `encheck_pointage_marquer` (recréée ICI) ne pose
--          suspect=true QUE si l'anomalie est encore NON RÉSOLUE — jamais
--          sur un DÉPART manuel qui ferme une session oubliée ;
--       c) les lignes DÉJÀ faussement marquées sont réparées plus bas
--          (PARTIE 4) : suspect=false, suspect_reason=NULL, anomalie=NULL.
--
--  P2 · Le problème : un pointage pouvait être écrit DANS LE FUTUR (un
--       boîtier mal réglé, une saisie « J+1 » côté admin…) et devenir une
--       fausse journée de travail.
--
--       → un trigger refuse désormais tout pointage dont check_time dépasse
--         « maintenant + 5 min » (réglable : `garde_fou_futur_minutes`).
--         Le message d'erreur commence par `horloge_futur`.
--
--  RÈGLES DE SÉCURITÉ RESPECTÉES (comme pour les livraisons admin)
--  ───────────────────────────────────────────────────────────────
--   1. aucune colonne inventée : on n'utilise que celles du schéma réel ;
--   2. une VÉRIFICATION de schéma AVANT toute modification (PARTIE 0) ;
--   3. le tout est TRANSACTIONNEL : si quelque chose échoue, RIEN n'est
--      appliqué (et tu peux rejouer le fichier entier) ;
--   4. idempotent : rejouer ne change rien de plus.
--
--  ⚠️ DÉPENDANCE : `encheck_seuil()` (source unique des seuils) vient de la
--     migration admin `20261016000001_fondations_auto_close_structure.sql`,
--     déjà exécutée en production le 16/10. La PARTIE 0 vérifie qu'elle est
--     là et te le dit clairement sinon.
-- ═══════════════════════════════════════════════════════════════════════════


BEGIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTIE 0 — VÉRIFICATIONS AVANT DE TOUCHER À QUOI QUE CE SOIT
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  c_colonnes CONSTANT text[] := ARRAY[
    'id', 'employee_id', 'enterprise_id', 'check_time', 'check_type',
    'origine', 'anomalie', 'suspect', 'suspect_reason'
  ];
  v_col text;
BEGIN
  IF to_regclass('public.attendances') IS NULL THEN
    RAISE EXCEPTION 'Table public.attendances introuvable : ce script cible '
                    'le projet Supabase de l''application de pointage.';
  END IF;

  IF to_regclass('public.employees') IS NULL THEN
    RAISE EXCEPTION 'Table public.employees introuvable.';
  END IF;

  FOREACH v_col IN ARRAY c_colonnes LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name   = 'attendances'
         AND column_name  = v_col
    ) THEN
      RAISE EXCEPTION 'Colonne attendances.% introuvable : le schéma n''est '
                      'pas celui attendu. Ne rien modifier, signaler le '
                      'problème.', v_col;
    END IF;
  END LOOP;

  IF to_regprocedure('public.encheck_seuil(uuid, text, numeric)') IS NULL THEN
    RAISE EXCEPTION 'encheck_seuil() est absente : exécute d''abord la '
                    'migration admin 20261016000001_fondations_auto_close_structure.sql '
                    '(source unique des seuils), puis rejoue ce fichier.';
  END IF;

  RAISE NOTICE '✓ Vérifications OK — on peut appliquer les correctifs.';
END $$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTIE 1 — LE CERVEAU AVEC SES SEUILS LU EN BASE (cohérence fiche 2/3)
-- ═══════════════════════════════════════════════════════════════════════════
--  Même fonction que `SYSTEME_IN_OUT.sql` (source versionnée dans le dépôt
--  En-Check-App-Pointage). Les seuils viennent de `encheck_reglages_pointage`
--  via `encheck_seuil()` : oubli_sortie_heures (12 h), presence_courte_minutes
--  (5 min), seuil_rebond_secondes (60 s) — plus aucun chiffre en dur.

CREATE OR REPLACE FUNCTION public.encheck_type_suggere(p_employee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- ── LES RÉGLAGES : lus dans `encheck_reglages_pointage` (source unique) ──
  v_enterprise        uuid;
  v_seuil_oubli_h     numeric;
  v_presence_courte_m numeric;
  v_garde_fou_s       numeric;
  v_seuil_presence    interval;
  v_presence_courte   interval;
  v_garde_fou         interval;

  v_dernier_type text;
  v_dernier_time timestamptz;
  v_anciennete   interval;
  v_type         text;
  v_confiance    text;
  v_raison       text;
  v_anomalie     text;
BEGIN
  IF p_employee_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'raison', 'employe_manquant');
  END IF;

  -- Les réglages se lisent au niveau de l'entreprise de l'employé, avec
  -- repli sur le réglage global puis sur le défaut.
  SELECT e.enterprise_id INTO v_enterprise
    FROM public.employees e
   WHERE e.id = p_employee_id;

  v_seuil_oubli_h     := public.encheck_seuil(v_enterprise, 'oubli_sortie_heures', 12);
  v_presence_courte_m := public.encheck_seuil(v_enterprise, 'presence_courte_minutes', 5);
  v_garde_fou_s       := public.encheck_seuil(v_enterprise, 'seuil_rebond_secondes', 60);

  v_seuil_presence   := make_interval(mins => (v_seuil_oubli_h * 60)::int);
  v_presence_courte  := make_interval(mins => v_presence_courte_m::int);
  v_garde_fou        := make_interval(secs => v_garde_fou_s::double precision);

  SELECT a.check_type, a.check_time::timestamptz
    INTO v_dernier_type, v_dernier_time
    FROM public.attendances a
   WHERE a.employee_id = p_employee_id
   ORDER BY a.check_time DESC
   LIMIT 1;

  -- Règle 1 : aucun pointage connu → c'est une arrivée.
  IF v_dernier_type IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true, 'bloque', false,
      'type', 'in', 'confiance', 'haute',
      'raison', 'aucun_pointage', 'anomalie', null);
  END IF;

  v_anciennete := now() - v_dernier_time;

  -- Règle 2 : garde-fou anti double-geste.
  IF v_anciennete < v_garde_fou THEN
    RETURN jsonb_build_object(
      'ok', true, 'bloque', true,
      'raison', 'pointage_trop_recent',
      'secondes', GREATEST(EXTRACT(EPOCH FROM v_anciennete)::int, 0),
      'dernier_type', v_dernier_type);
  END IF;

  IF v_dernier_type = 'out' THEN
    -- Règle 3
    v_type := 'in'; v_confiance := 'haute';
    v_raison := 'derniere_sortie'; v_anomalie := null;

  ELSIF v_anciennete > v_seuil_presence THEN
    -- Règle 5 : la présence est anormalement longue.
    v_type := 'in'; v_confiance := 'basse';
    v_raison := 'presence_trop_longue'; v_anomalie := 'sortie_oubliee';

  ELSE
    -- Règle 4
    v_type := 'out'; v_raison := 'derniere_entree'; v_confiance := 'haute';
    v_anomalie := null;

    IF v_anciennete < v_presence_courte THEN
      v_anomalie := 'presence_courte';
      v_confiance := 'moyenne';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'bloque', false,
    'type', v_type,
    'confiance', v_confiance,
    'raison', v_raison,
    'anomalie', v_anomalie,
    'dernier_type', v_dernier_type,
    'anciennete_secondes', EXTRACT(EPOCH FROM v_anciennete)::int,
    'seuil_presence_heures', EXTRACT(EPOCH FROM v_seuil_presence) / 3600);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.encheck_type_suggere(uuid) TO anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTIE 2 — P1 : suspect UNIQUEMENT sur anomalie non résolue
-- ═══════════════════════════════════════════════════════════════════════════
--  Avant : suspect=true dès que p_anomalie IS NOT NULL, quel que soit le type
--  choisi → un DÉPART tranché par l'employé était puni comme un oubli.
--
--  Maintenant : un doute RÉSOLU n'est plus une anomalie.
--   · `resolution_employe` (l'humain a tranché) → jamais suspect, jamais
--     d'alerte ; le code est conservé pour l'audit ;
--   · `sortie_oubliee` sur un DÉPART d'origine `manuel` → jamais suspect :
--     l'employé qui pointe sa sortie ferme justement la session oubliée ;
--   · sinon (anomalie encore non résolue) → suspect=true + alerte, comme
--     avant.

CREATE OR REPLACE FUNCTION public.encheck_pointage_marquer(
  p_attendance_id uuid,
  p_origine       text,
  p_raison        text DEFAULT NULL,
  p_anomalie      text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_att          record;
  v_jour         date;
  v_resolu       boolean;
  v_anomalie_finale text;
BEGIN
  -- On lit d'abord la ligne : le sort de l'anomalie dépend du pointage
  -- lui-même (type choisi + origine de la décision), pas seulement de ce que
  -- l'application transmet.
  SELECT id, employee_id, enterprise_id,
         check_type, check_time::timestamptz AS ct,
         origine, anomalie, suspect, suspect_reason
    INTO v_att
    FROM public.attendances
   WHERE id = p_attendance_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'raison', 'pointage_introuvable');
  END IF;

  -- ── FICHE ARBITRAGE 2/3, P1 : un doute RÉSOLU n'est plus une anomalie ──
  v_resolu :=
       (p_anomalie IS NULL)
    OR (p_anomalie = 'resolution_employe')
    OR (p_anomalie = 'sortie_oubliee'
        AND v_att.check_type = 'out'
        AND COALESCE(p_origine, v_att.origine) = 'manuel');

  -- Que garde-t-on dans la colonne `anomalie` ?
  --   · `resolution_employe` → conservé tel quel (traçabilité du doute) ;
  --   · anomalie résolue     → NULL (cible fiche 2/3 sur les lignes Hippo) ;
  --   · anomalie non résolue → le code transmis ;
  --   · rien de transmis     → on garde l'existant.
  v_anomalie_finale :=
       CASE
         WHEN p_anomalie IS NULL                THEN v_att.anomalie
         WHEN p_anomalie = 'resolution_employe' THEN 'resolution_employe'
         WHEN v_resolu                          THEN NULL
         ELSE p_anomalie
       END;

  UPDATE public.attendances
     SET origine         = COALESCE(p_origine, origine),
         decision_raison = COALESCE(p_raison, decision_raison),
         anomalie        = v_anomalie_finale,
         suspect         = CASE
             WHEN p_anomalie IS NOT NULL AND NOT v_resolu THEN true
             ELSE suspect
           END,
         suspect_reason  = CASE
             WHEN p_anomalie IS NULL OR v_resolu THEN suspect_reason
             WHEN suspect_reason IS NULL OR btrim(suspect_reason) = ''
               THEN p_anomalie
             WHEN suspect_reason LIKE '%' || p_anomalie || '%'
               THEN suspect_reason
             ELSE suspect_reason || '|' || p_anomalie
           END
   WHERE id = p_attendance_id;

  -- Jour civil du pointage, en heure du Bénin. Calculé à part : s'il
  -- échoue, on retombe sur la date du jour plutôt que de perdre l'alerte.
  BEGIN
    v_jour := (v_att.ct AT TIME ZONE 'Africa/Porto-Novo')::date;
  EXCEPTION WHEN OTHERS THEN
    v_jour := (now() AT TIME ZONE 'Africa/Porto-Novo')::date;
  END;

  -- Alerte à l'administrateur. Un À-CÔTÉ qui ne doit jamais faire échouer le
  -- pointage. ⚠️ AUCUNE alerte pour un doute résolu (P1).
  IF p_anomalie IS NOT NULL AND NOT v_resolu THEN
    BEGIN
      PERFORM public.encheck_alerte_poser(
        p_enterprise := v_att.enterprise_id,
        p_employee   := v_att.employee_id,
        p_jour       := v_jour,
        p_type       := 'pointage_anomalie',
        p_gravite    := 'moyenne',
        p_titre      := 'Pointage à vérifier',
        p_detail     := 'Anomalie détectée par le système : ' || p_anomalie,
        p_ref        := v_att.id,
        p_appareil   := NULL
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Alerte non envoyée (sans conséquence) : %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'anomalie', v_anomalie_finale,
                            'suspect', NOT v_resolu AND p_anomalie IS NOT NULL);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.encheck_pointage_marquer(uuid, text, text, text)
  TO anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTIE 3 — P2 : GARDE-FOU « DATE FUTURE » (trigger de base)
-- ═══════════════════════════════════════════════════════════════════════════
--  Tout pointage dont check_time dépasse « maintenant + 5 min » est REFUSÉ.
--  Le seuil est réglable (`garde_fou_futur_minutes` dans
--  `encheck_reglages_pointage`). Pour la marge admin (10 min) :
--
--    INSERT INTO public.encheck_reglages_pointage (cle, valeur, commentaire)
--    VALUES ('garde_fou_futur_minutes', '10', 'Aligné sur la marge admin')
--    ON CONFLICT DO NOTHING;
--
--  Ce trigger couvre TOUTES les écritures (encheck_punch, corrections admin,
--  imports) et complète celui de l'admin (`trg_attendances_refuser_futur`,
--  INSERT seul, 10 min) qui reste en place.

CREATE OR REPLACE FUNCTION public.encheck_punch_garde_fou_futur()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_marge_minutes numeric;
BEGIN
  IF COALESCE(current_setting('encheck.test_rejeu', true), '') = '1' THEN
    RETURN NEW;   -- harnais de test explicite, jamais la production
  END IF;

  v_marge_minutes := COALESCE(
      public.encheck_seuil(NEW.enterprise_id, 'garde_fou_futur_minutes', 5), 5);

  IF NEW.check_time IS NOT NULL
     AND NEW.check_time > now() + make_interval(mins => v_marge_minutes::int) THEN
    RAISE EXCEPTION
      'horloge_futur : pointage refusé — check_time (%) est dans le futur (marge : % min). Un pointage ne peut pas se trouver dans le futur : vérifiez la date/heure du boîtier ou de la saisie.',
      NEW.check_time, v_marge_minutes
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_attendances_garde_fou_futur ON public.attendances;
CREATE TRIGGER trg_attendances_garde_fou_futur
  BEFORE INSERT OR UPDATE OF check_time ON public.attendances
  FOR EACH ROW
  EXECUTE FUNCTION public.encheck_punch_garde_fou_futur();

REVOKE ALL ON FUNCTION public.encheck_punch_garde_fou_futur() FROM PUBLIC, anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTIE 4 — P1(c) : RÉPARER LES LIGNES DÉJÀ FAUSSEMENT MARQUÉES
-- ═══════════════════════════════════════════════════════════════════════════
--  Cible fiche 2/3 : Hippo BIYOKILA, 16/10 à 01:14 —
--  suspect=false, suspect_reason=NULL, anomalie=NULL.
--
--  On répare TOUTES les lignes du même type (un DÉPART manuel qui fermait
--  une session oubliée et qui a été marqué 🚩 à tort), puis on s'assure du
--  cas Hippo nommément. Rejouable : la deuxième fois, 0 ligne touchée.

-- 4a. APERÇU — ce qui va être réparé (lecture seule) ----------------------
SELECT a.id,
       e.first_name || ' ' || e.last_name AS employe,
       a.check_time,
       a.check_type,
       a.origine,
       a.anomalie,
       a.suspect,
       a.suspect_reason
  FROM public.attendances a
  JOIN public.employees e ON e.id = a.employee_id
 WHERE a.anomalie = 'sortie_oubliee'
   AND a.check_type = 'out'
   AND a.origine = 'manuel'
 ORDER BY a.check_time;

-- 4b. RÉPARATION GÉNÉRALE — le motif P1 exact -----------------------------
UPDATE public.attendances
   SET suspect        = false,
       suspect_reason = NULL,
       anomalie       = NULL
 WHERE anomalie  = 'sortie_oubliee'
   AND check_type = 'out'
   AND origine    = 'manuel';

-- 4c. CAS HIPPO, NOMMÉMENT — 16/10/2026 à 01:14 (heure du Bénin) ----------
--     Même si l'origine n'a pas été inscrite sur la ligne, on la répare.
SELECT a.id,
       a.check_time,
       a.suspect,
       a.suspect_reason,
       a.anomalie
  FROM public.attendances a
  JOIN public.employees e ON e.id = a.employee_id
 WHERE e.first_name ILIKE 'hippo%'
   AND e.last_name  ILIKE 'biyokila%'
   AND (a.check_time::timestamptz AT TIME ZONE 'Africa/Porto-Novo')
       >= TIMESTAMP '2026-10-16 01:11:00'
   AND (a.check_time::timestamptz AT TIME ZONE 'Africa/Porto-Novo')
       <  TIMESTAMP '2026-10-16 01:17:00';

UPDATE public.attendances a
   SET suspect        = false,
       suspect_reason = NULL,
       anomalie       = NULL
  FROM public.employees e
 WHERE a.employee_id = e.id
   AND e.first_name ILIKE 'hippo%'
   AND e.last_name  ILIKE 'biyokila%'
   AND a.anomalie = 'sortie_oubliee'
   AND (a.check_time::timestamptz AT TIME ZONE 'Africa/Porto-Novo')
       >= TIMESTAMP '2026-10-16 01:11:00'
   AND (a.check_time::timestamptz AT TIME ZONE 'Africa/Porto-Novo')
       <  TIMESTAMP '2026-10-16 01:17:00';

-- 4d. VÉRIFICATION FINALE — la ligne Hippo doit être propre ---------------
SELECT a.id,
       e.first_name || ' ' || e.last_name AS employe,
       a.check_time,
       a.check_type,
       a.suspect,
       a.suspect_reason,
       a.anomalie
  FROM public.attendances a
  JOIN public.employees e ON e.id = a.employee_id
 WHERE e.first_name ILIKE 'hippo%'
   AND e.last_name  ILIKE 'biyokila%'
   AND (a.check_time::timestamptz AT TIME ZONE 'Africa/Porto-Novo')
       >= TIMESTAMP '2026-10-16 01:11:00'
   AND (a.check_time::timestamptz AT TIME ZONE 'Africa/Porto-Novo')
       <  TIMESTAMP '2026-10-16 01:17:00';


COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════
-- FIN — RÉCAPITULATIF DE CE QUI A ÉTÉ FAIT
-- ═══════════════════════════════════════════════════════════════════════════
--  · encheck_type_suggere   : seuils lus dans encheck_reglages_pointage ;
--  · encheck_pointage_marquer : suspect=true seulement si anomalie non
--    résolue (P1) — plus de faux drapeau sur un « Départ » choisi ;
--  · trigger trg_attendances_garde_fou_futur : refus des pointages dans le
--    futur au-delà de garde_fou_futur_minutes, défaut 5 min (P2) ;
--  · lignes déjà faussement marquées réparées (cas Hippo inclus).
--
--  Teste le garde-fou « date future » si tu veux le voir de tes yeux :
--    INSERT INTO public.attendances (employee_id, enterprise_id, check_type,
--                                    check_time)
--    VALUES (<id employé>, <id entreprise>, 'out', now() + interval '1 day');
--    → ERROR : horloge_futur : pointage refusé …
-- ═══════════════════════════════════════════════════════════════════════════

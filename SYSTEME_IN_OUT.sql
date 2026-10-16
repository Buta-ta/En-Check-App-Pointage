-- ═══════════════════════════════════════════════════════════════════════════
--  EN-CHECK — SYSTÈME INTELLIGENT DE DÉCISION ENTRÉE / SORTIE
-- ═══════════════════════════════════════════════════════════════════════════
--
--  OÙ EXÉCUTER :  Dashboard Supabase → SQL Editor → coller → Run
--  PROJET      :  cxggndvhwdolbtyezjde
--
--  CE QUE CE SCRIPT FAIT
--  ---------------------
--  Aujourd'hui, l'application décide du type du pointage avec une bascule
--  aveugle : « si le dernier était une entrée, alors une sortie ». Elle ne
--  regarde ni l'heure, ni le contexte. Un seul pointage perdu et toute la
--  suite reste inversée jusqu'à ce qu'un humain corrige à la main.
--
--  Ce script installe un CERVEAU dans la base : une fonction qui déduit le
--  type du contexte, et qui indique à quel point elle est sûre d'elle.
--
--      confiance HAUTE   → on enregistre sans rien demander
--      confiance MOYENNE → on enregistre et on signale l'anomalie
--      confiance BASSE   → on demande à l'employé
--
--  Le point essentiel : le système SE RÉPARE. Une sortie oubliée n'inverse
--  plus la séquence indéfiniment ; elle est détectée au pointage suivant.
--
--  SÉCURITÉ
--  --------
--  Les fonctions sont SECURITY DEFINER : elles lisent la table `attendances`
--  malgré la politique RLS `encheck_scope_entreprise`, exactement comme
--  `encheck_pointages_historique` le fait déjà. On n'affaiblit aucune
--  politique : on emprunte la porte de service.
--
--  Ce script est IDEMPOTENT : tu peux le rejouer sans effet de bord.
--
--  NOUVEAU (2e version) - par rapport au script deja execute :
--    - les anomalies ecrivent aussi `suspect` / `suspect_reason`, le
--      mecanisme que la page Pointages affiche DEJA ;
--    - une alerte est envoyee a l'administrateur via `encheck_alerte_poser`,
--      SANS jamais inventer ni corriger de donnees ;
--    - la correction par l'employe exige le jeton de session et reste
--      limitee a 30 minutes.
--
--  NOUVEAU (3e version) — fiche ARBITRAGE N°2/3 (16/10/2026) :
--    P1 · `encheck_pointage_marquer` ne pose suspect=true QUE si l'anomalie
--        est encore NON RÉSOLUE : jamais sur un DÉPART manuel qui ferme une
--        session oubliée (code neutre `resolution_employe`, cas Hippo) ;
--    P2 · garde-fou « date future » : tout pointage dont check_time dépasse
--        « now() + 5 min » est REFUSÉ en base (trigger + réglage
--        `garde_fou_futur_minutes`) — un boîtier mal réglé n'écrit plus le
--        pointage de demain ;
--    · les seuils du cerveau sont lus dans `encheck_reglages_pointage` via
--      `encheck_seuil()` (source unique — arbitrage : aucun chiffre en dur).
--
--  ⚠️ DÉPENDANCE : `encheck_seuil()` vient de la migration ADMIN
--     `20261016000001_fondations_auto_close_structure.sql` (déjà exécutée en
--     production le 16/10). Sans elle, le cerveau ne peut pas lire ses
--     seuils : exécute d'abord cette migration, ou le script
--     `CORRECTIF_ARBITRAGE_2-3_P1_P2.sql` qui le vérifie pour toi.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
--  1. LES COLONNES DE TRAÇABILITÉ
-- ═══════════════════════════════════════════════════════════════════════════
--  Toutes sont OPTIONNELLES (aucune contrainte NOT NULL, sauf un booléen
--  avec valeur par défaut) : les pointages déjà enregistrés restent valides
--  et aucune application existante ne casse.

ALTER TABLE public.attendances ADD COLUMN IF NOT EXISTS origine text;
  -- 'auto'        : décidé par le cerveau, sans intervention
  -- 'manuel'      : l'employé a dû choisir (le système doutait)
  -- 'hors_ligne'  : décidé sans serveur
  -- 'corrige'     : le type a été corrigé après coup

ALTER TABLE public.attendances ADD COLUMN IF NOT EXISTS decision_raison text;
  -- la règle qui a décidé : aucune_pointage, derniere_sortie,
  -- derniere_entree, presence_trop_longue, bascule_locale…

ALTER TABLE public.attendances ADD COLUMN IF NOT EXISTS anomalie text;
  -- 'sortie_oubliee'     : une entrée vieille de plus du seuil d'oubli
  -- 'presence_courte'    : une sortie quelques minutes après l'entrée
  -- 'resolution_employe' : le doute a été tranché par l'employé lui-même
  --                        (fiche 2/3) — code NEUTRE, jamais suspect
  -- NULL                 : rien à signaler

ALTER TABLE public.attendances
  ADD COLUMN IF NOT EXISTS modifie_par_employe boolean NOT NULL DEFAULT false;

ALTER TABLE public.attendances ADD COLUMN IF NOT EXISTS modifie_le timestamptz;


-- ═══════════════════════════════════════════════════════════════════════════
--  2. LE JOURNAL DES CORRECTIONS
-- ═══════════════════════════════════════════════════════════════════════════
--  Quand un employé corrige son type, on ne se contente pas d'écraser la
--  valeur : on garde la trace de qui a changé quoi, quand, et depuis quelle
--  valeur. C'est ce qui permet à l'admin de voir « modifié par l'employé ».

CREATE TABLE IF NOT EXISTS public.attendance_corrections (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id  uuid        NOT NULL REFERENCES public.attendances(id) ON DELETE CASCADE,
  employee_id    uuid        NOT NULL,
  enterprise_id  uuid,
  ancien_type    text,
  nouveau_type   text        NOT NULL,
  origine        text        NOT NULL DEFAULT 'employe',
  corrige_le     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_attendance_corrections_attendance
  ON public.attendance_corrections (attendance_id);

-- L'application doit pouvoir écrire une correction (elle est anonyme).
-- En revanche, seul un utilisateur authentifié peut LIRE le journal.
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT INSERT ON public.attendance_corrections TO anon, authenticated;
GRANT SELECT ON public.attendance_corrections TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
--  3. LE CERVEAU
-- ═══════════════════════════════════════════════════════════════════════════
--  Retourne, pour un employé :
--     type       : 'in' ou 'out'
--     confiance  : 'haute' | 'moyenne' | 'basse'
--     raison     : la règle appliquée
--     anomalie   : 'sortie_oubliee' | 'presence_courte' | null
--     bloque     : true si l'employé vient de pointer (garde-fou)
--
--  LA TABLE DE DÉCISION
--  ───────────────────
--   1. aucun pointage connu               → ENTRÉE, confiance haute
--   2. dernier pointage < 60 s            → BLOQUÉ (déjà pointé)
--   3. dernier = SORTIE                   → ENTRÉE, confiance haute
--   4. dernier = ENTRÉE, < seuil oubli    → SORTIE, confiance haute
--      (si la présence < seuil court      → SORTIE, confiance MOYENNE)
--   5. dernier = ENTRÉE, > seuil oubli    → ENTRÉE, confiance BASSE
--                                           + anomalie « sortie oubliée »
--
--  LES SEUILS VIENNENT DE LA BASE (fiche 2/3 : aucun chiffre en dur)
--  ────────────────────────────────────────────────────────────────
--  Source unique : `encheck_reglages_pointage`, lue par `encheck_seuil()`.
--  Valeurs par défaut (uniquement si le réglage est absent) :
--    · oubli_sortie_heures     → 12 h   (règles 4 et 5)
--    · presence_courte_minutes → 5 min  (règle 4, sortie suspecte)
--    · seuil_rebond_secondes   → 60 s   (règle 2, anti double-geste)
--
--  LA RÈGLE 5 EST CELLE QUI RÉPARE LE SYSTÈME
--  ───────────────────────────────────────────
--  Avec une simple bascule, une sortie oubliée inverse la séquence pour
--  toujours. Ici, au pointage suivant, le système voit que la dernière
--  entrée remonte à plus de 12 h, en déduit qu'elle a été oubliée, et
--  repart sur une ENTRÉE. La séquence se remet d'elle-même.
--
--  ⚠️ LE SYSTÈME N'INVENTE JAMAIS DE DONNÉES : il n'écrit pas de sortie
--     fictive. Il signale l'anomalie et laisse l'admin décider.

CREATE OR REPLACE FUNCTION public.encheck_type_suggere(p_employee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- ── LES RÉGLAGES : lus dans `encheck_reglages_pointage` (source unique) ──
  --    Les valeurs ci-dessous ne sont que des replis si le réglage est
  --    absent. Pour changer un seuil : UPDATE encheck_reglages_pointage
  --    (fiche 2/3 : aucun chiffre métier réécrit en dur).
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
--  4. MARQUER UN POINTAGE FRAÎCHEMENT ENREGISTRÉ
-- ═══════════════════════════════════════════════════════════════════════════
--  L'application appelle cette fonction juste après avoir enregistré un
--  pointage, pour y inscrire comment la décision a été prise.
--  Elle ne sert qu'à la traçabilité : si elle échoue, le pointage reste
--  parfaitement valide.

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
  --  Est « résolue » :
  --   · `resolution_employe` : l'employé a tranché lui-même dans le dialogue
  --     « Arrivée ou Départ ? » — le doute est levé par un humain ;
  --   · `sortie_oubliee` sur un DÉPART d'origine `manuel` : l'employé qui
  --     pointe sa sortie ferme justement la session oubliée (cas Hippo,
  --     16/10 01:14) ;
  --   · NULL : il n'y avait rien à signaler.
  --  Dans ces cas : suspect=true JAMAIS posé, et AUCUNE alerte.
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

  -- On se branche sur le mécanisme « suspect » que l'admin utilise DÉJÀ
  -- (page Pointages : drapeau suspect + traduction de suspect_reason).
  -- Inutile d'inventer un système parallèle : les anomalies apparaîtront
  -- ainsi dans les écrans existants, sans retouche côté admin.
  -- ⚠️ suspect=true UNIQUEMENT si l'anomalie est encore non résolue (P1) —
  --    et on ne touche JAMAIS à un suspect posé pour une autre raison.
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

  -- Alerte à l'administrateur. C'est un À-CÔTÉ : elle ne doit jamais faire
  -- échouer le pointage, qui est déjà enregistré. On ne connaît pas les
  -- valeurs exactes acceptées par p_type et p_gravite, donc si la base
  -- refuse, on encaisse l'échec et on continue.
  -- ⚠️ AUCUNE alerte pour un doute résolu (P1) : prévenir l'admin qu'un
  --    employé a simplement choisi « Départ » serait un faux signal.
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
--  5. CORRIGER LE TYPE D'UN POINTAGE (par l'employé)
-- ═══════════════════════════════════════════════════════════════════════════
--  L'employé peut corriger son type juste après avoir pointé. Trois garde-fous :
--
--    • le pointage doit exister ;
--    • il doit appartenir à l'employé indiqué ;
--    • il doit dater de MOINS DE 30 MINUTES. Passé ce délai, la correction
--      passe par l'admin. Sans cette limite, un employé pourrait modifier
--      ses heures de la semaine dernière.
--
--  Chaque correction est inscrite dans `attendance_corrections` et lève le
--  drapeau `modifie_par_employe` : l'admin la voit apparaître dans la page
--  Pointages.

CREATE OR REPLACE FUNCTION public.encheck_corriger_type(
  p_attendance_id uuid,
  p_employee_id   uuid,
  p_nouveau_type  text,
  p_jeton         text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_fenetre      constant interval := interval '30 minutes';
  v_att          record;
  v_employe_jeton uuid;
  v_jour         date;
BEGIN
  IF p_nouveau_type NOT IN ('in', 'out') THEN
    RETURN jsonb_build_object('ok', false, 'raison', 'type_invalide');
  END IF;

  SELECT id, employee_id, enterprise_id, check_type, check_time::timestamptz AS ct
    INTO v_att
    FROM public.attendances
   WHERE id = p_attendance_id
   FOR UPDATE;

  IF v_att.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'raison', 'pointage_introuvable');
  END IF;

  IF v_att.employee_id <> p_employee_id THEN
    RETURN jsonb_build_object('ok', false, 'raison', 'employe_non_proprietaire');
  END IF;

  -- Vérification du jeton de session, SI l'application en fournit un.
  -- Le jeton prouve que l'employé s'est réellement identifié sur l'appareil
  -- il y a peu. On ne connaît pas la forme exacte renvoyée par
  -- encheck_session_employe : si la lecture échoue, on NE BLOQUE PAS — les
  -- deux autres garde-fous (appartenance + fenêtre de 30 min) restent.
  IF p_jeton IS NOT NULL AND btrim(p_jeton) <> '' THEN
    BEGIN
      EXECUTE 'SELECT employee_id FROM public.encheck_session_employe($1) LIMIT 1'
        INTO v_employe_jeton USING p_jeton;
    EXCEPTION WHEN OTHERS THEN
      v_employe_jeton := NULL;
    END;

    IF v_employe_jeton IS NOT NULL AND v_employe_jeton <> p_employee_id THEN
      RETURN jsonb_build_object('ok', false, 'raison', 'jeton_invalide');
    END IF;
  END IF;

  IF now() - v_att.ct > c_fenetre THEN
    RETURN jsonb_build_object('ok', false, 'raison', 'delai_depasse',
                              'message', 'Le délai de correction est dépassé. Passez par un administrateur.');
  END IF;

  IF v_att.check_type = p_nouveau_type THEN
    RETURN jsonb_build_object('ok', true, 'inchange', true);
  END IF;

  INSERT INTO public.attendance_corrections
    (attendance_id, employee_id, enterprise_id, ancien_type, nouveau_type, origine)
  VALUES
    (v_att.id, v_att.employee_id, v_att.enterprise_id,
     v_att.check_type, p_nouveau_type, 'employe');

  UPDATE public.attendances
     SET check_type           = p_nouveau_type,
         origine              = 'corrige',
         modifie_par_employe  = true,
         modifie_le           = now()
   WHERE id = v_att.id;

  -- Jour civil du pointage, en heure du Bénin (même sécurité que plus haut).
  BEGIN
    v_jour := (v_att.ct AT TIME ZONE 'Africa/Porto-Novo')::date;
  EXCEPTION WHEN OTHERS THEN
    v_jour := (now() AT TIME ZONE 'Africa/Porto-Novo')::date;
  END;

  -- L'administrateur est prévenu. C'est un À-CÔTÉ : la correction est déjà
  -- enregistrée, l'échec de l'alerte ne doit donc rien annuler.
  BEGIN
    PERFORM public.encheck_alerte_poser(
      p_enterprise := v_att.enterprise_id,
      p_employee   := v_att.employee_id,
      p_jour       := v_jour,
      p_type       := 'correction_employe',
      p_gravite    := 'basse',
      p_titre      := 'Type de pointage corrigé par l''employé',
      p_detail     := 'Ancien type : ' || COALESCE(v_att.check_type, '?') ||
                      ' → nouveau type : ' || p_nouveau_type,
      p_ref        := v_att.id,
      p_appareil   := NULL
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Alerte de correction non envoyée (sans conséquence) : %', SQLERRM;
  END;

  RETURN jsonb_build_object('ok', true,
                            'ancien_type', v_att.check_type,
                            'nouveau_type', p_nouveau_type);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.encheck_corriger_type(uuid, uuid, text, text)
  TO anon, authenticated;
-- On garde aussi l'ancienne signature à trois arguments : si une version
-- plus ancienne de l'application l'appelle encore, elle continue de marcher.
GRANT EXECUTE ON FUNCTION public.encheck_corriger_type(uuid, uuid, text)
  TO anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
--  6. GARDE-FOU « DATE FUTURE » (fiche ARBITRAGE 2/3, P2)
-- ═══════════════════════════════════════════════════════════════════════════
--  Un pointage ne peut pas se trouver dans le futur. Un boîtier mal réglé,
--  une file hors-ligne corrompue ou une saisie erratique (le bouton « J+1 »
--  de l'admin) ne doivent jamais écrire « le pointage de demain » — qui sera
--  ensuite apparié et affiché comme une journée réelle (cas Hippo : une
--  sortie écrite au 17/10, 14 h de service inventées, fausses alertes).
--
--  Marge de dérive d'horloge : `garde_fou_futur_minutes` (défaut : 5 min),
--  lue dans `encheck_reglages_pointage` — source unique, comme le veut la
--  doctrine. Pour aligner sur la marge admin (10 min) :
--
--    INSERT INTO public.encheck_reglages_pointage (cle, valeur, commentaire)
--    VALUES ('garde_fou_futur_minutes', '10', 'Aligné sur trg_attendances_refuser_futur')
--    ON CONFLICT DO NOTHING;
--
--  DÉFENSE EN PROFONDEUR : ce trigger protège TOUTES les écritures dans
--  `attendances` (encheck_punch, corrections admin, imports…), pas seulement
--  l'application. L'admin a déjà le sien en INSERT (10 min) ; celui-ci couvre
--  aussi les UPDATE de check_time, avec la marge de la fiche.
--
--  Le point de contournement `SET encheck.test_rejeu = '1'` est réservé aux
--  harnais de test qui rejouent des scénarios avec dates fictives — jamais la
--  production (même convention que l'admin).

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

-- Le trigger s'exécute au moment de l'écriture : personne n'a besoin de
-- l'appeler soi-même. On retire donc les droits d'exécution directs.
REVOKE ALL ON FUNCTION public.encheck_punch_garde_fou_futur() FROM PUBLIC, anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
--  7. VÉRIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--  Ce SELECT doit renvoyer trois colonnes de plus qu'avant.

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'attendances'
ORDER BY ordinal_position;

--  Et celui-ci le résultat du cerveau pour le premier employé qui a pointé.
--  Remplace-le par un identifiant réel si tu veux tester un cas précis.

SELECT public.encheck_type_suggere(
  (SELECT employee_id FROM public.attendances
    ORDER BY check_time DESC LIMIT 1)
) AS suggestion;

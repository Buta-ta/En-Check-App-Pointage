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
  -- 'sortie_oubliee'  : une entrée vieille de plus du seuil
  -- 'presence_courte' : une sortie quelques minutes après l'entrée
  -- NULL              : rien à signaler

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
--   4. dernier = ENTRÉE, < 12 h           → SORTIE, confiance haute
--      (si la présence < 5 min            → SORTIE, confiance MOYENNE)
--   5. dernier = ENTRÉE, > 12 h           → ENTRÉE, confiance BASSE
--                                           + anomalie « sortie oubliée »
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
  -- ── LES RÉGLAGES (à adapter à tes règles d'entreprise) ──────────────────
  c_seuil_presence  constant interval := interval '12 hours';  -- au-delà, sortie oubliée
  c_presence_courte constant interval := interval '5 minutes'; -- sortie suspecte
  c_garde_fou       constant interval := interval '60 seconds';-- anti double-geste

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
  IF v_anciennete < c_garde_fou THEN
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

  ELSIF v_anciennete > c_seuil_presence THEN
    -- Règle 5 : la présence est anormalement longue.
    v_type := 'in'; v_confiance := 'basse';
    v_raison := 'presence_trop_longue'; v_anomalie := 'sortie_oubliee';

  ELSE
    -- Règle 4
    v_type := 'out'; v_raison := 'derniere_entree'; v_confiance := 'haute';
    v_anomalie := null;

    IF v_anciennete < c_presence_courte THEN
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
    'seuil_presence_heures', EXTRACT(EPOCH FROM c_seuil_presence) / 3600);
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
BEGIN
  UPDATE public.attendances
     SET origine         = COALESCE(p_origine, origine),
         decision_raison = COALESCE(p_raison, decision_raison),
         anomalie        = COALESCE(p_anomalie, anomalie)
   WHERE id = p_attendance_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'raison', 'pointage_introuvable');
  END IF;

  RETURN jsonb_build_object('ok', true);
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
  p_nouveau_type  text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_fenetre constant interval := interval '30 minutes';
  v_att     record;
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

  RETURN jsonb_build_object('ok', true,
                            'ancien_type', v_att.check_type,
                            'nouveau_type', p_nouveau_type);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.encheck_corriger_type(uuid, uuid, text)
  TO anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
--  6. VÉRIFICATION
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

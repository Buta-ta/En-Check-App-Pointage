-- ═══════════════════════════════════════════════════════════════════════════
--  VISIBILITÉ DES PAUSES — LE BANDEAU DE LA TABLETTE (encheck_pauses_en_cours)
--  Suite de la fiche « LOT D : PAUSES » — 17 octobre 2026
--  ⚠️ À COLLER DANS L'ÉDITEUR SQL DE SUPABASE (projet En-Check, le même que
--      la migration admin 20261016000004_pauses_intelligentes.sql).
-- ═══════════════════════════════════════════════════════════════════════════
--
--  POURQUOI CE FICHIER ?
--  ───────────────────────
--  Le bouton PAUSE est désormais sur l'écran principal de la tablette, avec
--  un bandeau qui montre QUI est en pause et DEPUIS QUAND :
--
--      ⏸ PAUSES EN COURS
--      ⏸ Koffi Jean — en pause depuis 12:05
--      ⏸ Awa Diallo — en pause depuis 12:15   🕒 Toujours en pause ?
--
--  Or la tablette se connecte avec le rôle `anon` (sans session), et les
--  lectures actuelles de `encheck_pauses` sont réservées aux admins
--  (`encheck_pauses_lire` est explicitement REFUSÉE à `anon`). Sans ce
--  fichier, le bandeau ne peut montrer que les pauses commencées sur cette
--  tablette (et masque les pauses d'ailleurs).
--
--  CE QUE FAIT CE FICHIER (LECTURE SEULEMENT) :
--   • crée une petite fonction `encheck_pauses_en_cours` qui renvoie la
--     liste des pauses OUVERTES d'une entreprise (nom, matricule, début) ;
--   • autorise la tablette (`anon`) à l'APPELER.
--
--  SÉCURITÉ : la fonction ne fait qu'une LECTURE — elle n'écit, ne modifie
--  et ne supprime rien. Elle ne renvoie que les pauses actuellement ouvertes
--  (pas d'historique). C'est exactement ce que le bandeau affiche déjà.
--  Même sans ce fichier, les 2 boutons de pause fonctionnent (ils écrivent
--  via `encheck_pause_ouvrir` / `encheck_pause_fermer`, déjà autorisés).
--
--  ⚙️ SI LA FONCTION CHANGE DE NOM CÔTÉ ADMIN : prévenez-moi, je m'adapte.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) La fonction de lecture du bandeau
CREATE OR REPLACE FUNCTION public.encheck_pauses_en_cours(p_enterprise uuid)
RETURNS TABLE (
  employe_id     uuid,
  prenom         text,
  nom            text,
  matricule      text,
  debut          timestamptz,
  motif          text,
  duree_minutes  integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p.employee_id,
         e.first_name::text,
         e.last_name::text,
         e.matricule::text,
         p.debut,
         p.motif,
         (extract(epoch FROM (now() - p.debut)) / 60)::int AS duree_minutes
    FROM public.encheck_pauses p
    JOIN public.employees e ON e.id = p.employee_id
   WHERE p.enterprise_id = p_enterprise
     AND p.fin IS NULL                       -- uniquement les pauses OUVERTES
     AND p.statut IN ('reelle', 'presumee')  -- jamais les pauses écartées
   ORDER BY p.debut;
$$;

-- 2) Les droits : la tablette peut LIRE (rôle anon), jamais écrire
REVOKE ALL ON FUNCTION public.encheck_pauses_en_cours(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.encheck_pauses_en_cours(uuid)
  TO anon, authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
--  VÉRIFICATION (optionnelle) — à coller juste après :
--    SELECT proname, prosecdef
--      FROM pg_proc
--     WHERE proname = 'encheck_pauses_en_cours';
--  → 1 ligne, prosecdef = true (t).
--
--  ET pour voir ce que la tablette verra :
--    SELECT * FROM public.encheck_pauses_en_cours(
--      (SELECT id FROM public.enterprises LIMIT 1)
--    );
-- ═══════════════════════════════════════════════════════════════════════════

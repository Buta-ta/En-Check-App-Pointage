-- ═══════════════════════════════════════════════════════════════════════════
--  CORRECTIF LOT D — « PAUSE PRÉVUE » LISIBLE PAR LA TABLETTE (encheck_pause_prevue)
--  Fiche « LES PAUSES » — 16 octobre 2026
--  ⚠️ À COLLER DANS L'ÉDITEUR SQL DE SUPABASE (projet En-Check) — le même
--      projet que la migration admin 20261016000004_pauses_intelligentes.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  POURQUOI CE CORRECTIF ?
--  ───────────────────────
--  La fonction `encheck_pause_prevue` (celle qui calcule le créneau
--  « Pause prévue 12:00–13:00 ») a été créée SANS droit pour la tablette :
--
--   1. elle n'est pas autorisée pour le rôle `anon` — or la tablette se
--      connecte SANS session (c'est comme ça qu'elle fonctionne même
--      hors-ligne) ;
--   2. elle lit les plannings avec les droits de QUI L'APPELLE — donc même
--      avec le droit d'exécution, elle verrait 0 ligne et répondrait
--      toujours « pas de pause prévue ».
--
--  Conséquence sans correctif : l'annonce « Pause prévue 12:00–13:00 » ne
--  s'affichait jamais. Les 2 boutons, eux, fonctionnaient déjà.
--
--  CE QUE FAIT CE CORRECTIF (lecture SEULEMENT, aucun droit d'écriture) :
--   • autorise la tablette (`anon`) à APPELER la fonction ;
--   • la fait lire les plannings avec les droits du propriétaire de la
--     fonction (« SECURITY DEFINER ») — elle ne peut toujours ni écrire ni
--     voir autre chose que le créneau demandé.
--
--  SÉCURITÉ : la fonction ne renvoie QUE un créneau d'horaire
--  (ex. « 12:00–13:00 »). Elle n'écrit nulle part. Le reste des règles
--  (« l'app n'écrit que par les 2 RPC ») est inchangé.
--
--  SANTÉ À VÉRIFIER : la fonction doit être (re)définie dans le schéma
--  `public`. Si la commande ci-dessous répond « function does not exist »,
--  c'est qu'elle a été créée dans un autre schéma : prévenez-moi et je
--  l'ajusterai.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) La tablette (rôle anon) a le droit d'APPELER la fonction
GRANT EXECUTE ON FUNCTION public.encheck_pause_prevue(uuid, uuid, date) TO anon;

-- 2) La fonction lit les plannings avec les droits de son propriétaire,
--    pas ceux de la tablette (sinon elle répond toujours « rien trouvé »)
ALTER FUNCTION public.encheck_pause_prevue(uuid, uuid, date) SECURITY DEFINER;

-- 3) Par principe : qui est authentifié peut l'appeler aussi
GRANT EXECUTE ON FUNCTION public.encheck_pause_prevue(uuid, uuid, date) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
--  VÉRIFICATION (optionnelle) — à coller juste après, pour confirmer :
--    SELECT proname, prosecdef
--      FROM pg_proc
--     WHERE proname = 'encheck_pause_prevue';
--  → doit renvoyer 1 ligne avec prosecdef = true (t = SECURITY DEFINER).
-- ═══════════════════════════════════════════════════════════════════════════

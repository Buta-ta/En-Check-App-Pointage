#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
#  VERCEL — IGNORER LES DÉPLOIEMENTS INUTILES (économie du plan gratuit)
# ═══════════════════════════════════════════════════════════════════
#
#  Règle Vercel (« Ignored Build Step ») : c'est INVERSÉ par rapport à
#  l'habitude Unix :
#
#      sortie 0  =  on SAUTE le build  (la copie n'est pas créée)
#      sortie 1  =  on CONSTRUIT normalement
#
#  Notre règle :
#    • branche autre que main  → on saute  (pas de copie « preview »)
#    • main, mais build/web inchangé → on saute  (ex. : le commit de
#      fusion qui n'apporte pas encore la nouvelle compilation)
#    • main, avec build/web qui change → on construit (c'est LE
#      déploiement utile : la nouvelle version compilée par GitHub Actions)
#
#  En cas de doute ou d'erreur, on construit TOUJOURS (sécurité :
#  mieux vaut une copie en trop qu'un site non mis à jour).
# ═══════════════════════════════════════════════════════════════════

if [ "$VERCEL_GIT_COMMIT_REF" != "main" ]; then
  exit 0
fi

# build/web identique au commit précédent → rien de nouveau à publier.
# (Si git échoue — clone incomplet, premier commit — on tombe en sortie 1
#  donc on construit : comportement par défaut sûr.)
if git diff --quiet HEAD^ HEAD -- build/web 2>/dev/null; then
  exit 0
fi

exit 1

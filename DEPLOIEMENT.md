# Déploiement et dépannage — En-Check Pointage

## Comment l'app arrive sur Vercel

`vercel.json` ne déclare aucune étape de construction :

```json
{ "version": 2, "builds": [], "outputDirectory": "build/web" }
```

Vercel sert donc **directement le dossier `build/web/` tel qu'il est commité**
dans le dépôt. Il ne lance pas `flutter build web` : `build/web/` contient une
application **déjà compilée**.

### La compilation est désormais automatique

Le fichier `.github/workflows/build-web.yml` fait le travail à votre place :

```
  vous poussez du code sur la branche main
              │
              ▼
  GitHub Actions installe Flutter et lance « flutter build web »
              │
              ▼
  le dossier build/web régénéré est enregistré dans main
              │
              ▼
  Vercel publie les nouveaux fichiers
```

Vous n'avez donc **plus rien à compiler ni à recopier à la main**.

| Ce que vous modifiez | Effet sur le site déployé |
|---|---|
| `web/index.html`, `web/styles.css`, `web/manifest.json` | **Automatique** (2 à 5 min) : `flutter build web` recopie ces fichiers dans `build/web/` |
| n'importe quel fichier `lib/*.dart` | **Automatique** (2 à 5 min) |
| `build/web/**` directement | ❌ À ne plus faire : écrasé au prochain build |

> ⚠️ **Ne modifiez plus jamais `build/web/` à la main.** Ce dossier est
> fabriqué par la machine ; toute retouche disparaît au passage suivant.
> Travaillez toujours dans `web/` et `lib/`.

### Pourquoi Vercel affiche deux déploiements

Après chaque push, Vercel publie **deux fois**, et c'est normal :

1. **Déploiement n° 1** — immédiatement après votre push. Il publie
   l'**ancien** `build/web`, car la compilation n'est pas terminée. Le site
   semble inchangé : c'est attendu, pas un échec.
2. **Déploiement n° 2** — quelques minutes plus tard, avec le message de
   commit « `build: régénère build/web après compilation automatique` ».
   **C'est celui-là qui compte.**

### Si le site ne change pas du tout

1. Onglet **Actions** de GitHub : une croix rouge signale une compilation
   ratée. Cliquez dessus, puis sur la étape fautive pour lire l'erreur.
2. Si tout est vert mais que rien ne bouge, c'est le **cache du navigateur** :
   l'application contient un `flutter_service_worker.js` qui garde l'ancienne
   version en mémoire. Faites **Ctrl+Maj+R**, ou ouvrez les outils de
   développement → onglet *Application* → *Service Workers* → **Unregister**,
   puis rechargez.

### Compiler à la main, en secours

Onglet **Actions** → *Compiler l'application web* → **Run workflow** → bouton
vert. Utile pour relancer une compilation sans rien pousser.

> **Note technique** : `.gitignore` contient `build/`, or `build/web/` doit
> être versionné puisque c'est lui que Vercel publie. L'Action utilise donc
> `git add -f build/web`, ce qui force Git à prendre le dossier malgré
> `.gitignore`. C'est ce qui évite le piège du fichier oublié (`styles.css`
> en avait été victime).

---

## Le 401 « permission denied for table enterprises »

### Symptôme

Saisie d'un code entreprise (`PHAR050`) → l'app affiche une erreur, et la
console montre :

```
GET /rest/v1/enterprises?select=*&code=eq.PHAR050&is_active=eq.true  401
PostgrestException(message: permission denied for table enterprises, code: 42501)
```

Côté Supabase, le journal indique `sql_state_code: 42501` et
`database_user: authenticator`.

### Cause

L'app de pointage n'est pas authentifiée : elle parle à Supabase avec la clé
publique, donc avec le rôle Postgres **`anon`**. PostgREST se connecte en
`authenticator` puis fait `SET ROLE anon` — c'est ce rôle qui se voit refuser
l'accès.

`42501 permission denied for table` est un **GRANT manquant**, pas un problème
de RLS. La distinction compte :

- RLS activée sans politique → la requête **réussit** et renvoie `[]`.
- GRANT manquant → la requête **échoue** avec 42501.

Ici c'est le second cas : `anon` n'a jamais reçu `SELECT` sur
`public.enterprises`.

L'espace admin (repo `En-Check`) ne rencontre pas l'erreur parce qu'il ne lit
pas la table en direct pour ce cas : `src/pages/PostePointage.jsx` passe par
`supabase.rpc('encheck_entreprise_par_code')`, et une fonction s'exécute avec
ses propres droits.

### Correctif

Exécuter `supabase/migrations/20261013000001_acces_anon_tables_pointage.sql`
dans **Dashboard Supabase → SQL Editor**. Le script est idempotent.

Il accorde, au rôle `anon` et au rôle `authenticated` :

- `USAGE` sur le schéma `public` ;
- `SELECT` sur `enterprises`, `employees_public`, `attendances`,
  `employee_schedules`, `work_schedules` (chaque objet absent est ignoré, pas
  une erreur) ;
- `EXECUTE` sur les onze fonctions RPC du parcours de pointage — les dix que
  `lib/services/` appelle (`supabase_service`, `trusted_punch_service`,
  `photo_service`, `geofencing_service` et leurs variantes web), plus
  `encheck_entreprise_par_code` utilisé par l'espace admin ;
- lecture et écriture sur les buckets `attendance-photos` et `face-enrollments`.

Il **n'active jamais RLS** : il n'ajoute une politique que si la table l'a déjà.
Activer RLS sur `enterprises` restreindrait aussi l'espace admin, qui doit
pouvoir lire les entreprises inactives.

Les deux dernières requêtes du script sont le test décisif : elles rejouent en
rôle `anon` la lecture que l'app effectue. Elles doivent renvoyer des lignes.

### Pourquoi le message disait « Erreur de connexion internet »

`lib/screens/welcome_screen.dart` attrapait toute exception et affichait ce
message unique. Un refus d'autorisation était donc présenté comme une panne
réseau. `SupabaseService.messageErreur()` distingue maintenant 42501, clé API
refusée, RLS et vraie coupure réseau ; `SyncService` n'annonce plus
« ✅ Données hors-ligne téléchargées avec succès » quand la requête a échoué.

> ℹ️ Ces changements Dart apparaissent sur le site après le passage de
> l'Action de compilation (2 à 5 min), sans intervention de votre part.

---

## Les erreurs de console qui accompagnaient le 401

Toutes venaient de `web/index.html` (et de sa copie `build/web/index.html`) :

| Erreur | Cause | Correctif |
|---|---|---|
| `/styles.css 404` | la page liait un fichier qui n'existait pas | `web/styles.css` créé — teinte de fond de l'app, plus de flash blanc |
| `ReferenceError: Supabase is not defined` | le bundle UMD `supabase-js` expose `supabase`, pas `Supabase` | bootstrap JS supprimé. Le client est construit côté Dart ; aucun code ne lisait `window.supabaseConfig` |
| `TypeError: Cannot read properties of null (reading 'appendChild')` | un injecteur dans `<head>` faisait `document.body.appendChild` avant que `<body>` existe | injecteur supprimé. `main.dart.js` n'est plus chargé qu'une fois — l'ancien fichier le chargeait deux fois |
| avertissement `apple-mobile-web-app-capable is deprecated` | clé iOS seule | `mobile-web-app-capable` ajouté à côté |
| icônes PWA 404 (silencieux) | `manifest.json` citait `icons/Icon-192.png`, les fichiers sont `icons/icon-192.png` — Vercel sert depuis Linux, la casse compte | chemins corrigés |
| « Installer l'application » jamais proposé | aucun `<link rel="manifest">` | lien ajouté |

Le `<script src="https://unpkg.com/@dart/debug@0.1.6/debug.js">` a aussi été
retiré : il ne sert qu'aux builds de débogage, et faisait dépendre chaque
chargement de page d'un CDN tiers.

---

## À vérifier côté Supabase, au-delà du correctif

`SyncService.telechargerDonneesPourHorsLigne()` télécharge **toutes** les
entreprises actives, puis **tous** les employés de chacune, à chaque démarrage
et à chaque synchronisation. Avec un GRANT en place, ce parcours s'exécutera
pour de vrai : le volume croît avec le nombre d'entreprises du projet, pas avec
celles de l'appareil. Un appareil configuré pour `PHAR050` n'a besoin que de
`PHAR050`. À revoir quand le parc d'entreprises grandira.

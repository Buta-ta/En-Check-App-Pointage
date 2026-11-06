# Publicités de l’accueil — rapport de travail Admin / API

**Date de l’audit : 6 novembre 2026**  
**Périmètre : application de pointage Android et PWA**  
**Statut : spécification à implémenter par l’équipe Admin/API ; aucune évolution de schéma ou de RPC n’est incluse dans la PR visuelle.**

## 1. Constat vérifiable

La fonctionnalité publicitaire n’existe pas encore dans le socle consulté :

- aucune table de campagnes ou de publicités ;
- aucune RPC fournissant des médias publicitaires pour l’accueil ;
- aucun champ `media_url`, type de média ou durée d’affichage associé à une entreprise ;
- aucun bucket Storage dédié à ces médias ;
- les tables `messages_systeme` et `notifications_envoyees` ne portent pas le couple entreprise + média + ordre + durée requis et ne doivent pas être détournées ;
- la RPC `encheck_entreprises_publiques` retourne uniquement le catalogue public des entreprises, sans publicités.

L’application possède déjà la photo par défaut `assets/scenes/scene_pointage.jpg`. Elle reste affichée immédiatement. La PR visuelle ne crée pas de fausse campagne et n’invente pas de nom de table ou de RPC.

## 2. Résultat attendu

L’en-tête doit fonctionner ainsi :

1. la photo locale apparaît sans attendre le réseau ;
2. l’application demande ensuite, en tâche de fond, les publicités actives de l’entreprise sélectionnée ;
3. zéro publicité : conserver la photo ;
4. une publicité : l’afficher sans minuterie de défilement ;
5. plusieurs publicités : respecter l’ordre et la durée de chaque média ;
6. le cadre ne change jamais de dimensions ; le bandeau culturel reste un élément séparé sous le média ;
7. le symbole et le titre En-Check, l’heure, la date et le bouton de thème restent au-dessus et utilisables ;
8. une erreur, un réseau lent ou une coupure ne produit jamais de zone vide et ne bloque jamais un pointage.

## 3. Travail Admin/API — modèle de données

Créer une table dédiée, dont le nom définitif sera validé par l’équipe. Le contrat doit contenir au minimum :

| Champ | Type conseillé | Règle |
|---|---|---|
| `id` | UUID | Identifiant stable du média |
| `enterprise_id` | UUID NOT NULL | FK vers `enterprises`, indexée ; ciblage obligatoire |
| `type_media` | enum/texte | `image` ou `video` uniquement |
| `media_path` | texte NOT NULL | Chemin Storage, pas de contenu binaire dans la table |
| `duree_affichage_ms` | entier NOT NULL | Durée positive, configurée individuellement dans l’Admin |
| `ordre_publication` | entier NOT NULL | Ordre explicite, modifiable dans l’Admin |
| `is_active` | booléen NOT NULL | Seules les lignes actives sont diffusées |
| `publie_le` | timestamptz | Date de publication et départage déterministe |
| `debute_le` | timestamptz NULL | Début de diffusion facultatif |
| `termine_le` | timestamptz NULL | Fin de diffusion facultative |
| `created_at` / `updated_at` | timestamptz | Audit et invalidation du cache |

Contraintes nécessaires :

- durée strictement positive, avec bornes raisonnables validées par le produit ;
- `termine_le > debute_le` quand les deux sont présents ;
- ordre unique et stable au sein d’une entreprise, ou départage obligatoire par `publie_le`, puis `id` ;
- suppression ou archivage d’un média sans casser les autres entrées ;
- aucune ligne sans entreprise ; aucune campagne « toutes entreprises » implicite sans décision produit distincte.

### Définition de « active »

La RPC doit appliquer côté serveur, avec l’heure du serveur :

```text
is_active = true
AND enterprise_id = entreprise demandée
AND (debute_le IS NULL OR debute_le <= maintenant)
AND (termine_le IS NULL OR termine_le > maintenant)
```

Tri recommandé : `ordre_publication ASC, publie_le ASC, id ASC`.

### Durée des vidéos

`duree_affichage_ms` doit représenter le temps de présence dans l’en-tête, y compris pour une vidéo. Recommandation pour lever l’ambiguïté : lecture automatique **muette**, boucle si la vidéo est plus courte que cette durée, puis transition à l’échéance configurée. Si l’équipe choisit un autre comportement, il doit être documenté avant le développement de l’application.

## 4. Travail Admin/API — Storage et optimisation

Créer un bucket dédié et des chemins compartimentés :

```text
{enterprise_id}/{publicite_id}/{nom_fichier_optimise}
```

Exigences :

- empêcher l’écriture côté application de pointage ;
- limiter l’upload aux administrateurs autorisés pour cette entreprise ;
- vérifier le MIME réel, l’extension et la taille côté serveur ;
- ne jamais réutiliser le chemin d’une autre entreprise ;
- produire les médias optimisés avant publication, pas au démarrage de l’application ;
- images JPEG/PNG/WebP correctement dimensionnées pour l’en-tête ;
- vidéos courtes, légères, lisibles sur Android et Chrome PWA, sans piste audio nécessaire ;
- si le bucket est privé, fournir des URL signées via la RPC ; les octets déjà mis en cache restent utilisables hors ligne jusqu’à expiration de la politique locale de cache ;
- si le bucket est public, confirmer que les campagnes ne contiennent aucune donnée confidentielle.

Les limites exactes de poids, résolution et durée vidéo doivent être fixées par le produit. À titre de point de départ à valider : image ≤ 500 Ko, vidéo ≤ 3 Mo et ≤ 15 secondes, largeur utile ≤ 1600 px.

## 5. Travail Admin/API — RPC de lecture

Fournir une RPC unique, par exemple `encheck_accueil_publicites(p_enterprise_id uuid)`. Le nom est une proposition, pas un objet créé par cette PR.

Réponse attendue :

```json
{
  "ok": true,
  "entreprise_id": "uuid-de-l-entreprise",
  "publicites": [
    {
      "id": "uuid-du-media",
      "type": "image",
      "url": "url-signee-ou-publique",
      "duree_affichage_ms": 6000,
      "ordre_publication": 1,
      "updated_at": "horodatage-du-media"
    }
  ]
}
```

La réponse peut contenir les **métadonnées** de toute la campagne active : cela n’autorise pas l’application à télécharger tous les fichiers. L’application ne charge que le média courant et, si possible, le suivant.

Sécurité obligatoire :

- filtre `enterprise_id` dans la RPC elle-même, jamais seulement dans le client ;
- RLS et politiques Storage testées avec deux entreprises ;
- aucune clé `service_role` dans l’application ;
- droits minimaux : lecture publique de la seule RPC prévue, pas de `SELECT` général sur la table ;
- `search_path` sûr pour une fonction `SECURITY DEFINER`, si ce mode est retenu ;
- erreur générique et sûre ; l’application retombe sur le cache ou la photo sans exposer de détail interne.

## 6. Travail dans En-Check Admin

Ajouter un écran de gestion permettant de :

1. choisir l’entreprise destinataire ;
2. importer une image ou une vidéo et voir son aperçu ;
3. définir `duree_affichage_ms` pour **chaque** média ;
4. définir ou réordonner `ordre_publication` ;
5. activer/désactiver et, si retenu, programmer les dates de diffusion ;
6. voir les règles de poids, format et durée avant publication ;
7. modifier ou retirer un média sans toucher aux autres entreprises ;
8. disposer d’un jeu de démonstration rattaché uniquement à une entreprise fictive de test.

L’Admin doit enregistrer la durée en même temps que le média. L’application ne doit pas deviner une durée depuis le nombre de fichiers ou utiliser une constante commune à toute la campagne.

## 7. Travail ultérieur dans l’application de pointage

Une fois le contrat ci-dessus disponible :

- lancer la récupération après le premier rendu, sans `await` bloquant l’accueil ;
- conserver un cadre de taille fixe et le bandeau culturel indépendant ;
- associer chaque réponse, minuterie et entrée de cache à l’ID de l’entreprise ;
- utiliser un jeton de génération pour ignorer une réponse tardive après changement d’entreprise ;
- annuler les minuteries et libérer les contrôleurs vidéo lors d’un changement de média ou d’entreprise ;
- ne télécharger que le courant et, au maximum, précharger le suivant ;
- mettre en cache les octets avec une politique LRU bornée et séparée par entreprise ;
- utiliser le cache hors ligne ; à défaut, afficher immédiatement la photo locale ;
- ne pas démarrer de minuterie avec zéro ou un seul média ;
- utiliser une simple transition en fondu, désactivée si le système demande moins d’animations ;
- vidéo muette, lecture non bloquante, contrôleur paresseux et libéré après usage ;
- conserver les commandes d’horloge, de thème et de pointage au-dessus du média ;
- ne faire aucune analyse de pixels et ne recolorer ni média ni logos.

Le choix d’un lecteur vidéo devra privilégier une solution standard et légère, chargée uniquement lorsqu’une vidéo existe. Aucun package lourd ne doit être ajouté au démarrage pour les entreprises sans publicité.

## 8. Recette contractuelle

| Cas | Résultat attendu |
|---|---|
| Aucune publicité | Photo actuelle, aucun appel vidéo, aucune zone vide |
| Une image active | Image fixe, aucune rotation, durée non utilisée pour créer un défilement |
| Plusieurs images, durées différentes | Ordre Admin exact et durée individuelle mesurée pour chaque image |
| Vidéo | Lecture muette, format léger, durée configurée respectée, aucun déplacement du cadre |
| Réseau lent | Photo ou cache immédiat ; chargement en fond sans bloquer l’accueil |
| Réseau indisponible | Dernier média valide en cache, sinon photo ; aucune erreur bloquante |
| Média courant en échec | Cache ou photo, puis campagne poursuivie sans écran blanc |
| Changement d’entreprise | Ancienne minuterie invalidée ; aucun média de l’ancienne entreprise affiché |
| Publicité inactive ou hors période | Exclue par la RPC |
| Deux entreprises avec campagnes différentes | Aucun mélange, y compris dans le cache et les réponses tardives |
| Pointage pendant une transition | Identification et validation inchangées, aucun overlay interceptant les gestes |
| Clair/sombre et changement de motif | Overlay lisible ; bandeau et accents mis à jour sans recharger la campagne |

Pour chaque cas, relever : premier frame, nombre de requêtes médias, absence d’erreurs JS/native, débordement de mise en page et capacité à effectuer un pointage. Comparer le premier frame à la version avec photo locale, sans campagne.

## 9. Livrables attendus de l’équipe Admin/API

- migration de schéma et rollback ;
- RPC de lecture et tests de sécurité inter-entreprises ;
- bucket, politiques Storage et validation d’upload ;
- écran Admin avec ordre et durée par média ;
- médias de test optimisés pour une entreprise fictive ;
- exemple de réponse RPC pour zéro, une et plusieurs publicités, dont une vidéo ;
- documentation de la politique de cache et de l’invalidation après modification.

Ces livrables sont les prérequis du branchement réel du carrousel dans l’application. La PR visuelle courante ne prétend pas couvrir cette recette publicitaire.

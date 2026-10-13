# en_check

A new Flutter project.

## Déploiement

L'app est servie par Vercel **sans étape de construction** : `vercel.json`
pointe directement sur le dossier commité `build/web/`. Modifier `web/` ou
`lib/` ne change rien au site tant que `flutter build web` n'a pas régénéré ce
dossier.

Les erreurs de déploiement déjà rencontrées, leur cause et leur correctif sont
documentées dans **[DEPLOIEMENT.md](DEPLOIEMENT.md)** — en particulier le
`401 permission denied for table enterprises` qui bloque la saisie du code
entreprise, et dont le correctif est un script SQL à exécuter côté Supabase.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

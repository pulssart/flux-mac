# Extension Chrome Flux

Cette extension Chrome ou Chromium analyse la page ouverte pour verifier si un flux RSS, Atom ou JSON Feed existe vraiment. Si oui, elle peut envoyer ce flux vers l'app macOS Flux via le lien `flux://add-feed?...`.

## Ce qu'elle fait

- inspecte la page ouverte et ses balises RSS declarees
- regarde aussi les liens RSS visibles dans la page
- telecharge la page courante et la page d'accueil pour verifier les indices cote serveur
- teste des chemins classiques comme `/feed`, `/rss.xml`, `/atom.xml` ou `/feeds/posts/default`
- valide chaque piste en lisant le contenu reel du lien avant de l'afficher comme "confirme"

## Installation locale

1. Ouvrez `chrome://extensions` dans Chrome ou Chromium.
2. Activez le `Mode developpeur`.
3. Cliquez sur `Charger l'extension non empaquetee`.
4. Selectionnez le dossier :

   `/Users/adriendonot/Documents/Projetcs/MacOS/Flux/Flux Mac/ChromeExtension`

## Utilisation

1. Ouvrez n'importe quel site web.
2. Cliquez sur l'extension `Flux RSS Detector`.
3. Attendez la fin du scan.
4. Si un flux est confirme, cliquez sur `Ajouter dans Flux`.

## Cote application macOS

Flux gere deja le schema `flux://`. Cette extension s'appuie dessus avec un nouveau format :

- `flux://add-feed?feed=<url_du_flux>&site=<url_du_site>`

L'app tente alors d'ajouter directement la source, ou ouvre sa feuille d'ajout si un probleme doit etre montre a l'utilisateur.

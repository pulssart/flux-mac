# Extension Safari Flux

Cette version Safari a ete generee a partir de l'extension Chrome et reutilise les memes fichiers pour garder le meme comportement.

## Projet a ouvrir

Ouvrir ce projet Xcode :

`/Users/adriendonot/Documents/Projetcs/MacOS/Flux/Flux Mac/FluxSafariExtension/Flux Safari/Flux Safari.xcodeproj`

## Ce qu'elle fait

- detecte les flux RSS, Atom et JSON Feed sur la page ouverte
- affiche les flux confirmes
- envoie le flux vers l'app Flux avec `flux://add-feed?...`

## Installation dans Safari

1. Ouvrir le projet dans Xcode.
2. Lancer le scheme `Flux Safari`.
3. L'app `Flux Safari` s'ouvre.
4. Cliquer sur le bouton qui ouvre les reglages des extensions Safari.
5. Activer `Flux Safari Extension` dans Safari.

## Important

- Cette extension Safari partage les fichiers de `/ChromeExtension`.
- Si vous modifiez `popup.js`, `popup.html`, `popup.css` ou `manifest.json`, Safari utilisera aussi ces changements.

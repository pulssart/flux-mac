# Flux — Landing page

Page d'atterrissage de **Flux**, le lecteur RSS natif pour Mac & iPad.
Site **100 % statique** : aucune étape de build, aucune dépendance. Juste du HTML, du CSS et un peu de JavaScript.

## Contenu du dossier

```
site/
├── index.html          Page (hero centré, FR/EN, toutes les sections)
├── styles.css          Styles
├── app.js              Bascule FR/EN, animations au scroll, barre collante
├── assets/
│   ├── flux-icon.png   Icône / favicon
│   ├── og.png          Image de partage social (1200×630)
│   └── shot-*.png      Captures de l'application
├── robots.txt
├── sitemap.xml
├── .nojekyll           Désactive le traitement Jekyll de GitHub Pages
└── .github/workflows/deploy.yml   Déploiement automatique (option B)
```

## Aperçu en local

Ouvrez simplement `index.html` dans un navigateur, ou servez le dossier :

```bash
cd site
python3 -m http.server 8080
# puis ouvrez http://localhost:8080
```

## Déploiement sur GitHub Pages

### Option A — branche `main`, le plus simple
1. Créez un dépôt GitHub et poussez le **contenu de ce dossier `site/`** à la racine du dépôt.
2. Dans le dépôt : **Settings → Pages**.
3. *Build and deployment* → **Source : Deploy from a branch**.
4. *Branch* : `main`, dossier `/ (root)` → **Save**.
5. La page sera en ligne sous une minute à l'adresse
   `https://<votre-utilisateur>.github.io/<nom-du-depot>/`.

> Le fichier `.nojekyll` est inclus : il évite que GitHub ignore certains fichiers.

### Option B — GitHub Actions (déploiement automatique à chaque push)
1. Poussez le contenu de `site/` à la racine du dépôt (le workflow est dans `.github/workflows/deploy.yml`).
2. **Settings → Pages → Source : GitHub Actions**.
3. Chaque `git push` sur `main` redéploie automatiquement.

## Domaine personnalisé

1. Ajoutez un fichier `CNAME` à la racine, contenant uniquement votre domaine :
   ```
   pulssart.github.io/flux-mac
   ```
2. Chez votre registrar, créez un enregistrement `CNAME` (ou les `A` records GitHub Pages pour un domaine apex).
3. **Settings → Pages → Custom domain** : renseignez le domaine et cochez **Enforce HTTPS**.

## À mettre à jour avant la mise en ligne

Recherchez `https://pulssart.github.io/flux-mac/` dans `index.html`, `robots.txt` et `sitemap.xml` et remplacez par votre URL réelle si besoin. Concerné :
- `<link rel="canonical">`
- les balises `og:url` et `og:image` / `twitter:image` (URL absolue de `assets/og.png`)
- `robots.txt` et `sitemap.xml`

## Personnalisation rapide

- **Couleur d'accent** : variable `--accent` (et `--accent-strong`) en haut de `styles.css`.
- **Police des titres** : variable `--title-family` (serif éditorial par défaut).
- **Textes FR / EN** : objet `I18N` dans `app.js`.
- **Lien App Store** : recherchez `id6752223666` dans `index.html`.

---

App : <https://apps.apple.com/fr/app/flux-smart-rss-reader/id6752223666>

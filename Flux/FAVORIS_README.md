# Système de Favoris - Flux

## Vue d'ensemble

Le système de favoris permet aux utilisateurs de sauvegarder des articles intéressants pour les consulter plus tard. Les articles favoris sont accessibles depuis une section dédiée dans la sidebar.

## Fonctionnalités

### 1. Section Favoris dans la Sidebar
- **Emplacement** : Section "Favoris" située sous "Mur de flux" dans la sidebar
- **Icône** : Cœur rouge (`heart.fill`)
- **Compteur** : Affiche le nombre d'articles favoris en temps réel
- **Navigation** : Cliquer sur "Mes favoris" affiche tous les articles favoris

### 2. Boutons Favori sur les Articles
- **ArticleHeroCard** : Bouton favori en haut à droite de la carte principale
- **ArticleGridCard** : Bouton favori dans la zone des métadonnées
- **États visuels** :
  - ❤️ (cœur vide) : Article non favori
  - ❤️ (cœur plein rouge) : Article en favori
- **Interaction** : Cliquer bascule l'état favori de l'article

### 3. Vue des Favoris
- **Filtrage** : Affiche uniquement les articles marqués comme favoris
- **Tri** : Articles triés par date de publication (plus récents en premier)
- **Header** : Titre "Mes favoris" avec icône cœur rouge
- **Messages** : 
  - "Aucun article en favori" quand la liste est vide
  - Compteur dynamique dans la sidebar

## Implémentation Technique

### Modèle de Données
- **Article.isSaved** : Propriété Booléenne existante pour marquer les favoris
- **FeedService.favoriteArticles** : Propriété calculée retournant tous les articles favoris
- **FeedService.favoriteArticlesCount** : Nombre d'articles favoris

### Méthodes du Service
```swift
// Bascule l'état favori d'un article
func toggleFavorite(for article: Article) async

// Retourne tous les articles favoris triés par date
var favoriteArticles: [Article]

// Retourne le nombre d'articles favoris
var favoriteArticlesCount: Int
```

### Navigation
- **Identifiant spécial** : `favoritesId` (UUID sentinelle)
- **Logique de sélection** : Gestion spéciale pour éviter le marquage automatique comme lu
- **Vue conditionnelle** : `ArticlesView(showOnlyFavorites: true)` pour les favoris

### Interface Utilisateur
- **Boutons favori** : Intégrés dans les composants ArticleHeroCard et ArticleGridCard
- **Tooltips** : "Ajouter aux favoris" / "Retirer des favoris"
- **Couleurs** : Rouge pour les favoris actifs, gris pour les inactifs
- **Animations** : Transitions fluides lors des changements d'état

## Utilisation

### Ajouter un Article aux Favoris
1. Cliquer sur le bouton cœur (❤️) sur n'importe quel article
2. L'article est automatiquement marqué comme favori
3. Le compteur dans la sidebar se met à jour

### Consulter ses Favoris
1. Cliquer sur "Mes favoris" dans la section Favoris de la sidebar
2. Tous les articles favoris s'affichent dans la vue principale
3. Les articles sont triés par date de publication

### Retirer un Article des Favoris
1. Cliquer sur le bouton cœur plein (❤️) sur l'article favori
2. L'article est automatiquement retiré des favoris
3. Le compteur dans la sidebar se met à jour

## Avantages

- **Persistance** : Les favoris sont sauvegardés dans la base de données SwiftData
- **Performance** : Filtrage et tri optimisés côté service
- **UX cohérente** : Interface similaire aux autres sections de l'app
- **Accessibilité** : Tooltips et icônes explicites
- **Réactivité** : Mise à jour en temps réel des compteurs et états

## Extensions Futures Possibles

- **Synchronisation** : Partage des favoris entre appareils
- **Organisation** : Dossiers de favoris par thème
- **Export** : Sauvegarde des favoris en format standard
- **Recherche** : Filtrage des favoris par mots-clés
- **Partage** : Envoi d'articles favoris par email/message

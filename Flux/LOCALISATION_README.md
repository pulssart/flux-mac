# Système de Localisation - Flux

## Vue d'ensemble

Le système de localisation permet aux utilisateurs de choisir la langue de l'interface utilisateur et d'influencer les fonctionnalités AI et TTS. La langue sélectionnée affecte tous les textes de l'interface, les phrases de chargement amusantes, et les paramètres de génération AI.

## Fonctionnalités

### 1. Langues Supportées
- **Français** 🇫🇷 (par défaut)
- **Anglais** 🇺🇸
- **Espagnol** 🇪🇸
- **Allemand** 🇩🇪
- **Italien** 🇮🇹
- **Portugais** 🇵🇹
- **Japonais** 🇯🇵
- **Chinois** 🇨🇳
- **Coréen** 🇰🇷
- **Russe** 🇷🇺

### 2. Interface Localisée
- **Sidebar** : Sections, boutons, tooltips
- **Articles** : Messages de chargement, boutons, tooltips
- **Réglages** : Titres, boutons, messages
- **Phrases de chargement** : Messages amusants localisés

### 3. Influence sur les Fonctionnalités
- **Accept-Language** : Headers HTTP pour les requêtes de flux
- **Voix TTS** : Sélection automatique de la voix appropriée
- **Génération AI** : Langue des prompts et réponses
- **Interface** : Tous les textes et messages

## Implémentation Technique

### Structure des Fichiers
```
Flux/
├── Localization.swift          # Gestionnaire de localisation
├── OpenAISettingsSheet.swift  # Modale des réglages avec sélection de langue
├── AppSidebar.swift           # Sidebar localisée
├── ArticlesView.swift         # Vue des articles localisée
└── FeedService.swift          # Service utilisant la langue sélectionnée
```

### Classes Principales

#### LocalizationManager
```swift
@Observable
class LocalizationManager {
    static let shared = LocalizationManager()
    
    var currentLanguage: SupportedLanguage
    var currentLocale: Locale
    
    func loadingPhrases() -> [String]
    func localizedString(_ key: LocalizationKey) -> String
}
```

#### SupportedLanguage
```swift
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case french = "fr"
    case english = "en"
    case spanish = "es"
    // ... autres langues
    
    var displayName: String
    var flag: String
    var locale: Locale
}
```

#### LocalizationKey
```swift
enum LocalizationKey {
    case today, newsWall, myFavorites, folders
    case youtube, myFeeds, addFeed, addFolder
    case aiSettings, cancel, save, loading
    // ... autres clés
}
```

### Persistance
- **UserDefaults** : Langue sélectionnée
- **SwiftData** : Paramètres dans le modèle Settings
- **NotificationCenter** : Changements de langue en temps réel

## Utilisation

### 1. Changer la Langue
1. Cliquer sur l'icône ⚙️ (Réglages IA)
2. Sélectionner la langue dans le menu déroulant
3. Cliquer sur "Enregistrer"
4. L'interface se met à jour immédiatement

### 2. Effets du Changement
- **Interface** : Tous les textes changent de langue
- **Phrases de chargement** : Messages amusants localisés
- **Headers HTTP** : Accept-Language mis à jour
- **Voix TTS** : Sélection automatique de la voix appropriée

### 3. Fallback
- **Langue système** : Utilisée par défaut si aucune langue n'est sélectionnée
- **Anglais** : Fallback pour les langues non encore traduites
- **Persistance** : La langue est sauvegardée entre les sessions

## Exemples de Localisation

### Phrases de Chargement
```swift
// Français
"Je compresse l'actualité…"
"Je briefe les derniers titres…"

// Anglais
"Compressing the news..."
"Briefing the latest headlines..."

// Espagnol
"Comprimiendo las noticias..."
"Resumiendo los últimos titulares..."
```

### Interface
```swift
// Français
"Aujourd'hui", "Mur de flux", "Mes favoris"

// Anglais
"Today", "News Wall", "My Favorites"

// Allemand
"Heute", "Nachrichtenwand", "Meine Favoriten"
```

## Extensions Futures

### 1. Nouvelles Langues
- **Arabe** 🇸🇦
- **Hindi** 🇮🇳
- **Néerlandais** 🇳🇱
- **Suédois** 🇸🇪
- **Norvégien** 🇳🇴

### 2. Fonctionnalités Avancées
- **Traduction automatique** des articles
- **Détection de langue** automatique
- **Préférences par flux** (langue spécifique)
- **Synchronisation** des préférences entre appareils

### 3. Personnalisation
- **Thèmes visuels** par langue
- **Formats de date** localisés
- **Monnaies** et unités de mesure
- **Raccourcis clavier** localisés

## Avantages

- **Expérience utilisateur** cohérente dans la langue native
- **Accessibilité** améliorée pour les utilisateurs internationaux
- **Intégration native** avec le système de réglages
- **Performance** optimisée (pas de requêtes de traduction)
- **Maintenance** simplifiée avec un système centralisé

## Support Technique

### Ajouter une Nouvelle Langue
1. Ajouter le cas dans `SupportedLanguage`
2. Implémenter les propriétés `displayName`, `flag`, `locale`
3. Ajouter les traductions dans `LocalizationKey`
4. Créer les phrases de chargement localisées

### Ajouter un Nouveau Texte
1. Ajouter la clé dans `LocalizationKey`
2. Implémenter les traductions pour toutes les langues
3. Utiliser `LocalizationManager.shared.localizedString(.key)`

Le système de localisation est maintenant entièrement fonctionnel et prêt à être étendu avec de nouvelles langues et fonctionnalités !

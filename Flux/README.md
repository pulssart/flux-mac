// Flux (macOS)
//
// Lecteur d’actualités et de contenus long format pour macOS, sans authentification, avec IA et TTS offline.
//
// Exigences
// - macOS 26+ (Tahoe)
// - Xcode 26 
// - Swift 6, SwiftUI, SwiftData
// - Accès réseau (entitlements)
//
// Lancer le projet
// 1. Cloner ce repo
// 2. Ouvrir `Flux.xcodeproj` avec Xcode 26
// 3. Compiler et lancer !
//
// Configuration IA
// Pas de clé API externe : l’IA utilise les modèles Apple du Mac (local).
// Tout reste sur l’appareil.
//
// Dépendances
// - FeedKit (RSS/Atom)
// - SwiftSoup (HTML scraping)
// - Nuke (images)
// - NaturalLanguage (langue)
// - SwiftData (persistance)
//
// Fonctionnalités majeures
// - Vue Aujourd’hui/Overview : meilleurs articles résumés
// - Abonnements RSS/Atom, tags, OPML, suggestions
// - Lecteur Articles : mode lecteur, IA résumé, TTS, favoris
// - TTS offline, mini-player barre de menus
// - Découverte et import/export OPML
// - 100% offline possible (hors suggestion/import/export)
// - Accessibilité, i18n (fr/en), logs structurés
//
// Tests
// - Lancer tests unitaires/UI depuis Xcode (Product > Test)
//
// Aucune authentification nécessaire
//
// © 2025 Adrien Donot / MIT

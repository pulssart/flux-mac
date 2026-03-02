const translations = {
  fr: {
    nav_home: "Accueil",
    nav_support: "Support",
    nav_privacy: "Confidentialité",
    hero_eyebrow: "Application macOS",
    hero_title: "Votre veille intelligente, sans friction.",
    hero_subtitle: "Flux rassemble vos sources, simplifie la lecture et génère des résumés locaux pour aller à l’essentiel.",
    hero_cta_download: "Télécharger sur le Mac App Store",
    hero_cta_support: "Obtenir de l’aide",
    shots_title: "Captures de l’application",
    shots_subtitle: "L’interface Flux sur macOS, en situation réelle.",
    shot_1_caption: "Lecture immersive avec panneau d’informations intelligent.",
    shot_2_caption: "Vue classique pour parcourir rapidement vos articles.",
    shot_3_caption: "Newsletter générée automatiquement à partir de vos sources.",
    shot_4_caption: "Découverte visuelle des contenus avec mise en avant des sujets.",
    shot_5_caption: "Résumé clair, source, tags et partage en un coup d’œil.",
    feat_title: "Pourquoi Flux",
    feat_1_title: "Lecture concentrée",
    feat_1_text: "Une interface claire qui met le contenu en avant, sans bruit.",
    feat_2_title: "Synthèse locale",
    feat_2_text: "Résumés et fonctions IA locales, pensées pour macOS.",
    feat_3_title: "Organisation simple",
    feat_3_text: "Dossiers, favoris, découverte et newsletter au même endroit.",
    footer_copy: "© Flux",
    support_eyebrow: "Centre d’aide",
    support_title: "Comment pouvons-nous vous aider ?",
    support_subtitle: "Retrouvez les réponses rapides, les étapes de dépannage et le contact support.",
    support_contact_cta: "Contacter le support",
    support_getting_started_title: "Démarrage rapide",
    support_step_1: "Ajoutez vos flux depuis la barre latérale.",
    support_step_2: "Classez vos sources dans des dossiers.",
    support_step_3: "Activez vos options de lecture dans les réglages.",
    support_contact_title: "Contact",
    support_contact_email_label: "Email :",
    support_contact_delay: "Délai de réponse habituel : 1 à 2 jours ouvrés.",
    support_faq_title: "Questions fréquentes",
    faq_1_q: "L’app ne charge pas certains articles.",
    faq_1_a: "Vérifiez votre connexion, puis rafraîchissez la source concernée. Si le problème persiste, contactez le support avec le nom du flux.",
    faq_2_q: "Comment importer ou exporter ma configuration ?",
    faq_2_a: "Ouvrez Réglages puis la section Configuration. Vous pouvez exporter, importer ou supprimer votre configuration depuis cet écran.",
    faq_3_q: "Comment changer la langue de l’interface ?",
    faq_3_a: "Dans Réglages, choisissez la langue dans le menu “Langue de l’interface”. Le changement est appliqué immédiatement."
  },
  en: {
    nav_home: "Home",
    nav_support: "Support",
    nav_privacy: "Privacy",
    hero_eyebrow: "macOS app",
    hero_title: "Smart monitoring, zero friction.",
    hero_subtitle: "Flux gathers your sources, simplifies reading, and creates local summaries so you can focus on what matters.",
    hero_cta_download: "Download on the Mac App Store",
    hero_cta_support: "Get support",
    shots_title: "App screenshots",
    shots_subtitle: "Flux on macOS in real usage.",
    shot_1_caption: "Immersive reading with an intelligent insight panel.",
    shot_2_caption: "Classic view to scan your articles quickly.",
    shot_3_caption: "Newsletter generated automatically from your sources.",
    shot_4_caption: "Visual discovery feed with highlighted topics.",
    shot_5_caption: "Clear summary, source, tags, and sharing at a glance.",
    feat_title: "Why Flux",
    feat_1_title: "Focused reading",
    feat_1_text: "A clean interface that keeps content first, without noise.",
    feat_2_title: "Local AI summaries",
    feat_2_text: "Local summaries and AI features, designed for macOS.",
    feat_3_title: "Simple organization",
    feat_3_text: "Folders, favorites, discovery, and newsletter in one place.",
    footer_copy: "© Flux",
    support_eyebrow: "Help center",
    support_title: "How can we help you?",
    support_subtitle: "Find quick answers, troubleshooting steps, and direct support contact.",
    support_contact_cta: "Contact support",
    support_getting_started_title: "Quick start",
    support_step_1: "Add your feeds from the sidebar.",
    support_step_2: "Organize your sources into folders.",
    support_step_3: "Enable reading options in settings.",
    support_contact_title: "Contact",
    support_contact_email_label: "Email:",
    support_contact_delay: "Typical response time: 1 to 2 business days.",
    support_faq_title: "Frequently asked questions",
    faq_1_q: "Some articles do not load.",
    faq_1_a: "Check your connection, then refresh the impacted source. If it continues, contact support with the feed name.",
    faq_2_q: "How can I import or export my configuration?",
    faq_2_a: "Open Settings, then go to Configuration. You can export, import, or delete your configuration from there.",
    faq_3_q: "How can I change the interface language?",
    faq_3_a: "In Settings, choose your language in “Interface language”. The change is applied immediately."
  }
};

function normalizeLang(input) {
  if (!input) return "fr";
  const lower = input.toLowerCase();
  if (lower.startsWith("en")) return "en";
  return "fr";
}

function getLangFromQuery() {
  const params = new URLSearchParams(window.location.search);
  return params.get("lang");
}

function updateLangInQuery(lang) {
  const url = new URL(window.location.href);
  url.searchParams.set("lang", lang);
  window.history.replaceState({}, "", url.toString());
}

function applyLanguage(lang) {
  const selected = translations[lang] ? lang : "fr";
  document.documentElement.lang = selected;
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const key = node.getAttribute("data-i18n");
    const value = translations[selected][key];
    if (value) node.textContent = value;
  });

  document.querySelectorAll(".lang-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.lang === selected);
  });

  localStorage.setItem("flux-site-lang", selected);
  updateLangInQuery(selected);
}

function initLanguage() {
  const fromQuery = getLangFromQuery();
  const fromStorage = localStorage.getItem("flux-site-lang");
  const fromBrowser = navigator.language;
  const startLang = normalizeLang(fromQuery || fromStorage || fromBrowser);
  applyLanguage(startLang);
}

document.addEventListener("DOMContentLoaded", () => {
  initLanguage();
  document.querySelectorAll(".lang-btn").forEach((btn) => {
    btn.addEventListener("click", () => applyLanguage(btn.dataset.lang));
  });
});

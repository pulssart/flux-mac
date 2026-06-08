/* ============================================================
   Flux Landing — i18n + interactions
   ============================================================ */

const I18N = {
  fr: {
    nav_features: "Fonctionnalités",
    nav_privacy: "Confidentialité",
    nav_faq: "FAQ",
    nav_download: "Télécharger",

    hero_pill_a: "Lecteur RSS pour",
    hero_pill_b: "Mac & iPad",
    hero_title: "Le calme retrouvé dans tout ce que vous lisez.",
    hero_lead: "Flux réunit vos sources RSS, blogs, newsletters et chaînes YouTube dans une seule app native. Locale, sans compte, sans algorithme qui décide à votre place.",
    cta_download: "Télécharger sur le Mac App Store",
    cta_discover: "Découvrir l’app",
    hero_n1: "Conçu pour macOS & iPadOS",
    hero_n2: "Synchronisé par iCloud",
    hero_n3: "100 % local",

    as_1: "Aucun compte requis",
    as_2: "Vos données restent sur l’appareil",
    as_3: "Sync Mac ↔ iPad via iCloud",
    as_4: "Pensé localement par les modèles d’Apple",

    wall_eyebrow: "Toutes vos sources",
    wall_title: "Un mur de flux, pas une timeline.",
    wall_lead: "Ajoutez un site, un flux ou une chaîne. Flux range tout dans un espace lisible où chaque source garde sa place — vous lisez ce que vous avez choisi, dans l’ordre que vous décidez.",
    wall_f1b: "Détection automatique des flux",
    wall_f1: "quand un site la permet, en un collage d’URL.",
    wall_f2b: "Dossiers, favoris, à lire plus tard",
    wall_f2: "sans empiler des vues qui ne servent à rien.",
    wall_f3b: "Une vraie hiérarchie visuelle,",
    wall_f3: "pas une soupe de cartes identiques.",

    today_tag: "Apple Intelligence · sur l’appareil",
    today_eyebrow: "Aujourd’hui",
    today_title: "Votre journée, mise au clair.",
    today_lead: "Chaque matin, Flux compose une vue d’ensemble de vos sources : l’essentiel, les tendances du moment, la météo. La mise en forme est assurée localement par les modèles d’Apple — rien ne part ailleurs.",
    today_f1b: "Le bruit filtré,",
    today_f1: "les doublons et la publicité écartés avant lecture.",
    today_f2b: "Une lecture orchestrée,",
    today_f2: "ordonnée par sujet plutôt que par horodatage.",

    signaux_eyebrow: "Signaux",
    signaux_title: "Ce que le monde anticipe, d’un coup d’œil.",
    signaux_lead: "Au-delà de vos flux, Signaux agrège les marchés prédictifs — politique, tech, finance, culture, sport. Des probabilités estimées en argent réel, filtrées et présentées sans tapage.",
    signaux_f1b: "Tendances en direct,",
    signaux_f1: "regroupées par thème et mises à jour en continu.",
    signaux_f2b: "À la une,",
    signaux_f2: "les événements les plus suivis du moment.",

    read_eyebrow: "Lecture",
    read_title: "Quand vous lisez, l’interface s’efface.",
    read_lead: "Vue immersive, contexte de l’article à portée, rythme posé. Le texte reste au centre, le reste passe en retrait — exactement comme une lecture devrait se présenter.",
    read_f1b: "Vue immersive",
    read_f1: "pour les articles, sans distraction autour.",
    read_f2b: "Contexte à portée :",
    read_f2: "personnes, entreprises et tags cités dans l’article.",

    nl_eyebrow: "Newsletter",
    nl_title: "Rattraper sans rouvrir vingt onglets.",
    nl_lead: "Flux assemble une synthèse à partir de vos propres sources, mise en page comme une vraie newsletter. À votre rythme, pour aller à l’essentiel quand le temps manque.",

    native_eyebrow: "Au quotidien",
    native_title: "Une app qui se comporte comme un outil, pas comme une vitrine.",
    native_lead: "Native sur Mac et iPad, pensée pour durer et pour rester discrète.",
    m1_t: "100 % natif",
    m1_p: "Construite avec SwiftUI pour macOS et iPadOS. Rapide, sobre, à sa place sur le système.",
    m2_t: "iCloud privé",
    m2_p: "Flux, dossiers et articles lus se synchronisent entre vos appareils via votre iCloud.",
    m3_t: "Local d’abord",
    m3_p: "Pas de compte, pas de serveur. Vos lectures vivent sur votre appareil.",
    m4_t: "Sans pistage",
    m4_p: "Aucune régie publicitaire, aucun profilage. Vous lisez, c’est tout.",

    privacy_eyebrow: "Local d’abord",
    privacy_title: "Vos lectures restent chez vous.",
    privacy_lead: "Pas de compte à créer, pas de profil à nourrir. Vos sources et vos articles vivent sur votre appareil et se synchronisent uniquement via votre iCloud privé. Flux n’intègre aucune régie publicitaire.",
    privacy_link: "Lire la politique de confidentialité",

    faq_eyebrow: "Questions fréquentes",
    faq_title: "Ce qu’on nous demande le plus souvent.",
    faq_1_q: "Sur quels appareils fonctionne Flux ?",
    faq_1_a: "Flux est une app native pour Mac (macOS) et iPad (iPadOS). Vos flux, dossiers et statuts de lecture se synchronisent automatiquement entre les deux via iCloud.",
    faq_2_q: "Que vient faire l’intelligence d’Apple ici ?",
    faq_2_a: "Flux s’appuie sur les modèles d’Apple, exécutés localement, pour filtrer le bruit, regrouper les sujets et composer la vue « Aujourd’hui » et les synthèses. Le traitement reste sur votre appareil — aucun contenu n’est envoyé ailleurs pour cela.",
    faq_3_q: "Mes données quittent-elles mon appareil ?",
    faq_3_a: "Non. Flux ne demande pas de compte. Vos données restent locales et ne transitent que par votre iCloud privé pour la synchronisation. Flux contacte uniquement les sites et flux que vous ajoutez, pour en récupérer le contenu.",
    faq_4_q: "Quels formats de sources sont pris en charge ?",
    faq_4_a: "RSS, Atom, blogs, newsletters et chaînes YouTube. Collez une URL : Flux détecte le flux quand le site le permet.",
    faq_5_q: "Flux est-il gratuit ?",
    faq_5_a: "Flux se télécharge sur le Mac App Store. Rendez-vous sur la fiche de l’app pour les détails de tarification et de version.",

    closing_eyebrow: "Commencer",
    closing_title: "Reprenez le fil, à votre rythme.",
    closing_n: "Sur le Mac App Store · Mac & iPad · 100 % local",

    footer_tagline: "Un web lisible, sur votre Mac.",
    footer_features: "Fonctionnalités",
    footer_privacy: "Confidentialité",
    footer_faq: "FAQ",
    footer_appstore: "Mac App Store",
    footer_copy: "© 2026 Flux. Conçu pour macOS & iPadOS."
  },

  en: {
    nav_features: "Features",
    nav_privacy: "Privacy",
    nav_faq: "FAQ",
    nav_download: "Download",

    hero_pill_a: "RSS reader for",
    hero_pill_b: "Mac & iPad",
    hero_title: "Calm, brought back to everything you read.",
    hero_lead: "Flux brings your RSS feeds, blogs, newsletters, and YouTube channels into one native app. Local, no account, no algorithm deciding for you.",
    cta_download: "Download on the Mac App Store",
    cta_discover: "Discover the app",
    hero_n1: "Built for macOS & iPadOS",
    hero_n2: "Synced over iCloud",
    hero_n3: "100% local",

    as_1: "No account required",
    as_2: "Your data stays on device",
    as_3: "Mac ↔ iPad sync via iCloud",
    as_4: "Shaped on-device by Apple’s models",

    wall_eyebrow: "All your sources",
    wall_title: "A wall of feeds, not a timeline.",
    wall_lead: "Add a site, a feed, or a channel. Flux keeps everything in a readable space where each source holds its place — you read what you chose, in the order you decide.",
    wall_f1b: "Automatic feed detection",
    wall_f1: "when a site allows it, from a pasted URL.",
    wall_f2b: "Folders, favorites, read later,",
    wall_f2: "without stacking views you never use.",
    wall_f3b: "Real visual hierarchy,",
    wall_f3: "not a soup of identical cards.",

    today_tag: "Apple Intelligence · on device",
    today_eyebrow: "Today",
    today_title: "Your day, made clear.",
    today_lead: "Every morning, Flux composes an overview of your sources: the essentials, current trends, the weather. The shaping runs locally on Apple’s models — nothing leaves your device.",
    today_f1b: "Noise filtered out,",
    today_f1: "duplicates and ads removed before you read.",
    today_f2b: "Reading, orchestrated:",
    today_f2: "grouped by topic rather than by timestamp.",

    signaux_eyebrow: "Signals",
    signaux_title: "What the world expects, at a glance.",
    signaux_lead: "Beyond your feeds, Signals aggregates prediction markets — politics, tech, finance, culture, sports. Probabilities estimated with real money, filtered and shown without the noise.",
    signaux_f1b: "Live trends,",
    signaux_f1: "grouped by theme and updated continuously.",
    signaux_f2b: "Front page:",
    signaux_f2: "the most-watched events right now.",

    read_eyebrow: "Reading",
    read_title: "When you read, the interface gets out of the way.",
    read_lead: "Immersive view, article context within reach, a calmer pace. The text stays at the center, everything else steps back — exactly how reading should feel.",
    read_f1b: "Immersive view",
    read_f1: "for articles, with no clutter around them.",
    read_f2b: "Context within reach:",
    read_f2: "people, companies, and tags cited in the article.",

    nl_eyebrow: "Newsletter",
    nl_title: "Catch up without reopening twenty tabs.",
    nl_lead: "Flux builds a recap from your own sources, laid out like a real newsletter. At your own pace, to get to the essentials when time is short.",

    native_eyebrow: "Day to day",
    native_title: "An app that behaves like a tool, not a storefront.",
    native_lead: "Native on Mac and iPad, built to last and to stay out of your way.",
    m1_t: "Fully native",
    m1_p: "Built with SwiftUI for macOS and iPadOS. Fast, quiet, at home on the system.",
    m2_t: "Private iCloud",
    m2_p: "Feeds, folders, and read status sync across your devices through your iCloud.",
    m3_t: "Local first",
    m3_p: "No account, no server. Your reading lives on your device.",
    m4_t: "No tracking",
    m4_p: "No ad networks, no profiling. You just read.",

    privacy_eyebrow: "Local first",
    privacy_title: "Your reading stays yours.",
    privacy_lead: "No account to create, no profile to feed. Your sources and articles live on your device and sync only through your private iCloud. Flux includes no ad network.",
    privacy_link: "Read the privacy policy",

    faq_eyebrow: "FAQ",
    faq_title: "What we get asked most.",
    faq_1_q: "Which devices does Flux run on?",
    faq_1_a: "Flux is a native app for Mac (macOS) and iPad (iPadOS). Your feeds, folders, and read status sync automatically between both over iCloud.",
    faq_2_q: "What does Apple’s intelligence do here?",
    faq_2_a: "Flux relies on Apple’s models, run locally, to filter noise, group topics, and compose the “Today” view and recaps. The processing stays on your device — no content is sent elsewhere for it.",
    faq_3_q: "Does my data leave my device?",
    faq_3_a: "No. Flux requires no account. Your data stays local and only moves through your private iCloud for syncing. Flux contacts only the sites and feeds you add, to fetch their content.",
    faq_4_q: "Which source formats are supported?",
    faq_4_a: "RSS, Atom, blogs, newsletters, and YouTube channels. Paste a URL: Flux detects the feed when the site allows it.",
    faq_5_q: "Is Flux free?",
    faq_5_a: "Flux downloads from the Mac App Store. Check the app’s listing for pricing and version details.",

    closing_eyebrow: "Get started",
    closing_title: "Pick the thread back up, at your own pace.",
    closing_n: "On the Mac App Store · Mac & iPad · 100% local",

    footer_tagline: "A readable web, on your Mac.",
    footer_features: "Features",
    footer_privacy: "Privacy",
    footer_faq: "FAQ",
    footer_appstore: "Mac App Store",
    footer_copy: "© 2026 Flux. Built for macOS & iPadOS."
  }
};

function normalizeLang(input) {
  if (!input) return "fr";
  return String(input).toLowerCase().startsWith("en") ? "en" : "fr";
}

function applyLanguage(lang) {
  const sel = I18N[lang] ? lang : "fr";
  document.documentElement.lang = sel;
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const key = node.getAttribute("data-i18n");
    const val = I18N[sel][key];
    if (val != null) node.textContent = val;
  });
  document.querySelectorAll(".lang-btn").forEach((b) =>
    b.classList.toggle("active", b.dataset.lang === sel)
  );
  try {
    localStorage.setItem("flux-lang", sel);
    const url = new URL(window.location.href);
    url.searchParams.set("lang", sel);
    window.history.replaceState({}, "", url.toString());
  } catch (e) {}
}

function initLanguage() {
  let fromQuery = null;
  try { fromQuery = new URLSearchParams(window.location.search).get("lang"); } catch (e) {}
  let fromStore = null;
  try { fromStore = localStorage.getItem("flux-lang"); } catch (e) {}
  applyLanguage(normalizeLang(fromQuery || fromStore || navigator.language));
}

function setupReveal() {
  const nodes = Array.from(document.querySelectorAll("[data-reveal]"));
  if (!nodes.length) return;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const h = () => window.innerHeight || document.documentElement.clientHeight;

  // Arme uniquement ce qui est sous la ligne de flottaison ; le reste reste visible.
  const armed = [];
  nodes.forEach((n) => {
    if (!reduce && n.getBoundingClientRect().top >= h() * 0.92) {
      n.classList.add("reveal-armed");
      armed.push(n);
    }
  });
  if (!armed.length) return;

  let pending = armed.slice();
  const check = () => {
    const vh = h();
    pending = pending.filter((n) => {
      if (n.getBoundingClientRect().top < vh * 0.92) {
        n.classList.add("is-visible");
        return false;
      }
      return true;
    });
    if (!pending.length) {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    }
  };
  let ticking = false;
  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(() => { ticking = false; check(); });
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll);
  check();
  // Filet de sécurité : si une transition reste bloquée, on retire l'état "armé"
  // (affichage instantané, sans dépendre d'une animation).
  setTimeout(() => armed.forEach((n) => n.classList.remove("reveal-armed")), 3000);
}

function setupStickyBar() {
  const bar = document.querySelector(".topbar");
  if (!bar) return;
  const onScroll = () => bar.classList.toggle("is-stuck", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
}

document.documentElement.classList.add("js-ready");
document.addEventListener("DOMContentLoaded", () => {
  initLanguage();
  setupReveal();
  setupStickyBar();
  document.querySelectorAll(".lang-btn").forEach((b) =>
    b.addEventListener("click", () => applyLanguage(b.dataset.lang))
  );
});

const COMMON_FEED_PATHS = [
  'feed',
  'feed/',
  'rss',
  'rss/',
  'rss.xml',
  'feed.xml',
  'atom.xml',
  'index.xml',
  'feeds/posts/default',
  'feeds/rss',
  'feeds/all.atom.xml',
  'feed.json'
];

const CONFIDENCE_LABELS = {
  high: 'High',
  medium: 'Medium',
  low: 'Low'
};

const extensionAPI = globalThis.browser ?? globalThis.chrome;

const browserName = detectBrowserName();

const ui = {
  eyebrowLabel: document.getElementById('eyebrow-label'),
  pageCard: document.getElementById('page-card'),
  pageTitle: document.getElementById('page-title'),
  pageURL: document.getElementById('page-url'),
  loadingCard: document.getElementById('loading-card'),
  loadingCopy: document.getElementById('loading-copy'),
  errorCard: document.getElementById('error-card'),
  errorCopy: document.getElementById('error-copy'),
  emptyCard: document.getElementById('empty-card'),
  emptyCopy: document.getElementById('empty-copy'),
  noticeCard: document.getElementById('notice-card'),
  noticeCopy: document.getElementById('notice-copy'),
  resultsSection: document.getElementById('results-section'),
  resultsTitle: document.getElementById('results-title'),
  resultsMeta: document.getElementById('results-meta'),
  resultsList: document.getElementById('results-list'),
  rescanButton: document.getElementById('rescan-button')
};

const runtimeState = {
  activeTabId: null,
  pageURL: null
};

ui.eyebrowLabel.textContent = `Flux for ${browserName}`;

ui.rescanButton.addEventListener('click', () => {
  void runScan();
});

void runScan();

async function runScan() {
  resetUI();
  setLoading('Reading tab...');
  runtimeState.activeTabId = null;
  runtimeState.pageURL = null;

  try {
    const [tab] = await extensionAPI.tabs.query({ active: true, currentWindow: true });
    const pageURL = toWebURL(tab?.url);

    if (!tab || !pageURL) {
      showUnsupportedPage(tab?.url);
      return;
    }

    runtimeState.activeTabId = tab.id ?? null;
    runtimeState.pageURL = pageURL.href;

    renderPage(tab.title || pageURL.hostname, pageURL.href);

    setLoading('Checking page...');
    const pageSnapshot = await inspectPage(tab.id);

    const discovery = await discoverFeeds(pageURL, pageSnapshot);

    if (discovery.results.length === 0) {
      showNoResult(discovery);
      return;
    }

    renderResults(discovery, pageURL);
  } catch (error) {
    showError(error instanceof Error ? error.message : 'Unknown error.');
  } finally {
    ui.loadingCard.classList.add('hidden');
  }
}

function resetUI() {
  ui.loadingCard.classList.remove('hidden');
  ui.errorCard.classList.add('hidden');
  ui.emptyCard.classList.add('hidden');
  ui.noticeCard.classList.add('hidden');
  ui.resultsSection.classList.add('hidden');
  ui.resultsList.innerHTML = '';
}

function detectBrowserName() {
  const userAgent = navigator.userAgent || '';

  if (/Safari\//i.test(userAgent) && !/Chrome\//i.test(userAgent) && !/Chromium\//i.test(userAgent)) {
    return 'Safari';
  }

  if (/Edg\//i.test(userAgent)) {
    return 'Edge';
  }

  return 'Chrome';
}

function renderPage(title, url) {
  ui.pageCard.classList.remove('hidden');
  ui.pageTitle.textContent = title;
  ui.pageURL.textContent = url;
}

function setLoading(message) {
  ui.loadingCard.classList.remove('hidden');
  ui.loadingCopy.textContent = message;
}

function showError(message) {
  ui.errorCard.classList.remove('hidden');
  ui.errorCopy.textContent = message;
}

function showUnsupportedPage(rawURL) {
  showError(
    rawURL
      ? 'Only http:// and https:// pages are supported.'
      : 'No supported web page found.'
  );
}

function showNoResult(discovery) {
  ui.emptyCard.classList.remove('hidden');
  ui.emptyCopy.textContent = `Checked ${discovery.testedCandidates} candidates. No confirmed feed found.`;

  ui.noticeCard.classList.remove('hidden');
  ui.noticeCopy.textContent = 'You can still paste the site URL into Flux.';
}

function renderResults(discovery, pageURL) {
  ui.resultsSection.classList.remove('hidden');
  ui.resultsTitle.textContent =
    discovery.results.length === 1 ? '1 feed found' : `${discovery.results.length} feeds found`;
  ui.resultsMeta.textContent = `${discovery.testedCandidates} checked, ${discovery.validatedCandidates} confirmed`;

  const fragment = document.createDocumentFragment();

  for (const result of discovery.results) {
    fragment.appendChild(buildResultCard(result, pageURL));
  }

  ui.resultsList.replaceChildren(fragment);

  ui.noticeCard.classList.remove('hidden');
  ui.noticeCopy.textContent = 'If Flux does not open, launch it once and try again.';
}

function buildResultCard(result, pageURL) {
  const wrapper = document.createElement('article');
  wrapper.className = 'result-card';

  const header = document.createElement('div');
  header.className = 'result-header';

  const textColumn = document.createElement('div');
  const title = document.createElement('div');
  title.className = 'result-title';
  title.textContent = result.title;

  const urlText = document.createElement('p');
  urlText.className = 'result-url muted';
  urlText.textContent = result.feedURL;

  textColumn.append(title, urlText);

  const host = document.createElement('div');
  host.className = 'muted';
  host.textContent = new URL(result.feedURL).hostname;

  header.append(textColumn, host);

  const badgeRow = document.createElement('div');
  badgeRow.className = 'badge-row';
  badgeRow.append(
    createBadge(result.kind.toUpperCase(), `kind-${result.kind}`),
    createBadge(CONFIDENCE_LABELS[result.confidenceLevel], `confidence-${result.confidenceLevel}`)
  );

  const actions = document.createElement('div');
  actions.className = 'result-actions';

  const addButton = document.createElement('button');
  addButton.className = 'primary-button';
  addButton.type = 'button';
  addButton.textContent = 'Add to Flux';
  addButton.addEventListener('click', () => {
    addButton.disabled = true;
    openFlux(result, pageURL);
    setTimeout(() => {
      addButton.disabled = false;
    }, 1200);
  });

  const openLink = document.createElement('button');
  openLink.className = 'secondary-button';
  openLink.type = 'button';
  openLink.textContent = 'Open feed';
  openLink.addEventListener('click', async () => {
    await extensionAPI.tabs.create({ url: result.feedURL });
  });

  actions.append(addButton, openLink);
  wrapper.append(header, badgeRow, actions);
  return wrapper;
}

function createBadge(text, extraClass = '') {
  const badge = document.createElement('span');
  badge.className = ['badge', extraClass].filter(Boolean).join(' ');
  badge.textContent = text;
  return badge;
}

async function inspectPage(tabId) {
  if (!tabId) {
    return emptyPageSnapshot();
  }

  try {
    const [injectionResult] = await extensionAPI.scripting.executeScript({
      target: { tabId },
      func: () => {
        const FEED_TYPE_HINTS = [
          'application/rss+xml',
          'application/atom+xml',
          'application/feed+json',
          'application/json'
        ];

        function toAbsoluteURL(raw) {
          try {
            return new URL(raw, document.baseURI).href;
          } catch {
            return null;
          }
        }

        function extractAlternateLinks(root) {
          return Array.from(root.querySelectorAll('link[href]'))
            .map((link) => {
              const rel = (link.getAttribute('rel') || '').toLowerCase();
              const type = (link.getAttribute('type') || '').toLowerCase();
              const href = toAbsoluteURL(link.getAttribute('href') || '');
              if (!href) {
                return null;
              }

              const relParts = rel.split(/\s+/).filter(Boolean);
              const looksLikeFeed =
                relParts.includes('alternate') ||
                FEED_TYPE_HINTS.some((hint) => type.includes(hint)) ||
                href.includes('/feed') ||
                href.includes('/rss');

              if (!looksLikeFeed) {
                return null;
              }

              return {
                href,
                rel,
                type,
                title: (link.getAttribute('title') || '').trim()
              };
            })
            .filter(Boolean);
        }

        function extractAnchorHints(root) {
          return Array.from(root.querySelectorAll('a[href]'))
            .map((anchor) => {
              const href = toAbsoluteURL(anchor.getAttribute('href') || '');
              if (!href) {
                return null;
              }

              const text = [
                anchor.textContent || '',
                anchor.getAttribute('aria-label') || '',
                anchor.getAttribute('title') || ''
              ]
                .join(' ')
                .trim();

              const haystack = `${href} ${text}`.toLowerCase();
              const looksRelevant =
                /rss|atom|json feed|feedburner|syndication/.test(haystack) ||
                href.endsWith('.xml') ||
                href.includes('/feed') ||
                href.includes('/rss') ||
                href.includes('feeds/posts/default');

              if (!looksRelevant) {
                return null;
              }

              return {
                href,
                text: text.slice(0, 160)
              };
            })
            .filter(Boolean)
            .slice(0, 18);
        }

        const rootName = (document.documentElement?.nodeName || '').toLowerCase();
        const contentType = (document.contentType || '').toLowerCase();
        const pageLooksLikeFeed =
          rootName === 'rss' ||
          rootName === 'feed' ||
          rootName === 'rdf:rdf' ||
          contentType.includes('rss') ||
          contentType.includes('atom+xml') ||
          contentType.includes('feed+json');

        return {
          pageLooksLikeFeed,
          pageTitle: document.title || '',
          contentType,
          rootName,
          alternateLinks: extractAlternateLinks(document),
          anchorHints: extractAnchorHints(document)
        };
      }
    });

    return injectionResult?.result || emptyPageSnapshot();
  } catch {
    return emptyPageSnapshot();
  }
}

function emptyPageSnapshot() {
  return {
    pageLooksLikeFeed: false,
    pageTitle: '',
    contentType: '',
    rootName: '',
    alternateLinks: [],
    anchorHints: []
  };
}

async function discoverFeeds(pageURL, pageSnapshot) {
  const candidateMap = new Map();

  if (pageSnapshot.pageLooksLikeFeed || looksLikeFeedURL(pageURL)) {
    addCandidate(candidateMap, pageURL.href, {
      score: 120,
      kindHint: sniffKindFromURL(pageURL.href),
      reason: 'La page elle-meme ressemble a un flux',
      titleHint: pageSnapshot.pageTitle
    });
  }

  addLinksAsCandidates(candidateMap, pageSnapshot.alternateLinks, 110, 'Balise RSS detectee dans la page');
  addAnchorsAsCandidates(candidateMap, pageSnapshot.anchorHints, 82, 'Lien RSS visible dans la page');

  setLoading('Checking site...');

  const currentPageHints = await fetchDocumentHints(pageURL);
  addLinksAsCandidates(candidateMap, currentPageHints.alternateLinks, 106, 'Balise RSS detectee dans le HTML du site');
  addAnchorsAsCandidates(candidateMap, currentPageHints.anchorHints, 76, 'Lien RSS detecte dans le HTML du site');
  if (currentPageHints.pageLooksLikeFeed) {
    addCandidate(candidateMap, currentPageHints.finalURL || pageURL.href, {
      score: 118,
      kindHint: currentPageHints.directKind,
      reason: 'La reponse du site est deja un flux',
      titleHint: currentPageHints.pageTitle
    });
  }

  const homeURL = new URL(pageURL.origin);
  if (homeURL.href !== pageURL.href) {
    const homePageHints = await fetchDocumentHints(homeURL);
    addLinksAsCandidates(candidateMap, homePageHints.alternateLinks, 103, 'Balise RSS detectee sur la page d\'accueil');
    addAnchorsAsCandidates(candidateMap, homePageHints.anchorHints, 72, 'Lien RSS detecte sur la page d\'accueil');
    if (homePageHints.pageLooksLikeFeed) {
      addCandidate(candidateMap, homePageHints.finalURL || homeURL.href, {
        score: 115,
        kindHint: homePageHints.directKind,
        reason: 'La page d\'accueil repond deja avec un flux',
        titleHint: homePageHints.pageTitle
      });
    }
  }

  for (const baseURL of buildSearchBases(pageURL)) {
    for (const path of COMMON_FEED_PATHS) {
      addCandidate(candidateMap, new URL(path, baseURL).href, {
        score: baseURL.pathname === '/' ? 62 : 58,
        kindHint: sniffKindFromURL(path),
        reason: `Chemin RSS classique teste (${path})`
      });
    }
  }

  setLoading('Validating feeds...');

  const orderedCandidates = Array.from(candidateMap.values())
    .sort((left, right) => right.score - left.score)
    .slice(0, 28);

  const validated = await validateCandidates(orderedCandidates, pageURL);

  return {
    testedCandidates: orderedCandidates.length,
    validatedCandidates: validated.length,
    results: validated
  };
}

function addLinksAsCandidates(candidateMap, links, score, reason) {
  for (const link of links) {
    addCandidate(candidateMap, link.href, {
      score,
      kindHint: sniffKindFromType(link.type) || sniffKindFromURL(link.href),
      reason,
      titleHint: link.title
    });
  }
}

function addAnchorsAsCandidates(candidateMap, links, score, reason) {
  for (const link of links) {
    addCandidate(candidateMap, link.href, {
      score,
      kindHint: sniffKindFromURL(link.href),
      reason,
      titleHint: link.text
    });
  }
}

function addCandidate(candidateMap, rawURL, metadata) {
  const normalized = normalizeURL(rawURL);
  if (!normalized) {
    return;
  }

  const existing = candidateMap.get(normalized);
  if (existing) {
    existing.score = Math.max(existing.score, metadata.score);
    if (metadata.kindHint && !existing.kindHint) {
      existing.kindHint = metadata.kindHint;
    }
    if (metadata.titleHint && !existing.titleHint) {
      existing.titleHint = metadata.titleHint;
    }
    if (!existing.reasons.includes(metadata.reason)) {
      existing.reasons.push(metadata.reason);
    }
    return;
  }

  candidateMap.set(normalized, {
    url: normalized,
    score: metadata.score,
    kindHint: metadata.kindHint || null,
    titleHint: metadata.titleHint || '',
    reasons: [metadata.reason]
  });
}

async function fetchDocumentHints(pageURL) {
  try {
    const response = await fetch(pageURL.href, {
      redirect: 'follow',
      cache: 'no-store',
      credentials: 'omit'
    });

    const finalURL = toWebURL(response.url) || pageURL;
    const contentType = (response.headers.get('content-type') || '').toLowerCase();
    const text = await response.text();
    const sniffed = sniffFeed(text, contentType);

    if (sniffed.isFeed) {
      const metadata = extractFeedMetadata(text, sniffed.kind, finalURL.href);
      return {
        finalURL: finalURL.href,
        pageLooksLikeFeed: true,
        directKind: sniffed.kind,
        pageTitle: metadata.title,
        alternateLinks: [],
        anchorHints: []
      };
    }

    if (!looksLikeHTML(text, contentType)) {
      return {
        finalURL: finalURL.href,
        pageLooksLikeFeed: false,
        directKind: null,
        pageTitle: '',
        alternateLinks: [],
        anchorHints: []
      };
    }

    const doc = new DOMParser().parseFromString(text, 'text/html');
    const effectiveBase = resolveBaseURL(doc, finalURL.href);

    return {
      finalURL: finalURL.href,
      pageLooksLikeFeed: false,
      directKind: null,
      pageTitle: doc.title || '',
      alternateLinks: extractAlternateLinksFromDocument(doc, effectiveBase),
      anchorHints: extractAnchorHintsFromDocument(doc, effectiveBase)
    };
  } catch {
    return {
      finalURL: pageURL.href,
      pageLooksLikeFeed: false,
      directKind: null,
      pageTitle: '',
      alternateLinks: [],
      anchorHints: []
    };
  }
}

function extractAlternateLinksFromDocument(doc, baseURL) {
  return Array.from(doc.querySelectorAll('link[href]'))
    .map((link) => {
      const rel = (link.getAttribute('rel') || '').toLowerCase();
      const type = (link.getAttribute('type') || '').toLowerCase();
      const href = absolutize(link.getAttribute('href') || '', baseURL);
      if (!href) {
        return null;
      }

      const relParts = rel.split(/\s+/).filter(Boolean);
      const looksRelevant =
        relParts.includes('alternate') ||
        type.includes('rss') ||
        type.includes('atom') ||
        type.includes('feed+json') ||
        href.includes('/feed') ||
        href.includes('/rss');

      if (!looksRelevant) {
        return null;
      }

      return {
        href,
        rel,
        type,
        title: (link.getAttribute('title') || '').trim()
      };
    })
    .filter(Boolean);
}

function extractAnchorHintsFromDocument(doc, baseURL) {
  return Array.from(doc.querySelectorAll('a[href]'))
    .map((anchor) => {
      const href = absolutize(anchor.getAttribute('href') || '', baseURL);
      if (!href) {
        return null;
      }

      const text = [
        anchor.textContent || '',
        anchor.getAttribute('aria-label') || '',
        anchor.getAttribute('title') || ''
      ]
        .join(' ')
        .trim();

      const haystack = `${href} ${text}`.toLowerCase();
      const looksRelevant =
        /rss|atom|json feed|feedburner|syndication/.test(haystack) ||
        href.endsWith('.xml') ||
        href.includes('/feed') ||
        href.includes('/rss') ||
        href.includes('feeds/posts/default');

      if (!looksRelevant) {
        return null;
      }

      return {
        href,
        text: text.slice(0, 160)
      };
    })
    .filter(Boolean)
    .slice(0, 18);
}

function buildSearchBases(pageURL) {
  const bases = [new URL(pageURL.origin + '/')];
  const segments = pageURL.pathname.split('/').filter(Boolean);
  if (segments.length === 0) {
    return bases;
  }

  const localePattern = /^[a-z]{2}(?:-[a-z]{2})?$/i;

  if (localePattern.test(segments[0])) {
    bases.push(new URL(`/${segments[0]}/`, pageURL.origin));
    if (segments[1]) {
      bases.push(new URL(`/${segments[0]}/${segments[1]}/`, pageURL.origin));
    }
  } else {
    bases.push(new URL(`/${segments[0]}/`, pageURL.origin));
  }

  return dedupeURLs(bases);
}

async function validateCandidates(candidates, pageURL) {
  const validated = [];

  for (const candidate of candidates) {
    const result = await validateSingleCandidate(candidate, pageURL);
    if (result) {
      validated.push(result);
    }
  }

  const deduped = new Map();
  for (const item of validated) {
    const key = normalizeURL(item.feedURL);
    if (!key) {
      continue;
    }

    const existing = deduped.get(key);
    if (!existing || existing.confidenceScore < item.confidenceScore) {
      deduped.set(key, item);
    }
  }

  return Array.from(deduped.values()).sort(compareResults);
}

async function validateSingleCandidate(candidate, pageURL) {
  try {
    const response = await fetch(candidate.url, {
      redirect: 'follow',
      cache: 'no-store',
      credentials: 'omit'
    });

    if (!response.ok) {
      return null;
    }

    const finalURL = normalizeURL(response.url);
    if (!finalURL) {
      return null;
    }

    const contentType = (response.headers.get('content-type') || '').toLowerCase();
    const text = await response.text();
    const sniffed = sniffFeed(text, contentType);

    if (!sniffed.isFeed) {
      return null;
    }

    const metadata = extractFeedMetadata(text, sniffed.kind, finalURL);
    const confidenceScore = Math.min(
      100,
      candidate.score +
        (candidate.kindHint && candidate.kindHint === sniffed.kind ? 8 : 0) +
        (metadata.title ? 4 : 0)
    );

    return {
      feedURL: finalURL,
      siteURL: metadata.siteURL || pageURL.origin,
      title: metadata.title || candidate.titleHint || prettifyHost(new URL(finalURL).hostname),
      kind: sniffed.kind,
      reasons: dedupeStrings(candidate.reasons),
      confidenceLevel: confidenceScore >= 92 ? 'high' : confidenceScore >= 75 ? 'medium' : 'low',
      confidenceScore
    };
  } catch {
    return null;
  }
}

function compareResults(left, right) {
  if (right.confidenceScore !== left.confidenceScore) {
    return right.confidenceScore - left.confidenceScore;
  }

  const kindRank = { rss: 0, atom: 1, json: 2 };
  return (kindRank[left.kind] ?? 9) - (kindRank[right.kind] ?? 9);
}

function sniffFeed(text, contentType) {
  const head = text.slice(0, 8000).trimStart().toLowerCase();

  if (contentType.includes('application/rss+xml') || head.includes('<rss')) {
    return { isFeed: true, kind: 'rss' };
  }

  if (
    contentType.includes('application/atom+xml') ||
    (head.includes('<feed') && head.includes('http://www.w3.org/2005/atom'))
  ) {
    return { isFeed: true, kind: 'atom' };
  }

  if (
    head.includes('<rdf:rdf') ||
    head.includes('purl.org/rss/1.0')
  ) {
    return { isFeed: true, kind: 'rss' };
  }

  if (contentType.includes('feed+json') || contentType.includes('application/json')) {
    const jsonKind = sniffJSONFeed(text);
    if (jsonKind) {
      return { isFeed: true, kind: 'json' };
    }
  }

  if (sniffJSONFeed(text)) {
    return { isFeed: true, kind: 'json' };
  }

  return { isFeed: false, kind: null };
}

function sniffJSONFeed(text) {
  try {
    const json = JSON.parse(text);
    return Boolean(
      typeof json === 'object' &&
        json &&
        (
          (typeof json.version === 'string' && json.version.includes('jsonfeed.org/version')) ||
          (typeof json.title === 'string' && Array.isArray(json.items))
        )
    );
  } catch {
    return false;
  }
}

function extractFeedMetadata(text, kind, baseURL) {
  if (kind === 'json') {
    try {
      const json = JSON.parse(text);
      return {
        title: typeof json.title === 'string' ? json.title.trim() : '',
        siteURL:
          typeof json.home_page_url === 'string'
            ? absolutize(json.home_page_url, baseURL)
            : typeof json.homePageURL === 'string'
              ? absolutize(json.homePageURL, baseURL)
              : ''
      };
    } catch {
      return { title: '', siteURL: '' };
    }
  }

  const xml = new DOMParser().parseFromString(text, 'application/xml');
  if (xml.querySelector('parsererror')) {
    return {
      title: regexCapture(text, /<title>([^<]+)<\/title>/i),
      siteURL: regexCapture(text, /<link>(https?:\/\/[^<]+)<\/link>/i)
    };
  }

  if (kind === 'atom') {
    const title = xml.querySelector('feed > title')?.textContent?.trim() || '';
    const alternateLink = Array.from(xml.querySelectorAll('feed > link[href]')).find((link) => {
      const rel = (link.getAttribute('rel') || '').toLowerCase();
      return !rel || rel === 'alternate';
    });

    return {
      title,
      siteURL: absolutize(alternateLink?.getAttribute('href') || '', baseURL)
    };
  }

  const channel = xml.querySelector('channel');
  const title = channel?.querySelector('title')?.textContent?.trim() || '';
  const linkText = channel?.querySelector('link')?.textContent?.trim() || '';
  return {
    title,
    siteURL: absolutize(linkText, baseURL)
  };
}

function openFlux(result, pageURL) {
  const params = new URLSearchParams();
  params.set('feed', result.feedURL);
  params.set('site', result.siteURL || pageURL.href);
  params.set('title', result.title);
  params.set('source', 'chrome-extension');

  const deepLink = `flux://add-feed?${params.toString()}`;

  if (runtimeState.activeTabId) {
    void openFluxFromActiveTab(runtimeState.activeTabId, deepLink);
  } else {
    openFluxFromPopup(deepLink);
  }

  ui.noticeCard.classList.remove('hidden');
  ui.noticeCopy.textContent = 'Request sent to Flux.';
}

async function openFluxFromActiveTab(tabId, deepLink) {
  try {
    await extensionAPI.scripting.executeScript({
      target: { tabId },
      func: (url) => {
        const previousFrame = document.getElementById('flux-extension-deeplink-frame');
        if (previousFrame) {
          previousFrame.remove();
        }

        const iframe = document.createElement('iframe');
        iframe.id = 'flux-extension-deeplink-frame';
        iframe.style.display = 'none';
        iframe.src = url;
        document.documentElement.appendChild(iframe);

        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.style.display = 'none';
        document.documentElement.appendChild(anchor);
        anchor.click();

        setTimeout(() => {
          iframe.remove();
          anchor.remove();
        }, 1500);
      },
      args: [deepLink]
    });
  } catch {
    openFluxFromPopup(deepLink);
  }
}

function openFluxFromPopup(deepLink) {
  const anchor = document.createElement('a');
  anchor.href = deepLink;
  anchor.style.display = 'none';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
}

function toWebURL(rawURL) {
  if (!rawURL) {
    return null;
  }

  try {
    const url = new URL(rawURL);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return null;
    }
    return url;
  } catch {
    return null;
  }
}

function normalizeURL(rawURL) {
  const parsed = toWebURL(rawURL);
  if (!parsed) {
    return null;
  }

  parsed.hash = '';
  parsed.protocol = 'https:';

  let normalized = parsed.toString();
  while (normalized.endsWith('/') && normalized.length > 'https://a'.length) {
    normalized = normalized.slice(0, -1);
  }
  return normalized;
}

function looksLikeFeedURL(url) {
  const value = typeof url === 'string' ? url.toLowerCase() : url.href.toLowerCase();
  return (
    value.endsWith('.xml') ||
    value.endsWith('.rss') ||
    value.endsWith('/feed') ||
    value.endsWith('/feed/') ||
    value.endsWith('/rss') ||
    value.endsWith('/rss/') ||
    value.includes('feeds/posts/default')
  );
}

function sniffKindFromType(type) {
  const value = (type || '').toLowerCase();
  if (value.includes('rss')) {
    return 'rss';
  }
  if (value.includes('atom')) {
    return 'atom';
  }
  if (value.includes('feed+json') || value.includes('application/json')) {
    return 'json';
  }
  return null;
}

function sniffKindFromURL(rawURL) {
  const value = (rawURL || '').toLowerCase();
  if (value.includes('atom')) {
    return 'atom';
  }
  if (value.includes('json')) {
    return 'json';
  }
  if (value.includes('rss') || value.includes('feed') || value.endsWith('.xml')) {
    return 'rss';
  }
  return null;
}

function resolveBaseURL(doc, fallbackURL) {
  const baseHref = doc.querySelector('base[href]')?.getAttribute('href') || '';
  return absolutize(baseHref, fallbackURL) || fallbackURL;
}

function absolutize(rawURL, baseURL) {
  if (!rawURL) {
    return '';
  }

  try {
    const url = new URL(rawURL, baseURL);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return '';
    }
    return url.href;
  } catch {
    return '';
  }
}

function looksLikeHTML(text, contentType) {
  if (contentType.includes('text/html')) {
    return true;
  }
  const start = text.slice(0, 600).toLowerCase();
  return start.includes('<html') || start.includes('<!doctype html');
}

function regexCapture(text, pattern) {
  const match = pattern.exec(text);
  return match?.[1]?.trim() || '';
}

function dedupeURLs(urls) {
  const seen = new Set();
  const result = [];

  for (const url of urls) {
    const normalized = normalizeURL(url.href);
    if (!normalized || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    result.push(new URL(normalized));
  }

  return result;
}

function dedupeStrings(values) {
  return Array.from(new Set(values.filter(Boolean)));
}

function prettifyHost(hostname) {
  return hostname
    .replace(/^www\./i, '')
    .split('.')
    .slice(0, -1)
    .join(' ')
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

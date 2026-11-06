/*
 * Capture la PWA Flutter compilée, sans aucun compte ni serveur réel.
 * Usage : node capture_accueil.js <build/web> <dossier-sortie>
 * Le serveur local doit écouter sur http://127.0.0.1:8080/.
 */
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const BUILD = path.resolve(process.argv[2] || 'build/web');
const OUT = path.resolve(process.argv[3] || 'apercu-accueil');
const BASE = process.env.APERCU_BASE_URL || 'http://127.0.0.1:8080/';
const CHROME = process.env.CHROME_PATH ||
  ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser']
    .find((p) => fs.existsSync(p));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const LIMIT = Number(process.env.APERCU_LIMIT || 0);

const SCENARIOS_ACCUEIL = [
  { nom: 'reference-412x869-clair', w: 412, h: 869, dpr: 2, mobile: true },
  { nom: 'reference-412x869-sombre', w: 412, h: 869, dpr: 2, mobile: true, sombre: true },
  { nom: 'telephone-360x640-clair', w: 360, h: 640, dpr: 2, mobile: true },
  { nom: 'telephone-360x640-sombre', w: 360, h: 640, dpr: 2, mobile: true, sombre: true },
  { nom: 'telephone-390x844-clair', w: 390, h: 844, dpr: 3, mobile: true },
  { nom: 'accueil-sans-autres-modes-360x640', w: 360, h: 640, dpr: 2, mobile: true, sansAutresModes: true },
  { nom: 'pause-360x640-clair', w: 360, h: 640, dpr: 2, mobile: true, ouvrirPause: true },
  { nom: 'pause-412x869-clair', w: 412, h: 869, dpr: 2, mobile: true, ouvrirPause: true },
  { nom: 'pause-412x869-sombre', w: 412, h: 869, dpr: 2, mobile: true, sombre: true, ouvrirPause: true },
  { nom: 'ma-journee-360x640-clair', w: 360, h: 640, dpr: 2, mobile: true, ouvrirMaJournee: true },
  { nom: 'ma-journee-412x869-clair', w: 412, h: 869, dpr: 2, mobile: true, ouvrirMaJournee: true },
  { nom: 'tablette-800x1280-clair', w: 800, h: 1280, dpr: 2, tablette: true },
  { nom: 'tablette-800x1280-sombre', w: 800, h: 1280, dpr: 2, tablette: true, sombre: true },
  { nom: 'portable-1366x768-clair', w: 1366, h: 768, dpr: 1 },
  { nom: 'portable-1366x768-sombre', w: 1366, h: 768, dpr: 1, sombre: true },
  { nom: 'ordinateur-1920x962-clair', w: 1920, h: 962, dpr: 1 },
  { nom: 'motif-raphia-clair', w: 412, h: 869, dpr: 2, mobile: true, motif: 'raphia' },
  { nom: 'motif-raphia-sombre', w: 412, h: 869, dpr: 2, mobile: true, motif: 'raphia', sombre: true },
  { nom: 'motif-bogolan-clair', w: 412, h: 869, dpr: 2, mobile: true, motif: 'bogolan' },
  { nom: 'motif-bogolan-sombre', w: 412, h: 869, dpr: 2, mobile: true, motif: 'bogolan', sombre: true },
  { nom: 'motif-zoulou-clair', w: 412, h: 869, dpr: 2, mobile: true, motif: 'zoulou' },
  { nom: 'motif-zoulou-sombre', w: 412, h: 869, dpr: 2, mobile: true, motif: 'zoulou', sombre: true },
  { nom: 'checklist-incomplete-360x640', w: 360, h: 640, dpr: 2, mobile: true, checklistIncomplete: true },
  { nom: 'parametres-checklist-360x640', w: 360, h: 640, dpr: 2, mobile: true, checklistIncomplete: true, ouvrirParametres: true },
];
const SCENARIOS_HISTORIQUE = [
  { nom: 'historique-360x640-clair', w: 360, h: 640, dpr: 2, mobile: true },
  { nom: 'historique-412x869-clair', w: 412, h: 869, dpr: 2, mobile: true },
  { nom: 'historique-calendrier-360x640-clair', w: 360, h: 640, dpr: 2, mobile: true, ouvrirCalendrier: true },
];
const SCENARIOS = process.env.APERCU_MODE === 'historique'
  ? SCENARIOS_HISTORIQUE
  : SCENARIOS_ACCUEIL;

function typeContenu(fichier) {
  if (fichier.endsWith('.wasm')) return 'application/wasm';
  if (fichier.endsWith('.js')) return 'application/javascript';
  if (fichier.endsWith('.json')) return 'application/json';
  return 'application/octet-stream';
}

async function ouvrir(browser, scenario) {
  const page = await browser.newPage();
  const uaMobile = 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  const uaTablette = 'Mozilla/5.0 (Linux; Android 14; Tablet) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  if (scenario.mobile) await page.setUserAgent(uaMobile);
  if (scenario.tablette) await page.setUserAgent(uaTablette);
  await page.setViewport({
    width: scenario.w,
    height: scenario.h,
    deviceScaleFactor: scenario.dpr,
    isMobile: !!scenario.mobile,
    hasTouch: !!(scenario.mobile || scenario.tablette),
  });
  await page.setExtraHTTPHeaders({ 'Accept-Language': 'fr-FR,fr;q=0.9' });
  await page.setRequestInterception(true);
  const externes = [];
  page.on('request', (req) => {
    const url = req.url();
    if (url.startsWith(BASE) || url.startsWith('data:') || url.startsWith('blob:')) {
      return req.continue();
    }
    // Le SDK est déjà compilé dans build/web/canvaskit : on sert cette copie
    // locale au lieu du CDN, pour des captures reproductibles et hors réseau.
    if (url.includes('/flutter-canvaskit/')) {
      const parties = new URL(url).pathname.split('/');
      const relatif = parties.slice(3).join('/').split('?')[0];
      const fichier = path.join(BUILD, 'canvaskit', relatif);
      if (fs.existsSync(fichier)) {
        return req.respond({
          status: 200,
          contentType: typeContenu(fichier),
          body: fs.readFileSync(fichier),
        });
      }
    }
    externes.push(url.slice(0, 140));
    return req.abort('internetdisconnected');
  });
  const erreurs = [];
  page.on('pageerror', (e) => erreurs.push(String(e).slice(0, 400)));
  await page.evaluateOnNewDocument((s) => {
    try {
      Object.defineProperty(navigator, 'language', { get: () => 'fr-FR' });
      Object.defineProperty(navigator, 'languages', { get: () => ['fr-FR', 'fr'] });
    } catch (_) {}
    const S = (k, v) => localStorage.setItem('flutter.' + k, JSON.stringify(v));
    // Entreprise entièrement fictive : aucune donnée de l'équipe ou du fondateur.
    S('enterprise_id', '11111111-2222-3333-4444-555555555555');
    S('enterprise_name', 'EN-NOUS');
    S('matricule_prefix', 'ENN');
    S('enterprise_pays', 'CG');
    S('apparence_sombre_v2', !!s.sombre);
    S('tutoriel_vue_v1', true);
    S('checklist_motif_choisi', !s.checklistIncomplete);
    S('checklist_premier_pointage', !s.checklistIncomplete);
    S('module_qr_scanner', !s.sansAutresModes); // variante sans « Autres modes »
    S('motif_culturel_id', s.motif || 'adinkra');
    window.__firstFrame = null;
    window.addEventListener('flutter-first-frame', () => {
      window.__firstFrame = performance.now();
    });
    const original = window.requestAnimationFrame.bind(window);
    window.__raf = 0;
    window.requestAnimationFrame = (cb) => original((t) => {
      window.__raf += 1;
      cb(t);
    });
  }, scenario);
  const debut = Date.now();
  try {
    await page.goto(BASE, { waitUntil: 'load', timeout: 60000 });
  } catch (e) {
    throw new Error(`Chargement PWA: ${e}; requêtes bloquées: ${externes.join(', ')}`);
  }
  let premierFrameMs = null;
  try {
    await page.waitForFunction(() => window.__firstFrame !== null, { timeout: 30000 });
    premierFrameMs = await page.evaluate(() => Math.round(window.__firstFrame));
  } catch (e) {
    // On capture quand même : l'image doit montrer ce qui bloque, et le
    // rapport reste exploitable au lieu d'attendre deux minutes par taille.
    erreurs.push(`Premier frame Flutter non reçu: ${String(e).slice(0, 220)}`);
  }

  // Attendre la fin de l'animation unique et le chargement des images/fontes.
  let calme = false;
  let precedent = -1;
  let stable = 0;
  for (let i = 0; i < 20 && !calme; i += 1) {
    const raf = await page.evaluate(() => window.__raf);
    stable = raf === precedent ? stable + 1 : 0;
    precedent = raf;
    calme = stable >= 4;
    if (!calme) await sleep(400);
  }
  if (scenario.ouvrirParametres) {
    await page.mouse.click(scenario.w * 0.875, scenario.h - 32);
    await sleep(1200);
  }
  if (scenario.ouvrirCalendrier) {
    await page.mouse.click(scenario.w - 28, 28);
    await sleep(500);
  }
  if (scenario.ouvrirMaJournee) {
    // Onglet Historique de la navigation basse : la modale s'ouvre sans
    // envoyer de matricule/PIN ni toucher au flux de consultation.
    await page.mouse.click(scenario.w * 0.625, scenario.h - 32);
    await sleep(900);
    calme = false;
    stable = 0;
    precedent = -1;
    for (let i = 0; i < 20 && !calme; i += 1) {
      const raf = await page.evaluate(() => window.__raf);
      stable = raf === precedent ? stable + 1 : 0;
      precedent = raf;
      calme = stable >= 4;
      if (!calme) await sleep(400);
    }
  }
  if (scenario.ouvrirPause) {
    // Le vrai onglet « Pause » de la navigation basse (2e de 4).
    await page.mouse.click(scenario.w * 0.375, scenario.h - 32);
    await page.mouse.move(0, 0); // ne pas capturer un survol sur « Retour »
    await sleep(1400);
    calme = false;
    stable = 0;
    precedent = -1;
    for (let i = 0; i < 20 && !calme; i += 1) {
      const raf = await page.evaluate(() => window.__raf);
      stable = raf === precedent ? stable + 1 : 0;
      precedent = raf;
      calme = stable >= 4;
      if (!calme) await sleep(400);
    }
  }
  const mesure = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    documentWidth: document.documentElement.scrollWidth,
    documentHeight: document.documentElement.scrollHeight,
    bodyWidth: document.body ? document.body.scrollWidth : 0,
    bodyHeight: document.body ? document.body.scrollHeight : 0,
  }));
  return { page, premierFrameMs, attenteMs: Date.now() - debut, calme, externes, erreurs, mesure };
}

(async () => {
  if (!CHROME) throw new Error('Chrome introuvable (définir CHROME_PATH).');
  fs.mkdirSync(OUT, { recursive: true });
  const mesuresExistantes = path.join(OUT, 'mesures.json');
  const resultats = process.env.APERCU_MODE === 'historique' && fs.existsSync(mesuresExistantes)
    ? JSON.parse(fs.readFileSync(mesuresExistantes, 'utf8'))
    : [];
  const ARGS_COMPLET = [

      '--ash-no-nudges', '--disable-domain-reliability', '--disable-print-preview',
      '--disk-cache-size=33554432', '--no-default-browser-check', '--no-pings',
      '--font-render-hinting=none',
      '--disable-features=AudioServiceOutOfProcess,IsolateOrigins,site-per-process',
      '--enable-features=SharedArrayBuffer', '--ignore-gpu-blocklist',
      '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
      '--allow-running-insecure-content', '--disable-setuid-sandbox',
      '--disable-site-isolation-trials', '--disable-web-security', '--no-sandbox',
      '--disable-dev-shm-usage', '--lang=fr-FR',
      ];
  const ARGS_STANDARD = [

      '--no-sandbox', '--disable-dev-shm-usage', '--use-gl=angle',
      '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist', '--font-render-hinting=none',
      '--disable-web-security', '--allow-running-insecure-content',
      '--enable-features=SharedArrayBuffer', '--lang=fr-FR',
      ];
  let browser;
  let derniereErreur;
  const configurations = [ARGS_COMPLET, ARGS_STANDARD];
  for (let i = 0; i < configurations.length; i += 1) {
    try {
      browser = await puppeteer.launch({
        executablePath: CHROME,
        headless: true,
        args: configurations[i],
        protocolTimeout: 180000,
      });
      if (i > 0) console.log('Chrome démarré avec le jeu d’arguments standard de repli.');
      break;
    } catch (e) {
      derniereErreur = e;
      console.error(`Jeu d'arguments Chrome ${i + 1} refusé: ${String(e).slice(0, 500)}`);
    }
  }
  if (!browser) throw derniereErreur;
  try {
    for (const scenario of (LIMIT > 0 ? SCENARIOS.slice(0, LIMIT) : SCENARIOS)) {
      process.stdout.write(`Capture ${scenario.nom}… `);
      try {
        const r = await ouvrir(browser, scenario);
        await r.page.screenshot({ path: path.join(OUT, `${scenario.nom}.png`) });
        const m = r.mesure;
        const debordement = Math.max(
          m.documentWidth - m.innerWidth,
          m.documentHeight - m.innerHeight,
          m.bodyWidth - m.innerWidth,
          m.bodyHeight - m.innerHeight,
        );
        resultats.push({
          ...scenario,
          capture: `${scenario.nom}.png`,
          premierFrameMs: r.premierFrameMs,
          attenteMs: r.attenteMs,
          calme: r.calme,
          debordementDomPx: debordement,
          erreursJs: r.erreurs,
          requetesExternesBloquees: [...new Set(r.externes)].sort(),
        });
        console.log(`calme=${r.calme}, débordement DOM=${debordement}px, erreurs JS=${r.erreurs.length}`);
        await r.page.close();
      } catch (e) {
        // Une taille en échec ne doit pas priver toutes les autres de rapport.
        resultats.push({
          ...scenario,
          capture: null,
          calme: false,
          debordementDomPx: 0,
          erreursJs: [],
          erreurCapture: String(e && e.stack ? e.stack : e).slice(0, 1600),
        });
        console.log(`ÉCHEC: ${String(e).slice(0, 300)}`);
      }
      fs.writeFileSync(path.join(OUT, 'mesures.json'), JSON.stringify(resultats, null, 2));
    }
  } finally {
    await browser.close();
  }
  if (resultats.some((r) => !r.calme || r.debordementDomPx > 1 || r.erreursJs.length || r.erreurCapture)) {
    process.exitCode = 2;
  }
})().catch((e) => {
  console.error(e.stack || e);
  try {
    fs.mkdirSync(OUT, { recursive: true });
    fs.writeFileSync(path.join(OUT, 'mesures.json'), JSON.stringify([{
      nom: 'chrome-lancement', w: 0, h: 0, dpr: 1, mobile: false,
      capture: null, calme: false, debordementDomPx: 0, erreursJs: [],
      erreurCapture: String(e && e.stack ? e.stack : e).slice(0, 3000),
    }], null, 2));
  } catch (_) {}
  process.exit(1);
});

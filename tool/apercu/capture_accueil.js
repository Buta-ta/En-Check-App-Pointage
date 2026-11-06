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
const BASE = 'http://127.0.0.1:8080/';
const CHROME = process.env.CHROME_PATH ||
  ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser']
    .find((p) => fs.existsSync(p));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const SCENARIOS = [
  { nom: 'reference-412x869-clair', w: 412, h: 869, dpr: 2, mobile: true },
  { nom: 'reference-412x869-sombre', w: 412, h: 869, dpr: 2, mobile: true, sombre: true },
  { nom: 'telephone-360x640-clair', w: 360, h: 640, dpr: 2, mobile: true },
  { nom: 'telephone-360x640-sombre', w: 360, h: 640, dpr: 2, mobile: true, sombre: true },
  { nom: 'telephone-390x844-clair', w: 390, h: 844, dpr: 3, mobile: true },
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
];

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
    S('checklist_motif_choisi', true);
    S('checklist_premier_pointage', true);
    S('module_qr_scanner', true); // le bouton « Autres modes » de la maquette
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
  await page.goto(BASE, { waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction(() => window.__firstFrame !== null, { timeout: 120000 });
  const premierFrameMs = await page.evaluate(() => Math.round(window.__firstFrame));

  // Attendre la fin de l'animation unique et le chargement des images/fontes.
  let calme = false;
  let precedent = -1;
  let stable = 0;
  for (let i = 0; i < 60 && !calme; i += 1) {
    const raf = await page.evaluate(() => window.__raf);
    stable = raf === precedent ? stable + 1 : 0;
    precedent = raf;
    calme = stable >= 4;
    if (!calme) await sleep(400);
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
  const resultats = [];
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist',
      '--lang=fr-FR',
    ],
    protocolTimeout: 180000,
  });
  try {
    for (const scenario of SCENARIOS) {
      process.stdout.write(`Capture ${scenario.nom}… `);
      const r = await ouvrir(browser, scenario);
      await r.page.screenshot({ path: path.join(OUT, `${scenario.nom}.png`) });
      const m = r.mesure;
      const debordement = Math.max(
        m.documentWidth - m.innerWidth,
        m.documentHeight - m.innerHeight,
        m.bodyWidth - m.innerWidth,
        m.bodyHeight - m.innerHeight,
      );
      const resultat = {
        ...scenario,
        capture: `${scenario.nom}.png`,
        premierFrameMs: r.premierFrameMs,
        attenteMs: r.attenteMs,
        calme: r.calme,
        debordementDomPx: debordement,
        erreursJs: r.erreurs,
        requetesExternesBloquees: [...new Set(r.externes)].sort(),
      };
      resultats.push(resultat);
      fs.writeFileSync(path.join(OUT, 'mesures.json'), JSON.stringify(resultats, null, 2));
      console.log(`calme=${r.calme}, débordement DOM=${debordement}px, erreurs JS=${r.erreurs.length}`);
      await r.page.close();
    }
  } finally {
    await browser.close();
  }
  if (resultats.some((r) => !r.calme || r.debordementDomPx > 1 || r.erreursJs.length)) {
    process.exitCode = 2;
  }
})().catch((e) => {
  console.error(e.stack || e);
  process.exit(1);
});

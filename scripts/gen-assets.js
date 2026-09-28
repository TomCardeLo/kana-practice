// Regenera favicon.ico, apple-touch-icon.png (a partir de favicon.svg) y og.png (captura
// real de la app a 1200x630). Uso: npm run assets
// La app se sirve desde el disco con page.route, sin levantar servidor; Google Fonts sí
// se descarga de la red para que la captura use las fuentes reales.
const { chromium } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const ORIGIN = 'http://kana.local';
const TYPES = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml' };

// Sin rx: iOS rellena de negro las esquinas transparentes del apple-touch-icon.
const svg = fs.readFileSync(path.join(ROOT, 'favicon.svg'), 'utf8').replace(' rx="14"', '');

async function icon(browser, size) {
  const page = await browser.newPage({ viewport: { width: size, height: size } });
  await page.setContent(`<style>*{margin:0}svg{display:block;width:${size}px;height:${size}px}</style>${svg}`);
  const png = await page.screenshot({ omitBackground: true });
  await page.close();
  return png;
}

// ICO con un único PNG de 32x32 embebido (formato admitido por todos los navegadores).
function pngToIco(png) {
  const header = Buffer.alloc(22);
  header.writeUInt16LE(0, 0); // reservado
  header.writeUInt16LE(1, 2); // tipo: icono
  header.writeUInt16LE(1, 4); // número de imágenes
  header.writeUInt8(32, 6); // ancho
  header.writeUInt8(32, 7); // alto
  header.writeUInt16LE(1, 10); // planos de color
  header.writeUInt16LE(32, 12); // bits por píxel
  header.writeUInt32LE(png.length, 14);
  header.writeUInt32LE(22, 18); // offset del PNG
  return Buffer.concat([header, png]);
}

async function ogImage(browser) {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
  await page.route(`${ORIGIN}/**`, (route) => {
    const rel = new URL(route.request().url()).pathname.replace(/^\/$/, '/index.html');
    const file = path.join(ROOT, rel);
    route.fulfill({ body: fs.readFileSync(file), contentType: TYPES[path.extname(file)] });
  });
  await page.addInitScript(() => localStorage.setItem('kana-practice:tutorial-seen:v1', '1'));
  await page.goto(`${ORIGIN}/`);
  await page.getByTestId('row-chip-a').waitFor({ state: 'attached' });
  // La hoja de fuentes carga sin bloquear (media="print" -> "all"): esperar a que se active.
  await page.locator('link[href*="fonts.googleapis.com"][media="all"]').first().waitFor({ state: 'attached' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(ROOT, 'og.png') });
}

(async () => {
  const browser = await chromium.launch();
  try {
    fs.writeFileSync(path.join(ROOT, 'apple-touch-icon.png'), await icon(browser, 180));
    fs.writeFileSync(path.join(ROOT, 'favicon.ico'), pngToIco(await icon(browser, 32)));
    await ogImage(browser);
    console.log('Generados: apple-touch-icon.png, favicon.ico, og.png');
  } finally {
    await browser.close();
  }
})();

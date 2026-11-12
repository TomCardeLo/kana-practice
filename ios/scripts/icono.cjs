// Genera el icono de la app iOS (1024×1024, sin transparencia) desde favicon.svg, igual que la web.
// Uso: node ios/scripts/icono.cjs
const { chromium } = require('@playwright/test');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const DESTINO = path.join(ROOT, 'ios/Sources/Assets.xcassets/AppIcon.appiconset');
const svg = fs.readFileSync(path.join(ROOT, 'favicon.svg'), 'utf8').replace(' rx="14"', '');

(async () => {
  const browser = await chromium.launch({ channel: 'chrome' });
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
  await page.setContent(`<style>*{margin:0}svg{display:block;width:1024px;height:1024px}</style>${svg}`);
  const jpg = path.join(DESTINO, 'icono.jpg');
  await page.screenshot({ path: jpg, type: 'jpeg', quality: 100 });
  await browser.close();
  // JPEG → PNG: el icono no puede llevar canal alfa.
  execFileSync('sips', ['-s', 'format', 'png', jpg, '--out', path.join(DESTINO, 'icono.png')], { stdio: 'ignore' });
  fs.unlinkSync(jpg);
  fs.writeFileSync(path.join(DESTINO, 'Contents.json'), JSON.stringify({
    images: [{ filename: 'icono.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }],
    info: { author: 'xcode', version: 1 },
  }, null, 2));
  console.log('Icono generado en', DESTINO);
})();

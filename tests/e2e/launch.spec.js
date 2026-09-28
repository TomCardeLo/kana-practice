// Checklist de lanzamiento: lo que ven los buscadores y las redes al compartir el link.
// Con BASE_URL apuntando a producción también verifica la página 404 de Vercel.
const { test, expect } = require('@playwright/test');

test('metadatos SEO y Open Graph presentes en el HTML servido', async ({ page }) => {
  await page.goto('/');
  const meta = (sel) => page.locator(sel).getAttribute('content');
  expect((await meta('meta[name="description"]')).length).toBeGreaterThanOrEqual(50);
  expect(await meta('meta[property="og:title"]')).toBe('Kana Practice');
  expect(await meta('meta[property="og:description"]')).toBeTruthy();
  expect(await meta('meta[name="twitter:card"]')).toBe('summary_large_image');
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://kana-practice-green.vercel.app/');

  // La imagen de og:image apunta a producción; se comprueba el archivo equivalente del servidor actual.
  const ogPath = new URL(await meta('meta[property="og:image"]')).pathname;
  const og = await page.request.get(ogPath);
  expect(og.status()).toBe(200);
  expect(og.headers()['content-type']).toContain('image/png');
});

test('favicons, robots.txt y sitemap.xml se sirven', async ({ request }) => {
  for (const path of ['/favicon.ico', '/favicon.svg', '/apple-touch-icon.png']) {
    expect((await request.get(path)).status(), path).toBe(200);
  }
  const robots = await (await request.get('/robots.txt')).text();
  expect(robots).toContain('Allow: /');
  expect(robots).toContain('Sitemap: https://kana-practice-green.vercel.app/sitemap.xml');
  const sitemap = await (await request.get('/sitemap.xml')).text();
  expect(sitemap).toContain('<loc>https://kana-practice-green.vercel.app/</loc>');
});

test('ruta inexistente responde 404 con página propia y enlace al inicio', async ({ page }) => {
  test.skip(!process.env.BASE_URL, 'El servidor local no reproduce el 404.html de Vercel');
  const res = await page.goto('/ruta-que-no-existe');
  expect(res.status()).toBe(404);
  await expect(page.getByRole('heading', { name: 'Página no encontrada' })).toBeVisible();
  await page.getByTestId('link-home').click();
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
});

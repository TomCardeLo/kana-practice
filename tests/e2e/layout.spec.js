// Escenario 8: sin overflow horizontal a 320 px, con práctica corregida, solución y filtro abiertos.
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

for (const syl of h.SYLLABARIES) {
  test(`${syl}: sin overflow horizontal a 320px`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 320, height: 720 });
    await h.open(page);
    await h.generate(page, 'El murciélago hambriento comía chocolate en la biblioteca municipal', syl);
    await h.answer(page, 'eru murushierago');
    await page.getByTestId('btn-solution').click();
    await h.openRowFilter(page);
    await expect(page.getByTestId('score')).not.toBeEmpty();

    const { scrollWidth, clientWidth } = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
    }));
    await testInfo.attach('320px', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
    expect(scrollWidth, 'ancho del documento').toBeLessThanOrEqual(clientWidth);
  });

  test(`${syl}: modo al azar sin overflow horizontal a 320px`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 320, height: 720 });
    await h.open(page);
    await h.selectSyllabary(page, syl);
    await h.answer(page, 'kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk');
    await expect(page.getByTestId('word-reveal')).toHaveCount(5);
    await h.openRowFilter(page);
    await testInfo.attach('320px-random', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
    const { scrollWidth, clientWidth } = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
    }));
    expect(scrollWidth, 'ancho del documento').toBeLessThanOrEqual(clientWidth);
  });
}

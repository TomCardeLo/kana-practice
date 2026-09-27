// Textos largos (commit 31d0443): densidad compacta, scroll interno de #kana-output,
// indicador de posición is-current, panel de práctica sticky y pie sin marca.
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

const LONG_TEXT =
  'El aumento del salario mínimo de 2026 comenzó a reflejarse en las obligaciones pensionales de ' +
  'Colpensiones y, según Anif, generó una presión fiscal que se suma a las necesidades de recursos ' +
  'identificadas para cubrir las mesadas de noviembre y diciembre.';

const output = (page) => page.getByTestId('kana-output');
const current = (page) => page.locator('#kana-output .kana-cell.is-current');

async function currentIndex(page) {
  return page.evaluate(() => {
    const active = [...document.querySelectorAll('#kana-output .kana-cell:not(.is-dimmed)')];
    return active.findIndex((c) => c.classList.contains('is-current'));
  });
}

// Romaji esperado de las primeras `n` unidades activas, separado por palabras.
async function romajiPrefix(page, n) {
  return page.evaluate((count) => {
    const out = [];
    let taken = 0;
    for (const word of document.querySelectorAll('#kana-output .kana-word')) {
      const units = [...word.querySelectorAll('.kana-cell:not(.is-dimmed)')].map((c) => c.dataset.romaji);
      const part = [];
      for (let i = 0; i < units.length && taken < count; i += 1, taken += 1) {
        part.push(units[i] === 'n' && /^[aeiouy]/.test(units[i + 1] || '') ? "n'" : units[i]);
      }
      if (part.length) out.push(part.join(''));
      if (taken >= count) break;
    }
    return out.join(' ');
  }, n);
}

async function expectCurrentVisibleInOutput(page) {
  await expect
    .poll(async () =>
      current(page).evaluate((cell) => {
        const box = document.getElementById('kana-output').getBoundingClientRect();
        const r = cell.getBoundingClientRect();
        return r.top >= box.top - 1 && r.bottom <= box.bottom + 1;
      })
    )
    .toBe(true);
}

test.beforeEach(async ({ page }) => {
  await h.open(page);
});

test('densidad compacta solo con más de 24 kana', async ({ page }) => {
  await expect(h.cells(page).first()).toBeVisible();
  const roundUnits = await h.cells(page).count();
  if (roundUnits <= 24) await expect(output(page)).not.toHaveClass(/is-compact/);

  await h.generate(page, LONG_TEXT);
  expect(await h.cells(page).count()).toBeGreaterThan(24);
  await expect(output(page)).toHaveClass(/is-compact/);

  await h.generate(page, 'gato rojo');
  await expect(output(page)).not.toHaveClass(/is-compact/);
});

test('texto largo: #kana-output tiene altura máxima y scroll interno', async ({ page }) => {
  await h.generate(page, LONG_TEXT);
  const m = await output(page).evaluate((el) => {
    const cs = getComputedStyle(el);
    return { sh: el.scrollHeight, ch: el.clientHeight, overflowY: cs.overflowY, maxH: parseFloat(cs.maxHeight), vh: innerHeight, vw: innerWidth };
  });
  expect(m.overflowY).toBe('auto');
  expect(m.sh).toBeGreaterThan(m.ch);
  const expectedMax = m.vw >= 1024 ? Math.min(0.52 * m.vh, 520) : 0.42 * m.vh;
  expect(Math.abs(m.maxH - expectedMax)).toBeLessThanOrEqual(1);
});

test('is-current: celda 0 con respuesta vacía y "eru aume" -> ん (índice 5)', async ({ page }) => {
  await h.generate(page, LONG_TEXT);
  await expect(current(page)).toHaveCount(1);
  expect(await currentIndex(page)).toBe(0);

  const input = page.getByTestId('input-answer');
  await input.fill('eru aume');
  await expect(current(page).locator('.kana-cell__kana')).toHaveText('ん');
  expect(await currentIndex(page)).toBe(5);
  // Una consonante suelta final (aún sin kana) no avanza el indicador.
  await input.fill('eru aum');
  await expect.poll(() => currentIndex(page)).toBe(4);
  await input.fill('');
  await expect.poll(() => currentIndex(page)).toBe(0);
});

test('is-current no avanza con una sílaba de dos letras a medio escribir (sh, ts, ch)', async ({ page }) => {
  await page.getByTestId('input-answer').fill('puresh');
  await expect.poll(() => currentIndex(page), { timeout: 2000 }).toBe(2);
  await page.getByTestId('input-answer').fill('pureshion ts');
  await expect.poll(() => currentIndex(page), { timeout: 2000 }).toBe(5);
});

test('al escribir ~33 unidades is-current avanza, sigue visible en el contenedor y la página no se desplaza', async ({ page }) => {
  await h.generate(page, LONG_TEXT);
  const input = page.getByTestId('input-answer');
  await input.click();
  const before = await page.evaluate(() => window.scrollY);
  const outBefore = await output(page).evaluate((el) => el.scrollTop);

  // Al menos 33 unidades, y siempre hasta pasar el borde inferior visible del contenedor,
  // para que el scroll interno se ejerza también en 1440 px (donde caben más kana).
  const target = await output(page).evaluate((el) => {
    const active = [...el.querySelectorAll('.kana-cell:not(.is-dimmed)')];
    const firstHidden = active.findIndex((c) => c.offsetTop + c.offsetHeight > el.clientHeight);
    return Math.max(33, firstHidden + 3);
  });
  const answer = await romajiPrefix(page, target);
  await input.pressSequentially(`${answer} `);
  await expect.poll(() => currentIndex(page)).toBe(target);
  await expectCurrentVisibleInOutput(page);
  expect(await output(page).evaluate((el) => el.scrollTop)).toBeGreaterThan(outBefore);
  expect(await page.evaluate(() => window.scrollY)).toBe(before);
});

test('tras corregir o mostrar la solución no hay celda is-current', async ({ page }) => {
  await h.generate(page, LONG_TEXT);
  await page.getByTestId('input-answer').fill('eru aume');
  await expect(current(page)).toHaveCount(1);
  await page.getByTestId('btn-check').click();
  await expect(page.getByTestId('score')).toContainText('correctos');
  await expect(current(page)).toHaveCount(0);
  await page.getByTestId('input-answer').pressSequentially('nto');
  await expect(current(page)).toHaveCount(0);

  await h.generate(page, LONG_TEXT);
  await expect(current(page)).toHaveCount(1);
  await page.getByTestId('btn-solution').click();
  await expect(current(page)).toHaveCount(0);
  await page.getByTestId('input-answer').fill('eru');
  await expect(current(page)).toHaveCount(0);
});

test('el panel de práctica no se solapa con las estadísticas al bajar hasta el final', async ({ page }) => {
  await h.generate(page, LONG_TEXT);
  await h.answer(page, 'eru aumento deru'); // llena el panel de estadísticas
  await expect(page.getByTestId('stats-cell').first()).toBeVisible();
  const positions = [0, 0.25, 0.5, 0.75, 1];
  for (const p of positions) {
    await page.evaluate((f) => window.scrollTo(0, f * (document.documentElement.scrollHeight - innerHeight)), p);
    const { practiceBottom, statsTop } = await page.evaluate(() => ({
      practiceBottom: document.querySelector('.practice').getBoundingClientRect().bottom,
      statsTop: document.querySelector('.stats-panel').getBoundingClientRect().top,
    }));
    expect(practiceBottom, `scroll ${p * 100}%`).toBeLessThanOrEqual(statsTop + 0.5);
  }
  const position = await page.locator('.practice').evaluate((el) => getComputedStyle(el).position);
  expect(position).toBe(page.viewportSize().width >= 1024 ? 'sticky' : 'static');
  await expect(page.locator('.workspace .practice')).toHaveCount(1);
  await expect(page.locator('.workspace .controls')).toHaveCount(1);
});

test('pie: solo "Código en GitHub", sin mención a 2DATO', async ({ page }) => {
  const footer = page.locator('footer.site-footer');
  await expect(footer).not.toContainText('2DATO');
  await expect(footer.getByRole('link')).toHaveCount(1);
  await expect(footer.getByRole('link')).toHaveText('Código en GitHub');
  await expect(footer.getByRole('link')).toHaveAttribute('href', 'https://github.com/TomCardeLo/kana-practice');
  expect(await page.content()).not.toContain('2DATO');
});

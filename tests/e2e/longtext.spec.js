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
  const expectedMax = m.vw >= 1024 ? Math.min(m.vh - 140, 720) : 0.42 * m.vh;
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

const rect = (page, sel) =>
  page.locator(sel).first().evaluate((el) => {
    const r = el.getBoundingClientRect();
    return { top: r.top, bottom: r.bottom, left: r.left, right: r.right };
  });
const isDesktop = (page) => page.viewportSize().width >= 1024;

test('.answer-pane es sticky solo en ≥1024px y nunca se solapa con estadísticas', async ({ page }) => {
  await h.generate(page, LONG_TEXT);
  await h.answer(page, 'eru aumento deru'); // llena el panel de estadísticas
  await expect(page.getByTestId('stats-cell').first()).toBeVisible();
  for (const p of [0, 0.25, 0.5, 0.75, 1]) {
    await page.evaluate((f) => window.scrollTo(0, f * (document.documentElement.scrollHeight - innerHeight)), p);
    const answerPane = await rect(page, '.answer-pane');
    const practice = await rect(page, '.practice');
    const stats = await rect(page, '.stats-panel');
    expect(answerPane.bottom, `answer-pane, scroll ${p * 100}%`).toBeLessThanOrEqual(stats.top + 0.5);
    expect(practice.bottom, `practice, scroll ${p * 100}%`).toBeLessThanOrEqual(stats.top + 0.5);
  }
  const pos = (sel) => page.locator(sel).evaluate((el) => getComputedStyle(el).position);
  expect(await pos('.answer-pane')).toBe(isDesktop(page) ? 'sticky' : 'static');
  expect(await pos('.practice')).toBe('static');
  await expect(page.locator('.workspace')).toHaveCount(0);
  await expect(page.locator('.practice .practice-grid .kana-pane #kana-output')).toHaveCount(1);
  await expect(page.locator('.practice .practice-grid .answer-pane #input-answer')).toHaveCount(1);
  await expect(page.locator('.practice .answer-pane #score')).toHaveCount(1);
});

test('kana y respuesta lado a lado en ≥1024px, apilados en <1024px', async ({ page }) => {
  await h.generate(page, LONG_TEXT);
  await page.locator('.practice').scrollIntoViewIfNeeded();
  const kana = await rect(page, '#kana-output');
  const input = await rect(page, '#input-answer');
  if (isDesktop(page)) {
    expect(input.left, 'respuesta a la derecha del kana').toBeGreaterThanOrEqual(kana.right);
    expect(input.top < kana.bottom && input.bottom > kana.top, 'rangos verticales solapados').toBe(true);
  } else {
    expect(input.top, 'respuesta debajo del kana').toBeGreaterThanOrEqual(kana.bottom);
  }
  const m = await page.getByTestId('input-answer').evaluate((el) => ({
    rows: el.rows,
    maxH: parseFloat(getComputedStyle(el).maxHeight),
    vh: innerHeight,
  }));
  expect(m.rows).toBe(6);
  expect(Math.abs(m.maxH - (isDesktop(page) ? 0.5 : 0.3) * m.vh)).toBeLessThanOrEqual(1);
});

test('1440x900: tras ir a la sección 03 con texto largo, kana y respuesta visibles a la vez', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await h.generate(page, LONG_TEXT);
  await page.locator('#practice-heading').evaluate((el) => el.scrollIntoView({ block: 'start' }));
  await page.getByTestId('input-answer').click();
  await page.getByTestId('input-answer').pressSequentially('eru aumento');
  await testInfo.attach('seccion-03-1440', { body: await page.screenshot(), contentType: 'image/png' });
  const vh = 900;
  const kana = await rect(page, '#kana-output');
  const input = await rect(page, '#input-answer');
  const btn = await rect(page, '[data-testid="btn-check"]');
  expect(kana.top).toBeGreaterThanOrEqual(0);
  expect(kana.bottom).toBeLessThanOrEqual(vh);
  expect(input.top).toBeGreaterThanOrEqual(0);
  expect(input.bottom).toBeLessThanOrEqual(vh);
  expect(btn.bottom).toBeLessThanOrEqual(vh);
  await expect(page.locator('#kana-output .kana-cell.is-current')).toBeInViewport();
});

test('top-panel: 01 (modo) y 02 (silabario) en la misma fila en ≥1024px, apilados debajo', async ({ page }) => {
  const mode = await rect(page, '.top-panel .top-col--mode');
  const syl = await rect(page, '.top-panel .top-col--syllabary');
  if (isDesktop(page)) {
    expect(syl.left).toBeGreaterThanOrEqual(mode.right - 16.5); // margin-left -16px del borde divisor
    expect(Math.abs(syl.top - mode.top)).toBeLessThanOrEqual(1);
  } else {
    expect(syl.top).toBeGreaterThanOrEqual(mode.bottom);
  }
  await expect(page.locator('.top-panel h2', { hasText: '01' })).toBeVisible();
  await expect(page.locator('.top-panel h2', { hasText: '02' })).toBeVisible();
});

test('pie: solo "Código en GitHub", sin mención a 2DATO', async ({ page }) => {
  const footer = page.locator('footer.site-footer');
  await expect(footer).not.toContainText('2DATO');
  await expect(footer.getByRole('link')).toHaveCount(1);
  await expect(footer.getByRole('link')).toHaveText('Código en GitHub');
  await expect(footer.getByRole('link')).toHaveAttribute('href', 'https://github.com/TomCardeLo/kana-practice');
  expect(await page.content()).not.toContain('2DATO');
});

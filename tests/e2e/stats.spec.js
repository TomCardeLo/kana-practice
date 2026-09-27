// Escenario 5: estadísticas (FM 21-24).
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

const statCells = (page) => page.getByTestId('stats-cell');

async function statsMap(page) {
  return statCells(page).evaluateAll((els) =>
    Object.fromEntries(
      els.map((e) => [e.querySelector('.stats-cell__kana').textContent.trim(), e.querySelector('.stats-cell__rate').textContent.trim()])
    )
  );
}

test('se acumulan, persisten al recargar, separan silabarios y se reinician', async ({ page }) => {
  await h.open(page);
  await expect(statCells(page)).toHaveCount(0);

  // Hiragana: 1ª práctica falla と, 2ª práctica todo bien -> と 50 %, が 0 %.
  await h.generate(page, 'gato', 'hiragana');
  await h.answer(page, 'gaso');
  await expect(statCells(page)).toHaveCount(2);
  await expect(statCells(page).first().locator('.stats-cell__kana')).toHaveText('と'); // orden por % error
  expect(await statsMap(page)).toEqual({ と: '100% error', が: '0% error' });
  // Volver a corregir la misma práctica no registra otra vez.
  await h.answer(page, 'gato');
  await expect(page.getByTestId('score')).toContainText('2 / 2 correctos');
  expect(await statsMap(page)).toEqual({ と: '100% error', が: '0% error' });
  await h.generate(page, 'gato');
  await h.answer(page, 'gato');
  await expect(statCells(page).first().locator('.stats-cell__rate')).toHaveText('50% error');
  expect(await statsMap(page)).toEqual({ と: '50% error', が: '0% error' });

  // Persisten tras recargar (FM 21).
  await page.reload();
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
  await expect(statCells(page)).toHaveCount(2);
  expect(await statsMap(page)).toEqual({ と: '50% error', が: '0% error' });

  // Katakana tiene su propio contador (FM 23).
  await h.selectSyllabary(page, 'katakana');
  await expect(statCells(page)).toHaveCount(0);
  await expect(page.locator('.stats-panel__empty')).toBeVisible();
  await h.generate(page, 'gato');
  await h.answer(page, 'kato');
  expect(await statsMap(page)).toEqual({ ガ: '100% error', ト: '0% error' });
  await h.selectSyllabary(page, 'hiragana');
  expect(await statsMap(page)).toEqual({ と: '50% error', が: '0% error' });

  // Reinicio con confirmación: el primer clic solo pide confirmar.
  const reset = page.getByTestId('btn-reset-stats');
  await reset.click();
  await expect(reset).toHaveText('¿Confirmas el reinicio?');
  await expect(statCells(page)).toHaveCount(2);
  await reset.click();
  await expect(page.getByTestId('message')).toHaveText('Estadísticas reiniciadas.');
  await expect(reset).toHaveText('Reiniciar estadísticas');
  await expect(statCells(page)).toHaveCount(0);

  // Borra ambos silabarios y sigue borrado tras recargar (FM 24).
  await page.reload();
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
  await expect(statCells(page)).toHaveCount(0);
  await h.selectSyllabary(page, 'katakana');
  await expect(statCells(page)).toHaveCount(0);
});

test('sin localStorage la práctica sigue funcionando (FM 22)', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.addInitScript(() => {
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      get() {
        throw new DOMException('bloqueado', 'SecurityError');
      },
    });
  });
  await h.open(page);
  await h.generate(page, 'gato', 'katakana');
  await h.expectKana(page, ['ガ', 'ト']);
  await h.answer(page, 'gato');
  await expect(page.getByTestId('score')).toHaveText('2 / 2 correctos');
  expect(errors).toEqual([]);
});

test('corregir después de "Mostrar solución" no cuenta en estadísticas', async ({ page }) => {
  await h.open(page);
  await h.generate(page, 'gato', 'hiragana');
  await page.getByTestId('btn-solution').click();
  await h.answer(page, 'gaso');
  await expect(page.getByTestId('score')).toContainText('1 / 2 correctos');
  await expect(page.getByTestId('score')).toContainText('(no cuenta en estadísticas)');
  await expect(statCells(page)).toHaveCount(0);

  // Modo al azar: igual.
  await h.selectMode(page, 'random');
  await page.getByTestId('btn-solution').click();
  await h.answer(page, 'x');
  await expect(page.getByTestId('score')).toContainText('(no cuenta en estadísticas)');
  await expect(statCells(page)).toHaveCount(0);
});

test('cambiar de silabario tras corregir recalcula sin re-registrar ni perder la respuesta', async ({ page }) => {
  await h.open(page);
  await h.generate(page, 'gato', 'hiragana');
  await h.answer(page, 'gaso');
  await h.expectStates(page, ['ok', 'error']);
  await h.selectSyllabary(page, 'katakana');
  await h.expectKana(page, ['ガ', 'ト']);
  await h.expectStates(page, ['ok', 'error']);
  await expect(page.getByTestId('input-answer')).toHaveValue('gaso');
  await expect(page.getByTestId('score')).toContainText('1 / 2 correctos');
  await expect(statCells(page)).toHaveCount(0); // katakana sin registros
  await h.selectSyllabary(page, 'hiragana');
  expect(await statsMap(page)).toEqual({ と: '100% error', が: '0% error' });
});

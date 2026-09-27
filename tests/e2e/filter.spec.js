// Escenario 4 (palabra al azar + filtro de filas) y FM 25-28.
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

// Oráculo propio: hiragana de las filas あ か さ た な ま ら わ(+ん).
const ALLOWED_ROWS = ['a', 'ka', 'sa', 'ta', 'na', 'ma', 'ra', 'wa'];
const ALLOWED_HIRAGANA = new Set([...'あいうえおかきくけこさしすせそたちつてとなにぬねのまみむめもらりるれろわをん']);
const REPEATS = 12;

test.beforeEach(async ({ page }) => {
  await h.open(page);
});

for (const syl of h.SYLLABARIES) {
  test.describe(syl, () => {
    test(`palabra al azar con filtro limitado usa solo kana de las filas activas (x${REPEATS})`, async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, ALLOWED_ROWS);
      const allowed = new Set([...ALLOWED_HIRAGANA].map((k) => (syl === 'katakana' ? h.toKatakana(k) : k)));
      const seen = new Set();

      for (let i = 0; i < REPEATS; i += 1) {
        await page.getByTestId('btn-random').click();
        const word = await page.getByTestId('input-text').inputValue();
        expect(word, 'el botón debe rellenar el texto').not.toBe('');
        seen.add(word);
        await page.getByTestId('btn-generate').click();
        await expect(h.cells(page).first()).toBeVisible();
        const kana = await h.cellKana(page).allTextContents();
        for (const k of kana) expect(allowed.has(k), `"${word}" -> ${k} fuera del filtro`).toBe(true);
        await expect(page.locator('[data-testid="kana-cell"][data-state="dimmed"]')).toHaveCount(0);
      }
      // Sanidad: el azar realmente varía.
      expect(seen.size).toBeGreaterThan(1);
    });

    test('filtro vacío avisa al pedir palabra al azar y al generar (FM 28)', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, []);
      await page.getByTestId('btn-random').click();
      await expect(page.getByTestId('message')).toHaveText('Selecciona al menos una fila del silabario.');
      await expect(page.getByTestId('input-text')).toHaveValue('');
      await page.getByTestId('input-text').fill('gato');
      await page.getByTestId('btn-generate').click();
      await expect(page.getByTestId('message')).toHaveText('Selecciona al menos una fila del silabario.');
      await expect(h.cells(page)).toHaveCount(0);
    });

    test('filtro sin palabras posibles avisa sin colgarse (FM 26)', async ({ page }) => {
      await h.setActiveRows(page, ['ya']);
      await page.getByTestId('btn-random').click();
      await expect(page.getByTestId('message')).toHaveText('Ninguna palabra usa solo las filas elegidas.');
    });

    test('texto sin ningún kana en las filas activas avisa', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, ['ma']);
      await h.generate(page, 'gato');
      await expect(page.getByTestId('message')).toHaveText('Ningún kana del texto está en las filas elegidas.');
    });

    test('じ y ず pertenecen a la fila ZA', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, ['za', 'ma', 'ra']); // dime -> ji me, duro -> zu ro
      await h.generate(page, 'dime duro');
      await h.expectKana(page, h.kanaFor(['じ', 'め', 'ず', 'ろ'], syl));
      await h.expectStates(page, ['pending', 'pending', 'pending', 'pending']);
    });

    test('texto libre: kana fuera del filtro se atenúan y no cuentan (FM 27)', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, ['a', 'ta', 'ra']);
      await h.generate(page, 'gato rojo'); // ga to / ro ho
      await h.expectStates(page, ['dimmed', 'pending', 'pending', 'dimmed']);
      await h.answer(page, 'to ro');
      await h.expectStates(page, ['dimmed', 'ok', 'ok', 'dimmed']);
      await expect(page.getByTestId('score')).toHaveText('2 / 2 correctos');
      const statKana = page.locator('[data-testid="stats-cell"] .stats-cell__kana');
      await expect(statKana).toHaveCount(2);
      expect((await statKana.allTextContents()).sort()).toEqual(h.kanaFor(['と', 'ろ'], syl).sort());
    });
  });
}

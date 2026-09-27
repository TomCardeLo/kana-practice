// Filtro por filas (FM 25-28). La parte de palabras al azar con filtro vive en random.spec.js.
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

test.beforeEach(async ({ page }) => {
  await h.open(page);
});

for (const syl of h.SYLLABARIES) {
  test.describe(syl, () => {
    test('filtro vacío avisa en ambos modos y no deja práctica (FM 28)', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, []);
      await page.getByTestId('btn-new-round').click();
      await expect(page.getByTestId('message')).toHaveText('Selecciona al menos una fila del silabario.');
      await expect(h.cells(page)).toHaveCount(0);

      await h.generate(page, 'gato');
      await expect(page.getByTestId('message')).toHaveText('Selecciona al menos una fila del silabario.');
      await expect(h.cells(page)).toHaveCount(0);
    });

    test('filtro sin palabras posibles avisa sin colgarse (FM 26)', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, ['ya']);
      await page.getByTestId('btn-new-round').click();
      await expect(page.getByTestId('message')).toHaveText('Ninguna palabra usa solo las filas elegidas.');
      await expect(h.cells(page)).toHaveCount(0);
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

    test('cambiar el filtro tras corregir recalcula, conserva la respuesta y no re-registra', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.generate(page, 'gato rojo');
      await h.answer(page, 'gaso roho');
      await h.expectStates(page, ['ok', 'error', 'ok', 'ok']);
      await h.setActiveRows(page, h.ROW_IDS.filter((r) => r !== 'ga'));
      await h.expectStates(page, ['dimmed', 'error', 'ok', 'ok']);
      await expect(page.getByTestId('score')).toContainText('2 / 3 correctos');
      await expect(page.getByTestId('input-answer')).toHaveValue('gaso roho');
      await h.setActiveRows(page, h.ROW_IDS);
      await h.expectStates(page, ['ok', 'error', 'ok', 'ok']);

      // Si el cambio de filtro hubiera registrado otra vez, と tendría 2 fallos:
      // tras un acierto en una práctica nueva quedaría en 67 % en vez de 50 %.
      await h.generate(page, 'gato');
      await h.answer(page, 'gato');
      const rate = page.locator('[data-testid="stats-cell"]', { hasText: h.kanaFor(['と'], syl)[0] }).locator('.stats-cell__rate');
      await expect(rate).toHaveText('50% error');
    });
  });
}

// Tutorial (plan §5.4) y navegación por teclado de las pestañas.
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

const dialog = (page) => page.getByTestId('tutorial-dialog');
const isOpen = (page) => dialog(page).evaluate((d) => d.open);

async function openTutorial(page) {
  await page.getByTestId('btn-tutorial').click();
  await expect(dialog(page)).toBeVisible();
}

async function expectNoHorizontalOverflow(page) {
  const m = await page.evaluate(() => {
    const d = document.getElementById('tutorial-dialog');
    const r = d.getBoundingClientRect();
    return {
      docScroll: document.documentElement.scrollWidth,
      docClient: document.documentElement.clientWidth,
      dialogLeft: r.left,
      dialogRight: r.right,
      dialogScroll: d.scrollWidth,
      dialogClient: d.clientWidth,
    };
  });
  expect(m.docScroll, 'documento').toBeLessThanOrEqual(m.docClient);
  expect(m.dialogLeft, 'borde izquierdo del diálogo').toBeGreaterThanOrEqual(0);
  expect(m.dialogRight, 'borde derecho del diálogo').toBeLessThanOrEqual(m.docClient);
  expect(m.dialogScroll, 'scroll horizontal dentro del diálogo').toBeLessThanOrEqual(m.dialogClient);
}

test('se abre solo en la primera visita y no tras recargar', async ({ page }) => {
  await h.open(page, { tutorialSeen: false });
  await expect(dialog(page)).toBeVisible();
  await expect(page.getByTestId('tutorial-panel-guide')).toBeVisible();
  await expect(page.locator('.tutorial-step')).toHaveCount(4);
  await page.getByTestId('btn-tutorial-close').click();
  await expect(dialog(page)).toBeHidden();

  await page.reload();
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
  await expect(h.cells(page).first()).toBeVisible(); // la app terminó de iniciar
  expect(await isOpen(page)).toBe(false);
});

test.describe('con el tutorial ya visto', () => {
  test.beforeEach(async ({ page }) => {
    await h.open(page);
    expect(await isOpen(page)).toBe(false);
  });

  test('btn-tutorial abre; Escape y Cerrar cierran devolviendo el foco', async ({ page }) => {
    await openTutorial(page);
    await page.keyboard.press('Escape');
    await expect(dialog(page)).toBeHidden();
    await expect(page.getByTestId('btn-tutorial')).toBeFocused();

    await openTutorial(page);
    await page.getByTestId('btn-tutorial-close').click();
    await expect(dialog(page)).toBeHidden();
    await expect(page.getByTestId('btn-tutorial')).toBeFocused();
  });

  test('las tres pestañas muestran su panel y ocultan el resto', async ({ page }) => {
    await openTutorial(page);
    const ids = ['guide', 'table', 'rules'];
    for (const active of ids) {
      await page.getByTestId(`tutorial-tab-${active}`).click();
      for (const id of ids) {
        await expect(page.getByTestId(`tutorial-tab-${id}`)).toHaveAttribute('aria-selected', String(id === active));
        const panel = page.getByTestId(`tutorial-panel-${id}`);
        if (id === active) await expect(panel).toBeVisible();
        else await expect(panel).toBeHidden();
      }
    }
  });

  test('tabla de kana: か/カ con su romaji "ka" en ambos silabarios', async ({ page }) => {
    await openTutorial(page);
    await page.getByTestId('tutorial-tab-table').click();
    const grid = page.getByTestId('tutorial-table-grid');
    const cell = (kana) => grid.locator('td').filter({ has: page.locator('.kana-table__kana', { hasText: new RegExp(`^${kana}$`) }) });

    await expect(cell('か').locator('.kana-table__romaji')).toHaveText('ka');
    await expect(cell('しゃ').locator('.kana-table__romaji')).toHaveText('sha');
    await expect(cell('ん').locator('.kana-table__romaji')).toHaveText('n');
    await expect(grid.locator('.kana-table__kana', { hasText: 'カ' })).toHaveCount(0);

    await page.getByTestId('tutorial-table-katakana').click();
    await expect(page.getByTestId('tutorial-table-katakana')).toHaveAttribute('aria-pressed', 'true');
    await expect(cell('カ').locator('.kana-table__romaji')).toHaveText('ka');
    await expect(cell('シャ').locator('.kana-table__romaji')).toHaveText('sha');
    await expect(grid.locator('.kana-table__kana', { hasText: /^か$/ })).toHaveCount(0);
  });

  test('aviso de ayuda solo con una ronda sin corregir', async ({ page }) => {
    // Ronda al azar generada al cargar y sin corregir -> aviso.
    await openTutorial(page);
    await page.getByTestId('tutorial-tab-table').click();
    await expect(page.getByTestId('tutorial-table-warning')).toBeVisible();
    await page.getByTestId('btn-tutorial-close').click();

    // Tras corregir, consultar la tabla ya no es ayuda.
    await h.answer(page, 'x');
    await expect(page.getByTestId('score')).toContainText('correctos');
    await openTutorial(page);
    await page.getByTestId('tutorial-tab-table').click();
    await expect(page.getByTestId('tutorial-table-warning')).toBeHidden();
    await page.getByTestId('btn-tutorial-close').click();

    // Nueva ronda -> vuelve el aviso (reabriendo con la pestaña de tabla ya activa).
    await page.getByTestId('btn-new-round').click();
    await openTutorial(page);
    await expect(page.getByTestId('tutorial-panel-table')).toBeVisible();
    await expect(page.getByTestId('tutorial-table-warning')).toBeVisible();
  });

  test('tabla de reglas: tres -> とれす (y otros ejemplos del plan)', async ({ page }) => {
    await openTutorial(page);
    await page.getByTestId('tutorial-tab-rules').click();
    const table = page.getByTestId('tutorial-rules-table');
    const kanaOf = (word) => table.locator('tr').filter({ has: page.locator('td', { hasText: new RegExp(`^${word}$`) }) }).locator('td').nth(2);
    await expect(kanaOf('tres')).toHaveText('とれす');
    await expect(kanaOf('sol')).toHaveText('そる');
    await expect(kanaOf('hola')).toHaveText('おら');
    await expect(kanaOf('canción')).toHaveText('かんしおん');
    // Siempre en hiragana, aunque la práctica esté en katakana.
    await page.getByTestId('btn-tutorial-close').click();
    await h.selectSyllabary(page, 'katakana');
    await openTutorial(page);
    await expect(kanaOf('tres')).toHaveText('とれす');
  });

  test('sin overflow horizontal a 320px con el tutorial abierto (3 pestañas)', async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 320, height: 640 });
    await openTutorial(page);
    for (const id of ['guide', 'table', 'rules']) {
      await page.getByTestId(`tutorial-tab-${id}`).click();
      await expect(page.getByTestId(`tutorial-panel-${id}`)).toBeVisible();
      await testInfo.attach(`tutorial-${id}-320px`, { body: await page.screenshot(), contentType: 'image/png' });
      await expectNoHorizontalOverflow(page);
    }
  });

  test('pestañas de modo con flechas: foco, selección y panel', async ({ page }) => {
    const random = page.getByTestId('tab-random');
    const text = page.getByTestId('tab-text');
    await random.focus();
    await page.keyboard.press('ArrowRight');
    await expect(text).toBeFocused();
    await expect(text).toHaveAttribute('aria-selected', 'true');
    await expect(text).toHaveAttribute('tabindex', '0');
    await expect(random).toHaveAttribute('tabindex', '-1');
    await expect(page.getByTestId('panel-text')).toBeVisible();
    await expect(page.getByTestId('panel-random')).toBeHidden();

    await page.keyboard.press('ArrowRight'); // vuelve al principio
    await expect(random).toBeFocused();
    await expect(page.getByTestId('panel-random')).toBeVisible();
    await expect(h.cells(page).first()).toBeVisible(); // el modo al azar genera ronda

    await page.keyboard.press('ArrowLeft'); // da la vuelta hacia atrás
    await expect(text).toBeFocused();
    await expect(page.getByTestId('panel-text')).toBeVisible();
    await page.keyboard.press('Home');
    await expect(random).toBeFocused();
    await expect(random).toHaveAttribute('aria-selected', 'true');
    await page.keyboard.press('End');
    await expect(text).toBeFocused();
    await expect(text).toHaveAttribute('aria-selected', 'true');
    // Tab desde la pestaña activa sale del tablist (solo una pestaña es tabulable).
    await page.keyboard.press('Tab');
    await expect(random).not.toBeFocused();
    await expect(text).not.toBeFocused();
  });

  test('pestañas del tutorial con flechas', async ({ page }) => {
    await openTutorial(page);
    await page.getByTestId('tutorial-tab-guide').focus();
    await page.keyboard.press('ArrowLeft');
    await expect(page.getByTestId('tutorial-tab-rules')).toBeFocused();
    await expect(page.getByTestId('tutorial-panel-rules')).toBeVisible();
    await page.keyboard.press('ArrowRight');
    await expect(page.getByTestId('tutorial-tab-guide')).toBeFocused();
    await page.keyboard.press('ArrowRight');
    await expect(page.getByTestId('tutorial-tab-table')).toBeFocused();
    await expect(page.getByTestId('tutorial-panel-table')).toBeVisible();
    await expect(page.getByTestId('tutorial-panel-guide')).toBeHidden();
    await page.keyboard.press('End');
    await expect(page.getByTestId('tutorial-tab-rules')).toBeFocused();
    await expect(page.getByTestId('tutorial-panel-rules')).toBeVisible();
    await page.keyboard.press('Home');
    await expect(page.getByTestId('tutorial-tab-guide')).toBeFocused();
    await expect(page.getByTestId('tutorial-panel-guide')).toBeVisible();
  });

  test('pestaña seleccionada con texto blanco sobre fondo distinto al de las demás', async ({ page }) => {
    const style = (tid) =>
      page.getByTestId(tid).evaluate((el) => {
        const cs = getComputedStyle(el);
        return { color: cs.color, bg: cs.backgroundColor };
      });
    const selected = await style('tab-random');
    const other = await style('tab-text');
    expect(selected.color).toBe('rgb(255, 255, 255)');
    expect(selected.bg).not.toBe(other.bg);
  });
});

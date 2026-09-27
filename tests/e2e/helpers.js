// Utilidades compartidas por los specs E2E. Todas las esperas son deterministas
// (auto-wait de locators y expect con reintento), nunca por tiempo.
const { expect } = require('@playwright/test');

const SYLLABARIES = ['hiragana', 'katakana'];

// Oráculo independiente de wanakana: hiragana -> katakana por desplazamiento Unicode.
function toKatakana(hiragana) {
  return [...hiragana]
    .map((c) => (c >= 'ぁ' && c <= 'ゖ' ? String.fromCharCode(c.charCodeAt(0) + 0x60) : c))
    .join('');
}

function kanaFor(hiraganaUnits, syllabary) {
  return syllabary === 'katakana' ? hiraganaUnits.map(toKatakana) : hiraganaUnits;
}

async function open(page) {
  await page.goto('/');
  // Los chips de filas se crean desde app.js (módulo que importa wanakana del CDN):
  // si existen, la app terminó de cargar.
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
}

async function selectSyllabary(page, syllabary) {
  const radio = page.getByTestId(`syllabary-${syllabary}`);
  await radio.locator('xpath=..').click();
  await expect(radio).toBeChecked();
}

async function generate(page, text, syllabary) {
  if (syllabary) await selectSyllabary(page, syllabary);
  await page.getByTestId('input-text').fill(text);
  await page.getByTestId('btn-generate').click();
}

async function answer(page, text) {
  await page.getByTestId('input-answer').fill(text);
  await page.getByTestId('btn-check').click();
}

const cells = (page) => page.getByTestId('kana-cell');
const cellKana = (page) => page.locator('[data-testid="kana-cell"] .kana-cell__kana');

async function expectKana(page, units) {
  await expect(cellKana(page)).toHaveText(units);
}

async function expectStates(page, states) {
  const loc = cells(page);
  await expect(loc).toHaveCount(states.length);
  for (let i = 0; i < states.length; i += 1) {
    await expect(loc.nth(i)).toHaveAttribute('data-state', states[i]);
  }
}

async function openRowFilter(page) {
  const details = page.locator('details.row-filter');
  if (!(await details.evaluate((d) => d.open))) await details.locator('summary').click();
  await expect(page.getByTestId('row-chip-a')).toBeVisible();
}

async function setRow(page, rowId, active) {
  const chip = page.getByTestId(`row-chip-${rowId}`);
  if ((await chip.getAttribute('aria-pressed')) !== String(active)) await chip.click();
  await expect(page.getByTestId(`row-chip-${rowId}`)).toHaveAttribute('aria-pressed', String(active));
}

async function setActiveRows(page, activeIds) {
  await openRowFilter(page);
  const ids = await page
    .locator('[data-testid^="row-chip-"]')
    .evaluateAll((els) => els.map((e) => e.dataset.testid.replace('row-chip-', '')));
  for (const id of ids) await setRow(page, id, activeIds.includes(id));
}

module.exports = {
  SYLLABARIES,
  toKatakana,
  kanaFor,
  open,
  selectSyllabary,
  generate,
  answer,
  cells,
  cellKana,
  expectKana,
  expectStates,
  openRowFilter,
  setActiveRows,
};

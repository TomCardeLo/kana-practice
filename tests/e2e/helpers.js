// Utilidades compartidas por los specs E2E. Todas las esperas son deterministas
// (auto-wait de locators y expect con reintento), nunca por tiempo.
const { expect } = require('@playwright/test');

const SYLLABARIES = ['hiragana', 'katakana'];
const ROW_IDS = ['a', 'ka', 'sa', 'ta', 'na', 'ha', 'ma', 'ya', 'ra', 'wa', 'ga', 'za', 'da', 'ba', 'pa',
  'kya', 'sha', 'cha', 'nya', 'hya', 'mya', 'rya', 'gya', 'ja', 'bya', 'pya'];

// Oráculo independiente de wanakana: hiragana -> katakana por desplazamiento Unicode.
function toKatakana(hiragana) {
  return [...hiragana]
    .map((c) => (c >= 'ぁ' && c <= 'ゖ' ? String.fromCharCode(c.charCodeAt(0) + 0x60) : c))
    .join('');
}

function kanaFor(hiraganaUnits, syllabary) {
  return syllabary === 'katakana' ? hiraganaUnits.map(toKatakana) : hiraganaUnits;
}

const TUTORIAL_SEEN_KEY = 'kana-practice:tutorial-seen:v1';

// Por defecto marca el tutorial como visto para que el <dialog> modal de primera visita
// no bloquee la interacción. Los tests del tutorial usan { tutorialSeen: false }.
async function open(page, { tutorialSeen = true } = {}) {
  if (tutorialSeen) {
    await page.addInitScript((key) => {
      try {
        localStorage.setItem(key, '1');
      } catch {
        // Sin localStorage (test FM 22): la app tampoco abre el tutorial.
      }
    }, TUTORIAL_SEEN_KEY);
  }
  await page.goto('/');
  // Los chips de filas y la ronda inicial se crean desde app.js: si existen, la app cargó.
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
}

async function selectMode(page, mode) {
  const tab = page.getByTestId(mode === 'text' ? 'tab-text' : 'tab-random');
  // Pulsar la pestaña activa reinicia la práctica: solo se pulsa si no lo está.
  if ((await tab.getAttribute('aria-selected')) !== 'true') await tab.click();
  await expect(tab).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByTestId(mode === 'text' ? 'panel-text' : 'panel-random')).toBeVisible();
}

async function selectSyllabary(page, syllabary) {
  const radio = page.getByTestId(`syllabary-${syllabary}`);
  await radio.locator('xpath=..').click();
  await expect(radio).toBeChecked();
}

// Modo "Texto propio": escribe el texto y pulsa Generar.
async function generate(page, text, syllabary) {
  await selectMode(page, 'text');
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
  ROW_IDS,
  toKatakana,
  kanaFor,
  TUTORIAL_SEEN_KEY,
  open,
  selectMode,
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

// Modo "Palabras al azar" (plan §2 modo A, §5.1, §5.3 y FM 25).
const fs = require('fs');
const path = require('path');
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

const ROOT = path.join(__dirname, '..', '..');
const WORDS = [...fs.readFileSync(path.join(ROOT, 'src', 'words.js'), 'utf8').matchAll(/'([^']+)'/g)].map((m) => m[1]);
// Base estática: el index.html sin el <dialog> del tutorial (su tabla de reglas usa
// ejemplos fijos como "casa" o "sol", que no son una filtración de la ronda).
const STATIC_HTML = fs
  .readFileSync(path.join(ROOT, 'index.html'), 'utf8')
  .replace(/<dialog[\s\S]*?<\/dialog>/g, '')
  .replace(/<script[\s\S]*?<\/script>/g, '');

const ALLOWED_ROWS = ['a', 'ka', 'sa', 'ta', 'na', 'ma', 'ra', 'wa'];
const ALLOWED_HIRAGANA = [...'あいうえおかきくけこさしすせそたちつてとなにぬねのまみむめもらりるれろわをん'];
const ROUNDS = 6;

const groups = (page) => page.locator('#kana-output .kana-word-group');
const reveals = (page) => page.getByTestId('word-reveal');

function countWord(haystack, word) {
  const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return (haystack.match(new RegExp(`(?<!\\p{L})${escaped}(?!\\p{L})`, 'giu')) || []).length;
}

// Todo lo que el usuario (o un lector de pantalla) podría ver: HTML vivo del documento sin
// el tutorial ni los <script>, más título y valores de los campos de texto.
async function liveSurface(page) {
  return page.evaluate(() => {
    const clone = document.documentElement.cloneNode(true);
    clone.querySelectorAll('dialog, script').forEach((el) => el.remove());
    const values = [...document.querySelectorAll('input, textarea')].map((el) => el.value);
    return [document.title, clone.outerHTML, ...values].join('\n');
  });
}

async function groupKana(page) {
  return groups(page).evaluateAll((els) =>
    els.map((g) => [...g.querySelectorAll('.kana-cell__kana')].map((k) => k.textContent))
  );
}

async function revealWords(page) {
  await page.getByTestId('btn-solution').click();
  await expect(reveals(page)).toHaveCount(await groups(page).count());
  return reveals(page).allTextContents();
}

test.beforeEach(async ({ page }) => {
  await h.open(page);
});

for (const syl of h.SYLLABARIES) {
  test.describe(syl, () => {
    test('al cargar hay una ronda de 5 palabras sin repetir, pendiente de corregir', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await expect(page.getByTestId('tab-random')).toHaveAttribute('aria-selected', 'true');
      await expect(groups(page)).toHaveCount(5);
      await expect(page.locator('[data-testid="kana-cell"]:not([data-state="pending"])')).toHaveCount(0);
      const words = await revealWords(page);
      expect(new Set(words).size).toBe(5);
      for (const w of words) expect(WORDS).toContain(w);
    });

    test('el español no aparece en la página (texto ni atributos) antes de corregir', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await expect(groups(page)).toHaveCount(5);
      await expect(reveals(page)).toHaveCount(0);
      const before = await liveSurface(page);
      for (const r of await page.locator('.kana-cell__romaji').all()) await expect(r).toBeHidden();

      const words = await revealWords(page);
      const after = await liveSurface(page);
      for (const w of words) {
        const baseline = countWord(STATIC_HTML, w);
        expect(countWord(before, w), `"${w}" visible antes de corregir`).toBe(baseline);
        // Control positivo: la misma búsqueda sí la encuentra tras "Mostrar solución".
        expect(countWord(after, w), `"${w}" tras la solución`).toBeGreaterThan(baseline);
      }
    });

    test('corregir revela las palabras y una transcripción perfecta da N/N', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await expect(groups(page)).toHaveCount(5);
      const romaji = await groups(page).evaluateAll((els) =>
        els.map((g) => {
          const units = [...g.querySelectorAll('[data-testid="kana-cell"]')].map((c) => c.dataset.romaji);
          return units.map((u, i) => (u === 'n' && /^[aeiouy]/.test(units[i + 1] || '') ? "n'" : u)).join('');
        })
      );
      const total = await h.cells(page).count();
      await h.answer(page, romaji.join(' '));
      await expect(page.getByTestId('score')).toHaveText(`${total} / ${total} correctos`);
      await expect(reveals(page)).toHaveCount(5);
      for (const w of await reveals(page).allTextContents()) expect(WORDS).toContain(w);
    });

    test('corregir con errores también revela las palabras', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.answer(page, 'x');
      await expect(page.getByTestId('score')).toContainText('correctos');
      await expect(reveals(page)).toHaveCount(5);
    });

    test('Nueva ronda cambia las palabras y vuelve a ocultarlas', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      const first = await revealWords(page);
      let next = first;
      for (let i = 0; i < 3 && next.join() === first.join(); i += 1) {
        await page.getByTestId('btn-new-round').click();
        await expect(reveals(page)).toHaveCount(0);
        await expect(page.getByTestId('score')).toBeEmpty();
        await expect(page.getByTestId('input-answer')).toHaveValue('');
        next = await revealWords(page);
      }
      expect(next).not.toEqual(first);
    });

    test('cambiar de silabario mantiene las mismas palabras', async ({ page }) => {
      const other = syl === 'hiragana' ? 'katakana' : 'hiragana';
      await h.selectSyllabary(page, syl);
      const words = await revealWords(page);
      const kanaBefore = await groupKana(page);

      await h.selectSyllabary(page, other);
      const kanaAfter = await groupKana(page);
      const toHira = (k) =>
        [...k].map((c) => (c >= 'ァ' && c <= 'ヶ' ? String.fromCharCode(c.charCodeAt(0) - 0x60) : c)).join('');
      expect(kanaAfter.map((g) => g.map(toHira))).toEqual(kanaBefore.map((g) => g.map(toHira)));
      expect(kanaAfter).not.toEqual(kanaBefore);
      expect(await revealWords(page)).toEqual(words);
    });

    test('pulsar la pestaña ya activa no regenera la ronda', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      const kana = await groupKana(page);
      await h.answer(page, 'x');
      const score = await page.getByTestId('score').textContent();
      await page.getByTestId('tab-random').click();
      expect(await groupKana(page)).toEqual(kana);
      await expect(page.getByTestId('score')).toHaveText(score);
      await expect(reveals(page)).toHaveCount(kana.length);
    });

    test(`con filtro de filas limitado todos los kana son de filas activas (${ROUNDS} rondas)`, async ({ page }) => {
      await h.selectSyllabary(page, syl);
      await h.setActiveRows(page, ALLOWED_ROWS);
      const allowed = new Set(ALLOWED_HIRAGANA.map((k) => (syl === 'katakana' ? h.toKatakana(k) : k)));
      const seen = new Set();
      for (let i = 0; i < ROUNDS; i += 1) {
        await page.getByTestId('btn-new-round').click();
        await expect(reveals(page)).toHaveCount(0);
        const n = await groups(page).count();
        expect(n).toBeGreaterThanOrEqual(1);
        expect(n).toBeLessThanOrEqual(5);
        for (const k of await h.cellKana(page).allTextContents()) {
          expect(allowed.has(k), `${k} fuera del filtro`).toBe(true);
        }
        await expect(page.locator('[data-testid="kana-cell"][data-state="dimmed"]')).toHaveCount(0);
        const words = await revealWords(page);
        expect(new Set(words).size).toBe(words.length);
        words.forEach((w) => seen.add(w));
      }
      expect(seen.size).toBeGreaterThan(5); // el azar varía entre rondas
    });
  });
}

// Las palabras de ejemplo del tutorial (tabla de reglas) nunca salen en una ronda: el
// tutorial es consultable durante la ronda y las delataría. Para cada ejemplo se activa
// exactamente el conjunto de filas que usa, de modo que si estuviera en el banco sería
// una de las pocas candidatas y aparecería casi seguro en 3 rondas.
test('las palabras de ejemplo del tutorial no salen en rondas al azar', async ({ page }) => {
  const examples = [...fs.readFileSync(path.join(ROOT, 'src', 'app.js'), 'utf8').matchAll(/palabra: '([^']+)'/g)].map((m) => m[1]);
  expect(examples.length).toBeGreaterThan(3);
  const rowsByExample = await page.evaluate(async (list) => {
    const { toSyllables } = await import('/src/translit.js');
    const { rowOf } = await import('/src/kana.js');
    return Object.fromEntries(list.map((w) => [w, [...new Set(toSyllables(w)[0].map(rowOf))]]));
  }, examples);

  for (const example of examples) {
    await h.setActiveRows(page, rowsByExample[example]);
    for (let i = 0; i < 3; i += 1) {
      await page.getByTestId('btn-new-round').click();
      if ((await groups(page).count()) === 0) {
        await expect(page.getByTestId('message')).toHaveText('Ninguna palabra usa solo las filas elegidas.');
        break;
      }
      const words = await revealWords(page);
      expect(words, `filas ${rowsByExample[example]}`).not.toContain(example);
    }
  }
});

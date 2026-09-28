// Minijuego de tarjetas (tarjetas.html). Referencias "FM n" = tests/e2e/failure-modes.md.
// El tiempo se controla con el reloj falso de Playwright (page.clock): los tiempos por
// tarjeta y la pausa de 1200 ms tras un error se avanzan con runFor, sin esperas por tiempo.
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

const BEST_KEY = 'kana-practice:cards-best:v1';
const STATS_KEY = 'kana-practice:stats:v1';

// --- Oráculo independiente de la app: hiragana -> romaji Hepburn, escrito a mano. ---
const BASICOS = {
  あ: 'a', い: 'i', う: 'u', え: 'e', お: 'o',
  か: 'ka', き: 'ki', く: 'ku', け: 'ke', こ: 'ko',
  さ: 'sa', し: 'shi', す: 'su', せ: 'se', そ: 'so',
  た: 'ta', ち: 'chi', つ: 'tsu', て: 'te', と: 'to',
  な: 'na', に: 'ni', ぬ: 'nu', ね: 'ne', の: 'no',
  は: 'ha', ひ: 'hi', ふ: 'fu', へ: 'he', ほ: 'ho',
  ま: 'ma', み: 'mi', む: 'mu', め: 'me', も: 'mo',
  や: 'ya', ゆ: 'yu', よ: 'yo',
  ら: 'ra', り: 'ri', る: 'ru', れ: 're', ろ: 'ro',
  わ: 'wa', を: 'wo', ん: 'n',
};
// ぢ/づ no tienen tarjeta propia: se fusionan con じ/ず.
const DAKUTEN = {
  が: 'ga', ぎ: 'gi', ぐ: 'gu', げ: 'ge', ご: 'go',
  ざ: 'za', じ: 'ji', ず: 'zu', ぜ: 'ze', ぞ: 'zo',
  だ: 'da', で: 'de', ど: 'do',
  ば: 'ba', び: 'bi', ぶ: 'bu', べ: 'be', ぼ: 'bo',
  ぱ: 'pa', ぴ: 'pi', ぷ: 'pu', ぺ: 'pe', ぽ: 'po',
};
const COMBINADOS = {
  きゃ: 'kya', きゅ: 'kyu', きょ: 'kyo',
  しゃ: 'sha', しゅ: 'shu', しょ: 'sho',
  ちゃ: 'cha', ちゅ: 'chu', ちょ: 'cho',
  にゃ: 'nya', にゅ: 'nyu', にょ: 'nyo',
  ひゃ: 'hya', ひゅ: 'hyu', ひょ: 'hyo',
  みゃ: 'mya', みゅ: 'myu', みょ: 'myo',
  りゃ: 'rya', りゅ: 'ryu', りょ: 'ryo',
  ぎゃ: 'gya', ぎゅ: 'gyu', ぎょ: 'gyo',
  じゃ: 'ja', じゅ: 'ju', じょ: 'jo',
  びゃ: 'bya', びゅ: 'byu', びょ: 'byo',
  ぴゃ: 'pya', ぴゅ: 'pyu', ぴょ: 'pyo',
};
const TODOS = { ...BASICOS, ...DAKUTEN, ...COMBINADOS };
// Variantes Kunrei (y "nn" para ん) aceptadas por la app.
const KUNREI = {
  shi: 'si', chi: 'ti', tsu: 'tu', fu: 'hu', ji: 'zi', n: 'nn',
  sha: 'sya', shu: 'syu', sho: 'syo', cha: 'tya', chu: 'tyu', cho: 'tyo',
  ja: 'zya', ju: 'zyu', jo: 'zyo',
};
const JYA = { ja: 'jya', ju: 'jyu', jo: 'jyo' };

const isKatakana = (kana) => /[ァ-ヶ]/.test(kana);
const toHiragana = (kana) =>
  [...kana].map((c) => (c >= 'ァ' && c <= 'ヶ' ? String.fromCharCode(c.charCodeAt(0) - 0x60) : c)).join('');

function romajiOf(kana) {
  const r = TODOS[toHiragana(kana)];
  if (!r) throw new Error(`El oráculo no conoce el kana «${kana}»`);
  return r;
}
const hepburn = (kana) => romajiOf(kana);
const kunrei = (kana) => KUNREI[romajiOf(kana)] ?? romajiOf(kana);
// Una lectura real pero incorrecta para el kana dado.
const wrongReading = (kana) => (romajiOf(kana) === 'ka' ? 'ko' : 'ka');

// --- Utilidades de la página ---
const T0 = new Date('2026-01-01T00:00:00Z');

async function openCards(page) {
  await page.addInitScript((key) => {
    try {
      localStorage.setItem(key, '1');
    } catch {
      // Sin localStorage (FM 40): el tutorial de index.html tampoco se abre.
    }
  }, h.TUTORIAL_SEEN_KEY);
  await page.clock.install({ time: T0 });
  await page.goto('/tarjetas.html');
  await expect(page.getByTestId('btn-start')).toBeVisible();
  // Reloj detenido: el tiempo solo avanza con runFor.
  await page.clock.pauseAt(new Date(T0.getTime() + 60_000));
}

async function choose(page, testId) {
  const radio = page.getByTestId(testId);
  await radio.locator('xpath=..').click();
  await expect(radio).toBeChecked();
}

async function start(page, { syl = 'hiragana', deck = 'basicos', size = '5' } = {}) {
  await choose(page, `cards-syllabary-${syl}`);
  await choose(page, `cards-deck-${deck}`);
  await choose(page, `cards-size-${size}`);
  await page.getByTestId('btn-start').click();
  await expect(page.getByTestId('cards-game')).toBeVisible();
}

const progress = (page) => page.getByTestId('progress');
const lives = (page) => page.getByTestId('lives');
const input = (page) => page.getByTestId('card-input');
const feedback = (page) => page.getByTestId('card-feedback');
const summary = (page) => page.getByTestId('cards-summary');

// Responde una tarjeta. En ん una sola «n» espera a la segunda «n» o a Enter.
async function answerCard(page, text) {
  await input(page).fill(text);
  if (text === 'n') await input(page).press('Enter');
}

async function readKana(page) {
  const kana = (await page.getByTestId('card-kana').textContent()).trim();
  expect(kana, 'tarjeta con kana').not.toBe('');
  return kana;
}

// Responde bien las tarjetas `from`..`total` (1-based). Devuelve los kana vistos.
async function playCorrect(page, total, answerFor = hepburn, { from = 1, tick = 0 } = {}) {
  const seen = [];
  for (let i = from; i <= total; i += 1) {
    await expect(progress(page)).toHaveText(`${i}/${total}`);
    const kana = await readKana(page);
    seen.push(kana);
    if (tick) await page.clock.runFor(tick);
    await answerCard(page, answerFor(kana));
  }
  return seen;
}

async function expectComplete(page, total) {
  await expect(summary(page)).toBeVisible();
  await expect(summary(page)).toHaveAttribute('data-result', 'complete');
  await expect(page.getByTestId('summary-correct')).toHaveText(`${total}/${total}`);
}

const readJson = (page, key) => page.evaluate((k) => JSON.parse(localStorage.getItem(k)), key);

// Estado "sin cambios" tras una acción que no debe contar.
async function expectUntouched(page, pos, total, livesLeft = 3) {
  await expect(progress(page)).toHaveText(`${pos}/${total}`);
  await expect(lives(page)).toHaveAttribute('data-lives', String(livesLeft));
  await expect(feedback(page)).toBeEmpty();
  await expect(input(page)).toBeEnabled();
}

const TIME_RE = /^\d+\.\d s$/;
const seconds = (text) => Number.parseFloat(text);

test.beforeEach(async ({ page }) => {
  await openCards(page);
});

test('ronda de 5 en hiragana/básicos respondida bien: tiempos, récord y estadísticas (FM 36, 37, 31)', async ({ page }) => {
  await start(page, { size: '5' });
  await expect(page.getByTestId('card-timer')).toHaveText('0.0 s');
  const seen = await playCorrect(page, 5, hepburn, { tick: 500 });
  await expectComplete(page, 5);
  await expect(lives(page)).toHaveAttribute('data-lives', '3');

  for (const id of ['summary-total-time', 'summary-avg-time']) {
    const text = (await page.getByTestId(id).textContent()).trim();
    expect(text, id).toMatch(TIME_RE);
    expect(seconds(text), id).toBeGreaterThan(0);
  }
  // Con el reloj controlado, los tiempos son exactos: 5 × 0.5 s.
  await expect(page.getByTestId('summary-total-time')).toHaveText('2.5 s');
  await expect(page.getByTestId('summary-avg-time')).toHaveText('0.5 s');
  await expect(page.getByTestId('summary-slowest').locator('li')).toHaveCount(3);
  await expect(page.getByTestId('summary-slowest').locator('li')).toHaveText(Array(3).fill(/· 0\.5 s$/));
  await expect(page.getByTestId('summary-errors')).toHaveText('Sin errores');
  await expect(page.getByTestId('summary-record')).toHaveText('¡Nuevo récord! 0.5 s por tarjeta');
  expect(await readJson(page, BEST_KEY)).toEqual({ 'hiragana-basicos-5': 500 });
  expect(new Set(seen).size).toBe(5);

  // «Mis estadísticas» de index.html (hiragana por defecto) contiene exactamente esos 5 kana.
  await page.goto('/');
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
  const cellsKana = page.locator('[data-testid="stats-cell"] .stats-cell__kana');
  await expect(cellsKana).toHaveCount(5);
  expect((await cellsKana.allTextContents()).map((t) => t.trim()).sort()).toEqual([...seen].sort());
  await expect(page.locator('[data-testid="stats-cell"] .stats-cell__rate')).toHaveText(Array(5).fill('0% error'));
});

test('Full de básicos en hiragana con variantes Kunrei y «nn»: 46/46 sin repetidos (FM 29, 30, 32, 33)', async ({ page }) => {
  await choose(page, 'cards-deck-basicos');
  await choose(page, 'cards-size-full');
  await expect(page.locator('#size-full-count')).toHaveText('46');
  await start(page, { size: 'full' });

  const seen = [];
  for (let i = 1; i <= 46; i += 1) {
    await expect(progress(page)).toHaveText(`${i}/46`);
    const kana = await readKana(page);
    seen.push(kana);
    if (kana === 'を') {
      // «o» no es を (FM 33).
      await input(page).fill('o');
      await expectUntouched(page, i, 46);
    }
    await input(page).fill(kunrei(kana));
    await expect(lives(page)).toHaveAttribute('data-lives', '3');
  }
  await expectComplete(page, 46);
  await expect(page.getByTestId('summary-errors')).toHaveText('Sin errores');

  expect(seen).toHaveLength(46);
  expect(new Set(seen).size, 'sin repetidos').toBe(46);
  // Exactamente los 46 básicos: ningún dakuten ni combinado.
  expect([...seen].sort()).toEqual(Object.keys(BASICOS).sort());
});

test('Ambos + Todos + Full: 204 tarjetas únicas (102 + 102) y estadísticas por silabario (FM 29, 30, 31, 32)', async ({ page }) => {
  test.setTimeout(120_000);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await choose(page, 'cards-syllabary-ambos');
  await choose(page, 'cards-deck-todos');
  await expect(page.locator('#size-full-count')).toHaveText('204');
  await start(page, { syl: 'ambos', deck: 'todos', size: 'full' });

  // Hiragana en Kunrei; katakana en Hepburn salvo la fila じゃ, con «jya».
  const answerFor = (kana) => (isKatakana(kana) ? JYA[romajiOf(kana)] ?? hepburn(kana) : kunrei(kana));
  const seen = await playCorrect(page, 204, answerFor);
  await expectComplete(page, 204);
  await expect(lives(page)).toHaveAttribute('data-lives', '3');

  expect(new Set(seen).size, 'sin repetidos').toBe(204);
  const hira = seen.filter((k) => !isKatakana(k)).sort();
  const kata = seen.filter(isKatakana).sort();
  const oracleHira = Object.keys(TODOS).sort();
  expect(hira).toEqual(oracleHira);
  expect(kata).toEqual(oracleHira.map(h.toKatakana).sort());

  const stats = await readJson(page, STATS_KEY);
  const expectedHira = Object.fromEntries(oracleHira.map((k) => [k, { ok: 1, fail: 0 }]));
  const expectedKata = Object.fromEntries(oracleHira.map((k) => [h.toKatakana(k), { ok: 1, fail: 0 }]));
  expect(stats.hiragana).toEqual(expectedHira);
  expect(stats.katakana).toEqual(expectedKata);
  expect(errors).toEqual([]);
});

test('tres errores (dos con Enter, uno con «No la sé»): fin de ronda sin récord y tiempos sin la pausa (FM 34, 36, 37)', async ({ page }) => {
  await start(page, { size: '5' });
  const failed = [];
  for (let n = 1; n <= 3; n += 1) {
    await expect(progress(page)).toHaveText(`${n}/5`);
    await expect(lives(page)).toHaveAttribute('data-lives', String(4 - n));
    const kana = await readKana(page);
    failed.push(kana);
    await page.clock.runFor(300);
    if (n < 3) {
      await input(page).fill(wrongReading(kana));
      await expectUntouched(page, n, 5, 4 - n); // sin Enter todavía no cuenta
      await input(page).press('Enter');
    } else {
      await page.getByTestId('btn-skip').click();
    }
    await expect(lives(page)).toHaveAttribute('data-lives', String(3 - n)); // exactamente una vida menos
    await expect(feedback(page)).toHaveText(`${kana} se lee ${romajiOf(kana)}`);
    await page.clock.runFor(1200);
  }

  await expect(summary(page)).toBeVisible();
  await expect(summary(page)).toHaveAttribute('data-result', 'gameover');
  await expect(page.getByTestId('cards-game')).toBeHidden();
  await expect(lives(page)).toHaveAttribute('data-lives', '0');
  await expect(page.getByTestId('summary-correct')).toHaveText('0/5');
  await expect(page.getByTestId('summary-errors').locator('li')).toHaveText(failed.map((k) => `${k} → ${romajiOf(k)}`));
  // 3 respuestas × 0.3 s: la pausa de 1.2 s tras cada error no cuenta (FM 36).
  await expect(page.getByTestId('summary-total-time')).toHaveText('0.9 s');
  // La media es por acierto: sin aciertos, 0.0 s.
  await expect(page.getByTestId('summary-avg-time')).toHaveText('0.0 s');
  await expect(page.getByTestId('summary-record')).toHaveText('Completa la ronda para registrar un récord.');
  expect(await readJson(page, BEST_KEY)).toBeNull();

  const stats = await readJson(page, STATS_KEY);
  expect(stats.hiragana).toEqual(Object.fromEntries(failed.map((k) => [k, { ok: 0, fail: 1 }])));
});

test('tras un error: romaji correcto, campo deshabilitado y nada de lo escrito en la pausa pasa a la siguiente (FM 34, 35)', async ({ page }) => {
  await start(page, { size: '10' });
  const first = await readKana(page);
  await input(page).fill(wrongReading(first));
  await input(page).press('Enter');

  await expect(feedback(page)).toHaveText(`${first} se lee ${romajiOf(first)}`);
  await expect(input(page)).toBeDisabled();
  await expect(lives(page)).toHaveAttribute('data-lives', '2');
  await expect(progress(page)).toHaveText('1/10');

  // Intentos durante la pausa: teclado, texto inyectado con su evento input, envío del
  // formulario y «No la sé». Nada debe contar.
  await page.keyboard.type('ka');
  await page.keyboard.press('Enter');
  await input(page).evaluate((el) => {
    el.value = 'ka';
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.form.requestSubmit();
  });
  await page.getByTestId('btn-skip').click();
  await expect(lives(page)).toHaveAttribute('data-lives', '2');
  await expect(progress(page)).toHaveText('1/10');

  await page.clock.runFor(1199);
  await expect(progress(page)).toHaveText('1/10');
  await expect(input(page)).toBeDisabled();
  await page.clock.runFor(1);

  await expect(progress(page)).toHaveText('2/10'); // avanza exactamente 1
  await expect(input(page)).toHaveValue('');
  await expect(input(page)).toBeEnabled();
  await expect(input(page)).toBeFocused();
  await expect(feedback(page)).toBeEmpty();
  await expect(lives(page)).toHaveAttribute('data-lives', '2');

  const second = await readKana(page);
  expect(second).not.toBe(first);
  await answerCard(page, hepburn(second));
  await expect(progress(page)).toHaveText('3/10');
  await expect(lives(page)).toHaveAttribute('data-lives', '2');

  const stats = await readJson(page, STATS_KEY);
  expect(stats.hiragana[first]).toEqual({ ok: 0, fail: 1 }); // un solo fallo registrado
  expect(stats.hiragana[second]).toEqual({ ok: 1, fail: 0 });
});

test('sílabas a medio escribir y Enter vacío no cuentan; «ki» no vale ante きゃ (FM 33, 39)', async ({ page }) => {
  await start(page, { deck: 'todos', size: 'full' });
  // Avanza respondiendo bien hasta la primera tarjeta de combinado (dos caracteres).
  let pos = 1;
  let kana = await readKana(page);
  while ([...kana].length !== 2) {
    await answerCard(page, hepburn(kana));
    pos += 1;
    await expect(progress(page)).toHaveText(`${pos}/102`);
    kana = await readKana(page);
  }
  const romaji = romajiOf(kana);
  const bigKanaRomaji = romajiOf([...kana][0]); // ki, shi, chi, ji…

  // Enter con el campo vacío no hace nada (FM 39).
  await input(page).fill('');
  await input(page).press('Enter');
  await expectUntouched(page, pos, 102);

  // Prefijos: genéricos y el de la propia sílaba (ky, sh, ch, j…).
  for (const partial of ['k', 'sh', 'ky', romaji.slice(0, -1), bigKanaRomaji]) {
    await input(page).fill(partial);
    await expectUntouched(page, pos, 102);
    await expect(input(page)).toHaveValue(partial);
  }

  // El kana grande solo (ki ante きゃ) exige Enter y cuenta como error.
  await input(page).press('Enter');
  await expect(lives(page)).toHaveAttribute('data-lives', '2');
  await expect(feedback(page)).toHaveText(`${kana} se lee ${romaji}`);
});

test('«Abandonar» y «Otra ronda» reinician el estado sin temporizadores pendientes (FM 41)', async ({ page }) => {
  await start(page, { size: '5' });
  await answerCard(page, hepburn(await readKana(page)));
  await expect(progress(page)).toHaveText('2/5');
  await page.getByTestId('btn-skip').click();
  await expect(input(page)).toBeDisabled();

  // Abandonar durante la pausa del feedback.
  await page.getByTestId('btn-quit').click();
  await expect(page.getByTestId('cards-config')).toBeVisible();
  await expect(page.getByTestId('cards-game')).toBeHidden();
  await page.getByTestId('btn-start').click();
  await expectUntouched(page, 1, 5);
  await expect(input(page)).toHaveValue('');
  await expect(page.getByTestId('card-timer')).toHaveText('0.0 s');
  await page.clock.runFor(2000); // más que la pausa de 1200 ms de la ronda abandonada
  await expectUntouched(page, 1, 5);
  await expect(page.getByTestId('card-timer')).toHaveText('2.0 s');

  // Perder la ronda y pulsar «Otra ronda».
  for (let n = 1; n <= 3; n += 1) {
    await page.getByTestId('btn-skip').click();
    await page.clock.runFor(1200);
  }
  await expect(summary(page)).toHaveAttribute('data-result', 'gameover');
  await page.getByTestId('btn-again').click();
  await expect(page.getByTestId('cards-game')).toBeVisible();
  await expectUntouched(page, 1, 5);
  await expect(input(page)).toHaveValue('');
  await expect(page.getByTestId('card-timer')).toHaveText('0.0 s');
  await page.clock.runFor(2000);
  await expectUntouched(page, 1, 5);

  // La ronda nueva no arrastra errores ni tiempos de la anterior.
  await playCorrect(page, 5, hepburn, { tick: 100 });
  await expectComplete(page, 5);
  await expect(page.getByTestId('summary-errors')).toHaveText('Sin errores');
  await expect(page.getByTestId('summary-total-time')).toHaveText('2.5 s'); // 2.0 s de espera + 5 × 0.1 s

  await page.getByTestId('btn-config').click();
  await expect(page.getByTestId('cards-config')).toBeVisible();
  await expect(summary(page)).toBeHidden();
});

test('récords: una ronda más lenta no pisa un récord mejor y cada combinación tiene su clave (FM 37, 38)', async ({ page }) => {
  await page.evaluate((k) => localStorage.setItem(k, JSON.stringify({ 'hiragana-basicos-5': 1 })), BEST_KEY);

  await start(page, { syl: 'hiragana', size: '5' });
  await playCorrect(page, 5, hepburn, { tick: 500 });
  await expectComplete(page, 5);
  await expect(page.getByTestId('summary-record')).toHaveText('Récord: 0.0 s por tarjeta');
  expect(await readJson(page, BEST_KEY)).toEqual({ 'hiragana-basicos-5': 1 });

  // Otra combinación: katakana, mismo mazo y tamaño.
  await page.getByTestId('btn-config').click();
  await start(page, { syl: 'katakana', size: '5' });
  await playCorrect(page, 5, hepburn, { tick: 400 });
  await expect(page.getByTestId('summary-record')).toHaveText('¡Nuevo récord! 0.4 s por tarjeta');

  // Otra más: hiragana, tamaño 10.
  await page.getByTestId('btn-config').click();
  await start(page, { syl: 'hiragana', size: '10' });
  await playCorrect(page, 10, hepburn, { tick: 300 });
  await expect(page.getByTestId('summary-record')).toHaveText('¡Nuevo récord! 0.3 s por tarjeta');

  // Repetir la misma combinación más lento no la sobrescribe; más rápido sí.
  await page.getByTestId('btn-again').click();
  await playCorrect(page, 10, hepburn, { tick: 600 });
  await expect(page.getByTestId('summary-record')).toHaveText('Récord: 0.3 s por tarjeta');
  await page.getByTestId('btn-again').click();
  await playCorrect(page, 10, hepburn, { tick: 200 });
  await expect(page.getByTestId('summary-record')).toHaveText('¡Nuevo récord! 0.2 s por tarjeta');

  expect(await readJson(page, BEST_KEY)).toEqual({
    'hiragana-basicos-5': 1,
    'katakana-basicos-5': 400,
    'hiragana-basicos-10': 200,
  });
});

test.describe('sin localStorage', () => {
  // Debe registrarse antes que el init script de openCards (beforeEach externo).
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(window, 'localStorage', {
        configurable: true,
        get() {
          throw new DOMException('bloqueado', 'SecurityError');
        },
      });
    });
    await page.reload();
    await expect(page.getByTestId('btn-start')).toBeVisible();
  });

  test('se juega una ronda de 5 completa sin errores de consola (FM 40)', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
    expect(await page.evaluate(() => { try { return localStorage && 'accesible'; } catch { return 'bloqueado'; } })).toBe('bloqueado');

    await start(page, { size: '5' });
    await playCorrect(page, 5, hepburn, { tick: 500 });
    await expectComplete(page, 5);
    await expect(page.getByTestId('summary-avg-time')).toHaveText('0.5 s');
    expect(errors).toEqual([]);
  });

  test('el resumen no inventa un récord de 0.0 s cuando no se puede guardar (FM 40)', async ({ page }) => {
    await start(page, { size: '5' });
    await playCorrect(page, 5, hepburn, { tick: 500 });
    await expectComplete(page, 5);
    await expect(page.getByTestId('summary-record')).toHaveText('No se pudo guardar el récord en este navegador.');
  });
});

// Juega una ronda Full de básicos hasta que ん salga antes de la última tarjeta.
// Devuelve su posición; si ん sale última, juega otra ronda.
async function advanceToN(page) {
  for (let round = 0; round < 5; round += 1) {
    for (let i = 1; i <= 46; i += 1) {
      await expect(progress(page)).toHaveText(`${i}/46`);
      const kana = await readKana(page);
      if (kana === 'ん' && i < 46) return i;
      await answerCard(page, hepburn(kana));
    }
    await page.getByTestId('btn-again').click();
  }
  throw new Error('ん no apareció antes de la última tarjeta en 5 rondas');
}

test('ん: «nn» tecleado letra a letra acierta y la tarjeta siguiente arranca vacía (FM 32, 33, 35)', async ({ page }) => {
  await start(page, { size: 'full' });
  const pos = await advanceToN(page);
  // Una sola «n» todavía no cuenta: se espera la segunda o Enter.
  await input(page).pressSequentially('n');
  await expectUntouched(page, pos, 46);
  await input(page).pressSequentially('n');
  await expect(progress(page)).toHaveText(`${pos + 1}/46`);
  await expect(input(page)).toHaveValue('');
  await expect(input(page)).toBeEnabled();
  await expect(lives(page)).toHaveAttribute('data-lives', '3');
  expect((await readJson(page, STATS_KEY)).hiragana['ん']).toEqual({ ok: 1, fail: 0 });
});

test('ん: «n» + Enter también es acierto (FM 32)', async ({ page }) => {
  await start(page, { size: 'full' });
  const pos = await advanceToN(page);
  await input(page).pressSequentially('n');
  await input(page).press('Enter');
  await expect(progress(page)).toHaveText(`${pos + 1}/46`);
  await expect(input(page)).toHaveValue('');
  await expect(lives(page)).toHaveAttribute('data-lives', '3');
  await expect(feedback(page)).toBeEmpty();
});

test('la media y el récord cuentan solo los aciertos: un «No la sé» rápido no mejora la media (FM 36, 37)', async ({ page }) => {
  await start(page, { size: '5' });
  await page.clock.runFor(100);
  await page.getByTestId('btn-skip').click();
  await page.clock.runFor(1200);
  await playCorrect(page, 5, hepburn, { from: 2, tick: 500 });
  await expect(summary(page)).toHaveAttribute('data-result', 'complete');
  await expect(page.getByTestId('summary-correct')).toHaveText('4/5');
  await expect(page.getByTestId('summary-total-time')).toHaveText('2.1 s'); // 0.1 + 4 × 0.5
  await expect(page.getByTestId('summary-avg-time')).toHaveText('0.5 s'); // no 0.42
  await expect(page.getByTestId('summary-record')).toHaveText('¡Nuevo récord! 0.5 s por tarjeta');
  expect(await readJson(page, BEST_KEY)).toEqual({ 'hiragana-basicos-5': 500 });
});

test('solo se ve la sección activa y el foco va donde corresponde', async ({ page }) => {
  // Al cargar: solo la configuración.
  await expect(page.getByTestId('cards-config')).toBeVisible();
  await expect(page.getByTestId('cards-game')).toBeHidden();
  await expect(summary(page)).toBeHidden();
  await expect(lives(page)).toHaveAttribute('role', 'img');

  // Juego: la configuración y el resumen quedan ocultos.
  await start(page, { size: '5' });
  await expect(page.getByTestId('cards-config')).toBeHidden();
  await expect(summary(page)).toBeHidden();
  await expect(input(page)).toBeFocused();

  // Abandonar: vuelve solo la configuración, con el foco en «Empezar».
  await page.getByTestId('btn-quit').click();
  await expect(page.getByTestId('cards-config')).toBeVisible();
  await expect(page.getByTestId('cards-game')).toBeHidden();
  await expect(summary(page)).toBeHidden();
  await expect(page.getByTestId('btn-start')).toBeFocused();

  // Terminar la ronda: solo el resumen, con el foco en su título.
  await page.getByTestId('btn-start').click();
  await playCorrect(page, 5);
  await expect(summary(page)).toBeVisible();
  await expect(page.getByTestId('cards-game')).toBeHidden();
  await expect(page.getByTestId('cards-config')).toBeHidden();
  await expect(page.locator('#summary-title')).toBeFocused();

  // Volver a la configuración: foco en «Empezar».
  await page.getByTestId('btn-config').click();
  await expect(page.getByTestId('cards-config')).toBeVisible();
  await expect(summary(page)).toBeHidden();
  await expect(page.getByTestId('cards-game')).toBeHidden();
  await expect(page.getByTestId('btn-start')).toBeFocused();
});

test('navegación entre páginas y sin scroll horizontal a 320 px (configuración, juego y resumen)', async ({ page }, testInfo) => {
  await page.goto('/');
  await page.getByTestId('link-cards').click();
  await expect(page).toHaveURL(/\/tarjetas\.html$/);
  await expect(page.getByTestId('cards-config')).toBeVisible();
  await page.getByTestId('link-reading').click();
  await expect(page).toHaveURL(/\/(index\.html)?$/);
  await expect(page.getByTestId('row-chip-a')).toBeAttached();
  await page.getByTestId('link-cards').click();
  await expect(page.getByTestId('btn-start')).toBeVisible();

  await page.setViewportSize({ width: 320, height: 720 });
  const expectNoOverflow = async (name) => {
    await testInfo.attach(`320px-${name}`, { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
    const { scrollWidth, clientWidth } = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
    }));
    expect(scrollWidth, `ancho del documento (${name})`).toBeLessThanOrEqual(clientWidth);
  };

  await choose(page, 'cards-syllabary-ambos');
  await choose(page, 'cards-deck-todos');
  await expectNoOverflow('configuracion');

  await start(page, { syl: 'ambos', deck: 'todos', size: '5' });
  await page.getByTestId('btn-skip').click();
  await expect(feedback(page)).not.toBeEmpty();
  await expectNoOverflow('juego');

  await page.clock.runFor(1200);
  await page.getByTestId('btn-skip').click();
  await page.clock.runFor(1200);
  await page.getByTestId('btn-skip').click();
  await page.clock.runFor(1200);
  await expect(summary(page)).toHaveAttribute('data-result', 'gameover');
  await expectNoOverflow('resumen');
});

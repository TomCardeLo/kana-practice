// Modo "Texto propio": escenarios 1, 2, 3, 6 y 7 del plan (§7) + modos de fallo de
// translit/check vía la UI.
// Referencias "FM n" = tests/e2e/failure-modes.md.
const { test, expect } = require('@playwright/test');
const h = require('./helpers');

test.beforeEach(async ({ page }) => {
  await h.open(page);
  await h.selectMode(page, 'text');
});

for (const syl of h.SYLLABARIES) {
  test.describe(`${syl}`, () => {
    // Escenario 1: texto libre -> kana esperados -> transcripción perfecta -> N/N.
    const perfectCases = [
      { text: 'gato', kana: ['が', 'と'], romaji: 'gato' },
      { text: 'tres', kana: ['と', 'れ', 'す'], romaji: 'toresu' }, // FM 5
      { text: 'canción', kana: ['か', 'ん', 'し', 'お', 'ん'], romaji: 'kanshion' }, // FM 6, 9
      { text: 'Hola, amigo!', kana: ['お', 'ら', 'あ', 'み', 'ご'], romaji: 'ora amigo' }, // FM 4, 10
    ];
    for (const c of perfectCases) {
      test(`texto libre "${c.text}" -> kana correctos y transcripción perfecta`, async ({ page }) => {
        await h.generate(page, c.text, syl);
        await h.expectKana(page, h.kanaFor(c.kana, syl));
        await h.expectStates(page, c.kana.map(() => 'pending'));
        await h.answer(page, c.romaji);
        await h.expectStates(page, c.kana.map(() => 'ok'));
        await expect(page.getByTestId('score')).toHaveText(`${c.kana.length} / ${c.kana.length} correctos`);
        await expect(page.getByTestId('message')).toBeEmpty();
      });
    }

    test('varias palabras se muestran separadas y la puntuación se descarta', async ({ page }) => {
      await h.generate(page, '¡Hola, amigo! 123', syl);
      await expect(page.locator('.kana-word')).toHaveCount(2);
      await expect(page.locator('.kana-word').nth(0).locator('.kana-cell__kana')).toHaveText(h.kanaFor(['お', 'ら'], syl));
      await expect(page.locator('.kana-word').nth(1).locator('.kana-cell__kana')).toHaveText(h.kanaFor(['あ', 'み', 'ご'], syl));
    });

    // Escenario 2: errores -> solo los kana fallados en rojo, sin cascada (FM 17).
    test('un kana mal escrito marca solo ese kana', async ({ page }) => {
      await h.generate(page, 'zapato', syl); // sa pa to
      await h.answer(page, 'sabato');
      await h.expectStates(page, ['ok', 'error', 'ok']);
      await expect(page.getByTestId('score')).toHaveText('2 / 3 correctos');
      const err = h.cells(page).nth(1);
      await expect(err.locator('.kana-cell__typed')).toHaveText('escribiste: ba');
      await expect(err.locator('.kana-cell__romaji')).toBeVisible();
      await expect(err.locator('.kana-cell__romaji')).toHaveText('pa');
    });

    test('un kana faltante no desalinea el resto de la palabra', async ({ page }) => {
      await h.generate(page, 'manzana', syl); // ma n sa na
      await h.expectKana(page, h.kanaFor(['ま', 'ん', 'さ', 'な'], syl));
      await h.answer(page, 'masana');
      await h.expectStates(page, ['ok', 'error', 'ok', 'ok']);
      await expect(h.cells(page).nth(1).locator('.kana-cell__typed')).toHaveText('falta');
      await expect(page.getByTestId('score')).toHaveText('3 / 4 correctos');
    });

    test('un kana faltante al inicio de una frase larga no provoca cascada', async ({ page }) => {
      await h.generate(page, 'pelota roja', syl); // pe ro ta ro ha
      await h.answer(page, 'rota roha');
      await h.expectStates(page, ['error', 'ok', 'ok', 'ok', 'ok']);
      await expect(page.getByTestId('score')).toHaveText('4 / 5 correctos');
    });

    test('mayúsculas y espacios extra en la respuesta no cuentan como error', async ({ page }) => {
      await h.generate(page, 'gato', syl);
      await h.answer(page, '   GaTo   ');
      await h.expectStates(page, ['ok', 'ok']);
    });

    test('letras sueltas sin convertir se marcan como error (FM 19)', async ({ page }) => {
      await h.generate(page, 'gato', syl);
      await h.answer(page, 'gak');
      await h.expectStates(page, ['ok', 'error']);
      await expect(page.getByTestId('score')).toHaveText('1 / 2 correctos');
    });

    // Escenario 3: variantes aceptadas (FM 16).
    test('variantes si/ti/tu/hu/zi/di se aceptan', async ({ page }) => {
      await h.generate(page, 'sitio tuna fumar dime canto', syl);
      await h.expectKana(
        page,
        h.kanaFor(['し', 'ち', 'お', 'つ', 'な', 'ふ', 'ま', 'る', 'じ', 'め', 'か', 'ん', 'と'], syl)
      );
      await h.answer(page, 'sitio tuna humaru zime kanto');
      await expect(page.getByTestId('score')).toHaveText('13 / 13 correctos');
      await h.answer(page, 'shichio tsuna fumaru dime kanto');
      await expect(page.getByTestId('score')).toHaveText('13 / 13 correctos');
    });

    test('combinaciones ゃゅょ son un solo kana y aceptan variantes (FM 15)', async ({ page }) => {
      await h.generate(page, 'niño chocolate', syl); // ni nyo / cho ko ra te
      await h.expectKana(page, h.kanaFor(['に', 'にょ', 'ちょ', 'こ', 'ら', 'て'], syl));
      await h.answer(page, 'ninyo tyokorate');
      await expect(page.getByTestId('score')).toHaveText('6 / 6 correctos');
    });

    // ん antes de vocal entre palabras (FM 7): "pan agua" -> ぱん あぐあ.
    test("ん seguida de vocal: n' (apóstrofo) se acepta", async ({ page }) => {
      await h.generate(page, 'pan agua', syl);
      await h.expectKana(page, h.kanaFor(['ぱ', 'ん', 'あ', 'ぐ', 'あ'], syl));
      await h.answer(page, "pan'agua");
      await expect(page.getByTestId('score')).toHaveText('5 / 5 correctos');
    });

    test('variante nn para ん se acepta sin marcar sobrantes (plan §4 n/nn)', async ({ page }) => {
      await h.generate(page, 'canto', syl);
      await h.answer(page, 'kannto');
      await expect(page.getByTestId('score')).toHaveText('3 / 3 correctos');
      await h.generate(page, 'canna'); // ka n na: "kanna" no debe reducirse
      await h.expectKana(page, h.kanaFor(['か', 'ん', 'な'], syl));
      await h.answer(page, 'kanna');
      await expect(page.getByTestId('score')).toHaveText('3 / 3 correctos');
      await h.generate(page, 'pan agua');
      await h.answer(page, 'pann agua');
      await expect(page.getByTestId('score')).toHaveText('5 / 5 correctos');
    });

    test('ん seguida de vocal: separar palabras con espacio basta', async ({ page }) => {
      await h.generate(page, 'pan agua', syl);
      await h.answer(page, 'pan agua');
      await h.expectStates(page, ['ok', 'ok', 'ok', 'ok', 'ok']);
      await expect(page.getByTestId('score')).toHaveText('5 / 5 correctos');
    });

    test('kana sobrantes se informan en el marcador sin marcar error', async ({ page }) => {
      await h.generate(page, 'gato', syl);
      await h.answer(page, 'gatototo');
      await h.expectStates(page, ['ok', 'ok']);
      await expect(page.getByTestId('score')).toHaveText('2 / 2 correctos · 2 sobrantes');
      await h.answer(page, 'gaatok');
      await expect(page.getByTestId('score')).toHaveText('2 / 2 correctos · 2 sobrantes');
    });

    test('Enter hace salto de línea y no corrige; Control+Enter corrige', async ({ page }) => {
      await h.generate(page, 'gato', syl);
      const input = page.getByTestId('input-answer');
      await input.fill('ga');
      await input.press('Enter');
      await input.pressSequentially('to');
      await expect(input).toHaveValue('ga\nto');
      await expect(page.getByTestId('score')).toBeEmpty();
      await h.expectStates(page, ['pending', 'pending']);
      await input.press('Control+Enter');
      await expect(page.getByTestId('score')).toHaveText('2 / 2 correctos');
    });

    test('párrafo de varias líneas: un bloque por línea y transcripción multilínea perfecta', async ({ page }) => {
      await h.generate(page, 'Hola amigo,\nel gato\n\nsol rojo.', syl);
      const lines = page.locator('#kana-output .kana-line');
      await expect(lines).toHaveCount(4); // la línea vacía se conserva como separación
      const wordsPerLine = await lines.evaluateAll((els) => els.map((l) => l.querySelectorAll('.kana-word').length));
      expect(wordsPerLine).toEqual([2, 2, 0, 2]);
      await expect(lines.nth(1).locator('.kana-cell__kana')).toHaveText(h.kanaFor(['え', 'る', 'が', 'と'], syl));
      // Los bloques de líneas distintas quedan en posiciones verticales distintas.
      const tops = await lines.evaluateAll((els) => els.map((l) => l.getBoundingClientRect().top));
      expect(tops[1]).toBeGreaterThan(tops[0]);
      expect(tops[3]).toBeGreaterThan(tops[1]);

      await page.getByTestId('input-answer').fill('ora amigo\neru gato\n\nsoru roho');
      await page.getByTestId('btn-check').click();
      await expect(page.getByTestId('score')).toHaveText('13 / 13 correctos');
    });

    // Escenario 6: el romaji no se ve antes de corregir o de pedir la solución.
    test('el romaji está oculto hasta corregir o mostrar la solución', async ({ page }) => {
      await h.generate(page, 'zapato rojo', syl);
      const romaji = page.locator('[data-testid="kana-cell"] .kana-cell__romaji');
      await expect(romaji).toHaveCount(5);
      for (const r of await romaji.all()) await expect(r).toBeHidden();
      const visibleText = await page.getByTestId('kana-output').innerText();
      expect(visibleText).not.toMatch(/[a-z]/);

      // Tras corregir: solo los errores revelan su romaji.
      await h.answer(page, 'sapato roho');
      await expect(romaji.nth(0)).toBeHidden();
      await expect(romaji.nth(4)).toBeHidden();
      await h.answer(page, 'sapato rofu');
      await expect(romaji.nth(4)).toBeVisible();
      await expect(romaji.nth(0)).toBeHidden();

      await page.getByTestId('btn-solution').click();
      for (const r of await romaji.all()) await expect(r).toBeVisible();
      await expect(romaji).toHaveText(['sa', 'pa', 'to', 'ro', 'ho']);

      // Una nueva práctica vuelve a ocultar la solución.
      await h.generate(page, 'gato');
      await expect(romaji.nth(0)).toBeHidden();
    });

    // Escenario 7: entradas vacías.
    test('texto vacío o sin letras avisa y no genera práctica (FM 11)', async ({ page }) => {
      await h.selectSyllabary(page, syl);
      for (const text of ['', '    ', '¡! 123 ...']) {
        await h.generate(page, text);
        await expect(page.getByTestId('message')).toHaveText('Escribe un texto en español para generar la práctica.');
        await expect(h.cells(page)).toHaveCount(0);
      }
    });

    test('respuesta vacía avisa y no corrige (FM 20)', async ({ page }) => {
      await h.answer(page, 'gato');
      await expect(page.getByTestId('message')).toHaveText('Primero genera una práctica.');
      await h.generate(page, 'gato', syl);
      await expect(page.getByTestId('message')).toBeEmpty();
      await h.answer(page, '   ');
      await expect(page.getByTestId('message')).toHaveText('Escribe tu transcripción antes de corregir.');
      await h.expectStates(page, ['pending', 'pending']);
      await expect(page.getByTestId('score')).toBeEmpty();
    });
  });
}

// Modos de fallo de translit.js (FM 1-12) comprobados a través de la UI, en ambos silabarios.
const TRANSLIT = [
  ['leche', ['れ', 'ち', 'え']], // ch (FM 1)
  ['coche', ['こ', 'ち', 'え']],
  ['llave', ['や', 'べ']], // ll
  ['perro', ['ぺ', 'ろ']], // rr
  ['queso', ['け', 'そ']], // qu
  ['guitarra', ['ぎ', 'た', 'ら']], // gu + i (FM 3)
  ['guerra', ['げ', 'ら']],
  ['cine', ['し', 'ね']], // c + i (FM 2)
  ['gente', ['へ', 'ん', 'て']], // g + e
  ['hola', ['お', 'ら']], // h muda (FM 4)
  ['huevo', ['う', 'え', 'ぼ']],
  ['sol', ['そ', 'る']], // consonante final (FM 6)
  ['red', ['れ', 'ど']],
  ['plato', ['ぷ', 'ら', 'と']], // grupo consonántico (FM 5)
  ['pan', ['ぱ', 'ん']], // n final
  ['luna', ['る', 'な']], // n + vocal no es ん (FM 7)
  ['jugo', ['ふ', 'ご']],
  ['taxi', ['た', 'く', 'し']],
  ['rey', ['れ', 'い']], // y final (FM 12)
  ['tina', ['ち', 'な']], // ti (FM 8)
  ['foto', ['ふ', 'お', 'と']], // fo (FM 8)
  ['ÁRBOL', ['あ', 'る', 'ぼ', 'る']], // mayúsculas + tildes (FM 9, 10)
  ['pingüino', ['ぴ', 'ん', 'ぐ', 'い', 'の']], // güi: la u suena
  ['cigüeña', ['し', 'ぐ', 'え', 'にゃ']], // güe
];

for (const syl of h.SYLLABARIES) {
  test(`${syl}: dígrafos, h muda, consonantes finales y n se adaptan bien`, async ({ page }) => {
    await h.selectSyllabary(page, syl);
    await h.generate(page, TRANSLIT.map(([w]) => w).join(' '));
    const words = page.locator('.kana-word');
    await expect(words).toHaveCount(TRANSLIT.length);
    for (let i = 0; i < TRANSLIT.length; i += 1) {
      const [word, kana] = TRANSLIT[i];
      await expect(words.nth(i).locator('.kana-cell__kana'), `palabra "${word}"`).toHaveText(h.kanaFor(kana, syl));
    }
  });
}

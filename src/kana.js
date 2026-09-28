// Convierte sílabas romaji (de translit.js) en unidades de kana usando wanakana.
import * as wanakana from './../vendor/wanakana-5.3.1.js';

// Filas del silabario, con un kana de ejemplo (en hiragana) para mostrar en la UI de filtros.
export const ROWS = [
  { id: 'a', label: 'A', example: 'あ' },
  { id: 'ka', label: 'KA', example: 'か' },
  { id: 'sa', label: 'SA', example: 'さ' },
  { id: 'ta', label: 'TA', example: 'た' },
  { id: 'na', label: 'NA', example: 'な' },
  { id: 'ha', label: 'HA', example: 'は' },
  { id: 'ma', label: 'MA', example: 'ま' },
  { id: 'ya', label: 'YA', example: 'や' },
  { id: 'ra', label: 'RA', example: 'ら' },
  { id: 'wa', label: 'WA/N', example: 'わ' },
  { id: 'ga', label: 'GA', example: 'が' },
  { id: 'za', label: 'ZA', example: 'ざ' },
  { id: 'da', label: 'DA', example: 'だ' },
  { id: 'ba', label: 'BA', example: 'ば' },
  { id: 'pa', label: 'PA', example: 'ぱ' },
  { id: 'kya', label: 'KYA', example: 'きゃ' },
  { id: 'sha', label: 'SHA', example: 'しゃ' },
  { id: 'cha', label: 'CHA', example: 'ちゃ' },
  { id: 'nya', label: 'NYA', example: 'にゃ' },
  { id: 'hya', label: 'HYA', example: 'ひゃ' },
  { id: 'mya', label: 'MYA', example: 'みゃ' },
  { id: 'rya', label: 'RYA', example: 'りゃ' },
  { id: 'gya', label: 'GYA', example: 'ぎゃ' },
  { id: 'ja', label: 'JA', example: 'じゃ' },
  { id: 'bya', label: 'BYA', example: 'びゃ' },
  { id: 'pya', label: 'PYA', example: 'ぴゃ' },
];

// Romaji -> fila.
const SYLLABLE_ROW = {
  a: 'a', i: 'a', u: 'a', e: 'a', o: 'a',
  ka: 'ka', ki: 'ka', ku: 'ka', ke: 'ka', ko: 'ka',
  sa: 'sa', shi: 'sa', su: 'sa', se: 'sa', so: 'sa',
  ta: 'ta', chi: 'ta', tsu: 'ta', te: 'ta', to: 'ta',
  na: 'na', ni: 'na', nu: 'na', ne: 'na', no: 'na',
  ha: 'ha', hi: 'ha', fu: 'ha', he: 'ha', ho: 'ha',
  ma: 'ma', mi: 'ma', mu: 'ma', me: 'ma', mo: 'ma',
  ya: 'ya', yu: 'ya', yo: 'ya',
  ra: 'ra', ri: 'ra', ru: 'ra', re: 'ra', ro: 'ra',
  wa: 'wa', wo: 'wa', n: 'wa',
  ga: 'ga', gi: 'ga', gu: 'ga', ge: 'ga', go: 'ga',
  za: 'za', ze: 'za', zo: 'za',
  da: 'da', ji: 'za', zu: 'za', de: 'da', do: 'da',
  ba: 'ba', bi: 'ba', bu: 'ba', be: 'ba', bo: 'ba',
  pa: 'pa', pi: 'pa', pu: 'pa', pe: 'pa', po: 'pa',
  kya: 'kya', kyu: 'kya', kyo: 'kya',
  sha: 'sha', shu: 'sha', sho: 'sha',
  cha: 'cha', chu: 'cha', cho: 'cha',
  nya: 'nya', nyu: 'nya', nyo: 'nya',
  hya: 'hya', hyu: 'hya', hyo: 'hya',
  mya: 'mya', myu: 'mya', myo: 'mya',
  rya: 'rya', ryu: 'rya', ryo: 'rya',
  gya: 'gya', gyu: 'gya', gyo: 'gya',
  ja: 'ja', ju: 'ja', jo: 'ja',
  bya: 'bya', byu: 'bya', byo: 'bya',
  pya: 'pya', pyu: 'pya', pyo: 'pya',
};

// Filas de los kana "básicos" (a-n, sin dakuten/handakuten ni combinados きゃ...) para el
// minijuego de tarjetas.
const BASIC_ROWS = new Set(['a', 'ka', 'sa', 'ta', 'na', 'ha', 'ma', 'ya', 'ra', 'wa']);

// Mazo de tarjetas { romaji, kana, silabario } para el minijuego de tarjetas.js, construido
// desde SYLLABLE_ROW (sin lista nueva a mano): "basicos" son las filas a-n, "todos" el
// silabario completo.
export function cardDeck(silabario, mazo) {
  return Object.entries(SYLLABLE_ROW)
    .filter(([, rowId]) => mazo === 'todos' || BASIC_ROWS.has(rowId))
    .map(([romaji]) => ({ romaji, kana: silabaAKana(romaji, silabario), silabario }));
}

// Fila a la que pertenece una sílaba romaji ("n" y "wo" viven en la fila わ).
export function rowOf(romaji) {
  return SYLLABLE_ROW[romaji] || 'a';
}

function silabaAKana(romaji, silabario) {
  if (romaji === 'n') return silabario === 'katakana' ? 'ン' : 'ん';
  return silabario === 'katakana' ? wanakana.toKatakana(romaji) : wanakana.toHiragana(romaji);
}

// palabras de sílabas romaji -> palabras de unidades { romaji, kana, row }.
export function toUnits(palabrasSilabas, silabario) {
  return palabrasSilabas.map((silabas) =>
    silabas.map((romaji) => ({
      romaji,
      kana: silabaAKana(romaji, silabario),
      row: rowOf(romaji),
    }))
  );
}

// Kana de ejemplo de una fila, en el silabario activo (para los chips de filtro).
export function rowExample(rowId, silabario) {
  const fila = ROWS.find((r) => r.id === rowId);
  if (!fila) return '';
  return silabario === 'katakana' ? wanakana.toKatakana(fila.example) : fila.example;
}

// Agrupa las sílabas romaji que usa la app por fila (para la tabla del tutorial). Reutiliza
// SYLLABLE_ROW en vez de mantener una lista aparte, así no se puede desincronizar.
export function syllablesByRow() {
  const grupos = {};
  for (const [romaji, rowId] of Object.entries(SYLLABLE_ROW)) {
    (grupos[rowId] || (grupos[rowId] = [])).push(romaji);
  }
  return grupos;
}

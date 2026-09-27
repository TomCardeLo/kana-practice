// Convierte texto en español a sílabas romaji canónicas (kana básico: gojūon + dakuten + ゃゅょ).
// No traduce nada: es una adaptación fonética letra por letra.

const VOWELS = new Set(['a', 'e', 'i', 'o', 'u']);

// Reescritura ortográfica del español, en orden de prioridad (dígrafos antes que letras sueltas).
// 'G' es un marcador temporal para la "g" dura de gue/gui (u muda), para no confundirla
// con la "g" blanda de ge/gi (que suena como "j").
const REWRITES = [
  [/qu/g, 'k'],
  [/q/g, 'k'],
  [/gu([ei])/g, 'G$1'],
  [/ch/g, 'C'],
  [/ll/g, 'y'],
  [/rr/g, 'r'],
  [/l/g, 'r'],
  [/g([ei])/g, 'j$1'],
  [/c([ei])/g, 's$1'],
  [/c/g, 'k'],
  [/z/g, 's'],
  [/v/g, 'b'],
  [/h/g, ''],
  [/G/g, 'g'],
  // "ü" ya cumplió su papel (evitar que gue/gui la traten como u muda);
  // de aquí en más se procesa como una "u" normal (gu + vocal, no colapsada).
  [/ü/g, 'u'],
];

// Combinaciones irregulares consonante + vocal. Si no hay entrada, se usa el patrón por
// defecto (etiqueta de la consonante + vocal). Un valor array produce varias sílabas.
const COMBINE = {
  s: { i: 'shi' },
  t: { i: 'chi', u: 'tsu' },
  d: { i: 'ji', u: 'zu' },
  j: { a: 'ha', i: 'hi', u: 'fu', e: 'he', o: 'ho' },
  f: { a: ['fu', 'a'], e: ['fu', 'e'], i: ['fu', 'i'], o: ['fu', 'o'], u: 'fu' },
  y: { e: ['i', 'e'], i: ['i'] },
  ñ: { a: 'nya', e: ['ni', 'e'], i: ['ni'], o: 'nyo', u: 'nyu' },
  C: { e: ['chi', 'e'], i: 'chi' },
  w: { a: 'wa', e: ['u', 'e'], i: ['u', 'i'], o: ['u', 'o'], u: 'u' },
  x: { a: ['ku', 'sa'], e: ['ku', 'se'], i: ['ku', 'shi'], o: ['ku', 'so'], u: ['ku', 'su'] },
};

// Etiqueta romaji por defecto de cada consonante (para el patrón "consonante + vocal").
const LABEL = { b: 'b', d: 'd', g: 'g', k: 'k', m: 'm', p: 'p', r: 'r', s: 's', t: 't', y: 'y', C: 'ch', f: 'f', w: 'w' };

function combine(consonante, vocal) {
  const especial = COMBINE[consonante] && COMBINE[consonante][vocal];
  if (especial) return Array.isArray(especial) ? especial : [especial];
  const etiqueta = LABEL[consonante] || consonante;
  return [etiqueta + vocal];
}

// Consonante sin vocal siguiente (grupo consonántico o final de palabra).
// Regla general: + "u", salvo t/d que suman "o". Casos irregulares aparte.
function consonanteSuelta(consonante) {
  if (consonante === 'y') return ['i'];
  if (consonante === 'j') return ['fu'];
  if (consonante === 'ñ') return ['ni'];
  if (consonante === 'x') return ['ku', 'su'];
  if (consonante === 't') return ['to'];
  if (consonante === 'd') return ['do'];
  const etiqueta = LABEL[consonante] || consonante;
  return [`${etiqueta}u`];
}

// Minúsculas, quita tildes, conserva "ñ" y "ü" (se protegen antes de la normalización
// NFD para que no se descompongan junto con los acentos: "ü" debe seguir siendo distinta
// de "u" para que güe/güi no se confundan con gue/gui, que sí llevan la "u" muda).
function normalizar(texto) {
  return texto
    .toLowerCase()
    // NFC primero: si "ñ"/"ü" llegan descompuestos (n/u + diacrítico combinante), los junta
    // en un solo carácter precompuesto antes de protegerlos, si no el reemplazo literal de
    // abajo no los reconoce.
    .normalize('NFC')
    .replace(/ñ/g, '\u0001')
    .replace(/ü/g, '\u0002')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/\u0001/g, 'ñ')
    .replace(/\u0002/g, 'ü');
}

function reescribir(palabra) {
  return REWRITES.reduce((resultado, [patron, reemplazo]) => resultado.replace(patron, reemplazo), palabra);
}

function parsear(fonemico) {
  const letras = [...fonemico];
  const silabas = [];
  let i = 0;
  while (i < letras.length) {
    const actual = letras[i];
    if (VOWELS.has(actual)) {
      silabas.push(actual);
      i += 1;
      continue;
    }
    const siguiente = letras[i + 1];
    if (actual === 'n') {
      if (siguiente && VOWELS.has(siguiente)) {
        silabas.push('n' + siguiente);
        i += 2;
      } else {
        silabas.push('n');
        i += 1;
      }
      continue;
    }
    if (siguiente && VOWELS.has(siguiente)) {
      silabas.push(...combine(actual, siguiente));
      i += 2;
      continue;
    }
    silabas.push(...consonanteSuelta(actual));
    i += 1;
  }
  return silabas;
}

// texto en español -> array de palabras, cada una como array de sílabas romaji canónicas.
// Números, puntuación y emojis se descartan (separan palabras en vez de romperlas).
export function toSyllables(texto) {
  const normalizado = normalizar(texto);
  const palabras = normalizado.split(/[^a-zñü]+/).filter(Boolean);
  return palabras.map((palabra) => parsear(reescribir(palabra)));
}

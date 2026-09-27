// Corrección kana por kana de la respuesta del usuario (en romaji) contra las unidades
// esperadas, usando alineación por distancia de edición para no desalinear la palabra
// completa cuando falta o sobra un kana.
import * as wanakana from './../vendor/wanakana-5.3.1.js';

const YOON_PEQUENOS = new Set(['ゃ', 'ゅ', 'ょ']);

// ぢ/づ se consideran el mismo kana que じ/ず (variantes de escritura del mismo sonido).
function canonizar(hiragana) {
  return hiragana.replace(/ぢ/g, 'じ').replace(/づ/g, 'ず');
}

// Divide un texto ya convertido a hiragana en unidades: un kana grande + su ゃゅょ si lo tiene.
// Las letras latinas que quedaron sin convertir son, cada una, una unidad inválida.
function tokenizar(hiraganaTexto) {
  const unidades = [];
  for (const caracter of canonizar(hiraganaTexto)) {
    if (YOON_PEQUENOS.has(caracter) && unidades.length > 0) {
      unidades[unidades.length - 1] += caracter;
    } else {
      unidades.push(caracter);
    }
  }
  return unidades;
}

// Distancia de edición con backtrace: alinea la secuencia esperada con la escrita.
// Ante empate se prioriza sustitución/coincidencia por sobre inserción/borrado, para que
// cada unidad esperada quede emparejada con algo escrito (mejor feedback que un simple "falta").
function alinear(esperado, escrito) {
  const n = esperado.length;
  const m = escrito.length;
  const dist = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = 0; i <= n; i += 1) dist[i][0] = i;
  for (let j = 0; j <= m; j += 1) dist[0][j] = j;
  for (let i = 1; i <= n; i += 1) {
    for (let j = 1; j <= m; j += 1) {
      const costo = esperado[i - 1] === escrito[j - 1] ? 0 : 1;
      dist[i][j] = Math.min(
        dist[i - 1][j - 1] + costo,
        dist[i - 1][j] + 1,
        dist[i][j - 1] + 1
      );
    }
  }

  const pares = [];
  let i = n;
  let j = m;
  while (i > 0 || j > 0) {
    const costo = i > 0 && j > 0 ? (esperado[i - 1] === escrito[j - 1] ? 0 : 1) : Infinity;
    if (i > 0 && j > 0 && dist[i][j] === dist[i - 1][j - 1] + costo) {
      pares.unshift({ esperado: esperado[i - 1], escrito: escrito[j - 1] });
      i -= 1;
      j -= 1;
    } else if (i > 0 && dist[i][j] === dist[i - 1][j] + 1) {
      pares.unshift({ esperado: esperado[i - 1], escrito: null });
      i -= 1;
    } else {
      pares.unshift({ esperado: null, escrito: escrito[j - 1] });
      j -= 1;
    }
  }
  return pares;
}

// Algunos usuarios escriben "nn" (doblada) para marcar la ん antes de consonante, en vez
// del "n'" que espera wanakana. Sin normalizar, "kannto" produce かんんと (una ん de sobra).
// Solo se reduce cuando "nn" no tiene una sílaba siguiente que la reclame: si va seguida de
// vocal o "y" ("kanna" -> かんな, kan+na) se deja intacta, es una palabra distinta.
function normalizarNN(palabra) {
  return palabra.replace(/nn(?=[^aeiouy]|$)/g, "n'");
}

// Cuenta cuántas unidades kana completas lleva escritas el usuario, con la misma
// normalización/tokenización que checkAnswer (para el indicador «is-current» mientras
// escribe). No cuenta una letra latina final incompleta (todavía sin convertir a kana):
// wanakana deja sin tocar la última letra de una palabra en construcción ("ka" -> か,
// pero "k" queda como "k"), así que se descarta si el fragmento final no es kana.
export function countTypedUnits(respuesta) {
  const normalizada = respuesta.toLowerCase().trim().replace(/\s+/g, ' ');
  if (!normalizada) return 0;
  const hiraganaEscrito = normalizada
    .split(' ')
    .filter(Boolean)
    .map((palabra) => wanakana.toHiragana(normalizarNN(palabra)))
    .join('');
  // Las letras latinas del final son una sílaba a medio escribir (k, sh, ts…): no cuentan.
  const completo = hiraganaEscrito.replace(/[^぀-ヿ]+$/, '');
  return completo ? tokenizar(completo).length : 0;
}

// Corrige la respuesta contra las palabras esperadas ya filtradas por fila activa
// (array de palabras, cada una un array de unidades { romaji, kana, row }).
// Devuelve null si la respuesta está vacía (no se corrige nada).
export function checkAnswer(expectedWords, respuesta) {
  const normalizada = respuesta.toLowerCase().trim().replace(/\s+/g, ' ');
  if (!normalizada) return null;

  const esperadoPlano = expectedWords.flat();
  const kanaEsperado = esperadoPlano.map((unidad) => canonizar(wanakana.toHiragana(unidad.romaji)));
  // Convierte cada palabra por separado (no la respuesta entera junta): así una "n" al final
  // de una palabra no se funde con la vocal inicial de la siguiente ("pan agua" -> ぱん + あぐあ,
  // no ぱなぐあ).
  const hiraganaEscrito = normalizada
    .split(' ')
    .filter(Boolean)
    .map((palabra) => wanakana.toHiragana(normalizarNN(palabra)))
    .join('');
  const kanaEscrito = tokenizar(hiraganaEscrito);

  const paresCompletos = alinear(kanaEsperado, kanaEscrito);
  const extra = paresCompletos.filter((par) => par.esperado === null).length;
  const pares = paresCompletos.filter((par) => par.esperado !== null);

  let cursor = 0;
  let correct = 0;
  const words = expectedWords.map((word) =>
    word.map((unidad) => {
      const par = pares[cursor];
      cursor += 1;
      const ok = par.escrito !== null && par.escrito === par.esperado;
      if (ok) correct += 1;
      const typed = par.escrito === null ? null : wanakana.toRomaji(par.escrito);
      return { ...unidad, ok, typed };
    })
  );

  return { words, correct, total: esperadoPlano.length, extra };
}

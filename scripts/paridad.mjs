// Genera ios/Paridad/paridad.json: salidas reales de los módulos JS (translit, kana, check, wanakana)
// para un conjunto fijo de entradas. ios/scripts/paridad.sh compara el port Swift contra este archivo.
// Uso: npm run paridad
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import * as wanakana from '../vendor/wanakana-5.3.1.js';
import { toSyllables } from '../src/translit.js';
import { toUnits, cardDeck } from '../src/kana.js';
import { checkAnswer, isCorrectReading, countTypedUnits } from '../src/check.js';

const palabras = readFileSync(new URL('../src/words.js', import.meta.url), 'utf8')
  .match(/'[^']+'/g).map((s) => s.slice(1, -1));
const textos = [...palabras, 'Hola, ¿qué tal? 123', 'canción ñandú pingüino guerra', 'Ü ÑÑ ch rr ll qu',
  'rey y ley', 'examen taxi', 'whisky wifi', 'cielo gente guitarra', '  ', '😀 casa', 'atlántico adjetivo'];

const romajis = ['shi', 'si', 'chi', 'ti', 'tsu', 'tu', 'fu', 'hu', 'ji', 'zi', 'di', 'du', 'zu', 'sha', 'sya',
  'cha', 'tya', 'cya', 'ja', 'jya', 'zya', 'dya', 'n', 'nn', "n'", 'kan', "kan'yu", 'konyu', 'kannto', 'kanto',
  'kanna', 'wo', 'k', 'ky', 'sh', 'ts', 'kak', 'kka', 'tta', 'cchi', 'ppu', 'ssha', 'pan', 'agua', 'nya',
  'kya', 'gya', 'bya', 'pya', 'rya', 'mya', 'hya', 'nyu', 'xa', 'la', 'li', 'ca', 'ce', 'qa', 'va', 'fa',
  'je', 'ye', 'wi', 'we', 'a-i', 'kya ku', 'shinbun', 'tenpura', 'onna', 'konnichiha', 'ou', 'oo', 'x', 'q',
  'nka', 'nna', 'KA', 'Shi', ''];

const hiraganaUnits = [...new Set([...cardDeck('hiragana', 'todos'), ...cardDeck('katakana', 'todos')]
  .map((c) => c.kana)), 'ぢ', 'づ', 'を', 'ゃ', 'っ'];

const respuestas = [
  ['casa', 'kasa'], ['casa', 'kaza'], ['casa', 'ka'], ['casa', 'kasasa'], ['tres', 'toresu'],
  ['tres', 'tresu'], ['canción', 'kanshion'], ['canción', 'kannshion'], ['canción', 'kansion'],
  ['pan agua', 'pan agua'], ['pan agua', 'panagua'], ['luna', 'runa'], ['luna', 'RUNA  '],
  ['jugo', 'hugo'], ['niño', 'ninyo'], ['niño', "nin'yo"], ['hola', 'k'], ['hola', ''], ['leche', 'reche'],
  ['leche', 'retye'], ['chico', 'chiko'], ['jugo', 'fugo'], ['perro gato', 'pero gato'],
];

const salida = {
  translit: textos.map((t) => ({ entrada: t, silabas: toSyllables(t) })),
  toHiragana: romajis.map((r) => ({ entrada: r, salida: wanakana.toHiragana(r) })),
  toKatakana: romajis.map((r) => ({ entrada: r, salida: wanakana.toKatakana(r) })),
  toRomaji: hiraganaUnits.map((k) => ({ entrada: k, salida: wanakana.toRomaji(k) })),
  units: ['hiragana', 'katakana'].flatMap((s) =>
    textos.slice(-12).map((t) => ({ entrada: t, silabario: s, units: toUnits(toSyllables(t), s) }))),
  deck: ['hiragana', 'katakana'].flatMap((s) => ['basicos', 'todos'].map((m) =>
    ({ silabario: s, mazo: m, cartas: cardDeck(s, m) }))),
  isCorrectReading: cardDeck('hiragana', 'todos').flatMap((c) =>
    romajis.map((r) => ({ romaji: c.romaji, escrito: r, ok: isCorrectReading(c.romaji, r) })))
    .filter((x, i) => x.ok || i % 7 === 0),
  countTypedUnits: romajis.map((r) => ({ entrada: r, n: countTypedUnits(r) })),
  checkAnswer: respuestas.map(([texto, resp]) => ({
    texto, respuesta: resp, resultado: checkAnswer(toUnits(toSyllables(texto), 'hiragana'), resp),
  })),
};

mkdirSync(new URL('../ios/Paridad/', import.meta.url), { recursive: true });
writeFileSync(new URL('../ios/Paridad/paridad.json', import.meta.url), JSON.stringify(salida, null, 1));
console.log('ios/Paridad/paridad.json:', Object.entries(salida).map(([k, v]) => `${k}=${v.length}`).join(' '));

// Construye las listas de la fase 4 a partir de fuentes abiertas y fijadas, sin red al construir:
//   datos/fuentes/n5.csv        open-anki-jlpt-decks (MIT; lista de Jonathan Waller, tanos.co.uk), commit fijado abajo
//   datos/fuentes/JMdict.gz     JMdict (EDRDG, CC BY-SA 4.0): significados en español e inglés
//   datos/fuentes/kanjidic2.xml.gz  KANJIDIC2 (EDRDG, CC BY-SA 4.0): kanji del antiguo nivel 4 (≈ N5), lecturas, significados
//   datos/traducciones-claude.json  significados en español que JMdict/KANJIDIC2 no traen, traducidos con Claude y
//                                   marcados como tales para revisión
//   datos/revision-claude.json      revisión de Claude del español de JMdict/KANJIDIC2 contra el significado de la
//                                   lista: si lo marca (otro sentido, regionalismo, restos como «(eng: …)»), se usa su
//                                   sugerencia y se guarda el original para que el usuario lo vea
// Salida: datos/vocabulario-n5.json y datos/kanji-n5.json. Uso: node scripts/vocab/construir.mjs [--descargar]
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

export const OPEN_ANKI_COMMIT = '1ad66734417aca9dbcca6b2d5ee440cb13ab3ba0';
const FUENTES = new URL('../../datos/fuentes/', import.meta.url);
const DATOS = new URL('../../datos/', import.meta.url);
const URLS = {
  'n5.csv': `https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/${OPEN_ANKI_COMMIT}/src/n5.csv`,
  'JMdict.gz': 'http://ftp.edrdg.org/pub/Nihongo/JMdict.gz',
  'kanjidic2.xml.gz': 'http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz',
};

mkdirSync(FUENTES, { recursive: true });
for (const [archivo, url] of Object.entries(URLS)) {
  const ruta = new URL(archivo, FUENTES);
  if (process.argv.includes('--descargar') || !existsSync(ruta)) {
    console.log(`descargando ${url}`);
    execFileSync('curl', ['-sfL', '--max-time', '600', '-o', ruta.pathname, url]);
  }
}

// --- CSV (comillas dobles con comas dentro) ---
function filasCsv(texto) {
  const filas = [];
  for (const linea of texto.split(/\r?\n/).filter(Boolean)) {
    const campos = [];
    let actual = '', entre = false;
    for (let i = 0; i < linea.length; i++) {
      const c = linea[i];
      if (c === '"' && linea[i + 1] === '"' && entre) { actual += '"'; i++; }
      else if (c === '"') entre = !entre;
      else if (c === ',' && !entre) { campos.push(actual); actual = ''; }
      else actual += c;
    }
    campos.push(actual);
    filas.push(campos);
  }
  return filas;
}

const desescapar = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
const todos = (xml, etiqueta) => [...xml.matchAll(new RegExp(`<${etiqueta}(?: [^>]*)?>([^<]*)</${etiqueta}>`, 'g'))].map((m) => desescapar(m[1]));

// --- JMdict: índice por forma escrita y por lectura ---
const jmdict = gunzipSync(readFileSync(new URL('JMdict.gz', FUENTES))).toString('utf8');
const entradas = [];
for (const bloque of jmdict.split('<entry>').slice(1)) {
  const seq = Number(/<ent_seq>(\d+)<\/ent_seq>/.exec(bloque)[1]);
  const kebs = todos(bloque, 'keb');
  const rebs = todos(bloque, 'reb');
  const sentidos = bloque.split('<sense>').slice(1);
  const glosas = (idioma) => sentidos.map((s) => [...s.matchAll(/<gloss( xml:lang="(\w+)")?[^>]*>([^<]*)<\/gloss>/g)]
    .filter((m) => (m[2] ?? 'eng') === idioma).map((m) => desescapar(m[3]))).filter((g) => g.length);
  const comun = /<(ke_pri|re_pri)>(news1|ichi1|spec1|spec2|gai1)</.test(bloque);
  entradas.push({ seq, kebs, rebs, es: glosas('spa'), en: glosas('eng'), comun });
}
const porForma = new Map();
for (const e of entradas) for (const k of [...e.kebs, ...e.rebs]) porForma.set(k, [...(porForma.get(k) ?? []), e]);

// El CSV trae variantes como 「〜時」 o 「ご飯・御飯」: se prueba cada forma sin 〜.
const formas = (s) => s.split(/[・、/;；]/).map((x) => x.replace(/[〜～]/g, '').trim()).filter(Boolean);
const katakanaAHiragana = (s) => s.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));

const palabrasEn = (s) => new Set(s.toLowerCase().match(/[a-z]+/g) ?? []);

// Entre las entradas con esa forma y esa lectura, la que mejor coincide con el significado en inglés de la lista
// (ああ «Ah!» no es ああ «like that»); luego la común, la que tiene español y la de menor número.
function buscar(palabra, lectura, ingles) {
  const lecturas = formas(lectura).map(katakanaAHiragana);
  const candidatas = formas(palabra).flatMap((f) => porForma.get(f) ?? []);
  const conLectura = candidatas.filter((e) => e.rebs.some((r) => lecturas.includes(katakanaAHiragana(r))));
  const lista = [...new Set(conLectura.length ? conLectura : candidatas)];
  const objetivo = palabrasEn(ingles);
  const parecido = (e) => [...palabrasEn(e.en.flat().join(' '))].filter((w) => objetivo.has(w)).length;
  return lista.sort((a, b) => (parecido(b) - parecido(a)) || (b.comun - a.comun) || (b.es.length > 0) - (a.es.length > 0) || a.seq - b.seq)[0];
}

const traducciones = existsSync(new URL('traducciones-claude.json', DATOS))
  ? JSON.parse(readFileSync(new URL('traducciones-claude.json', DATOS), 'utf8')) : {};
const revision = existsSync(new URL('revision-claude.json', DATOS))
  ? JSON.parse(readFileSync(new URL('revision-claude.json', DATOS), 'utf8')) : {};
// Limpia restos de JMdict que no son significado: «(eng: cup)», «(usado en documentos legales)».
const limpiar = (g) => g.replace(/\s*\((eng|usado|used)[^)]*\)\s*/gi, ' ').replace(/\s+/g, ' ').trim();
const unicas = (lista, max) => [...new Set(lista.map(limpiar).filter(Boolean))].slice(0, max);

const [, ...filas] = filasCsv(readFileSync(new URL('n5.csv', FUENTES), 'utf8'));
const vistos = new Set();
const vocabulario = [];
for (const [palabra, lectura, ingles] of filas) {
  const id = `${palabra}|${lectura}`;
  if (vistos.has(id)) continue;
  vistos.add(id);
  const e = buscar(palabra, lectura, ingles);
  // Solo el primer sentido en español: los siguientes suelen ser usos raros (赤い «comunista»).
  const deJmdict = unicas(e?.es?.[0] ?? [], 3);
  const deClaude = traducciones[`v:${id}`];
  const corregido = revision[`v:${id}`];
  vocabulario.push({
    id,
    palabra,
    lectura,
    es: corregido?.sugerencia ?? (deJmdict.length ? deJmdict : deClaude ?? null),
    origenEs: corregido ? 'claude-corrige' : deJmdict.length ? 'jmdict' : deClaude ? 'claude' : null,
    ...(corregido ? { original: deJmdict.length ? deJmdict : deClaude ?? [], problema: corregido.problema } : {}),
    en: ingles, // el significado de la lista original: es la referencia para revisar el español
    jmdict: e?.seq ?? null,
  });
}

// --- KANJIDIC2: nivel 4 del examen anterior a 2010 (≈ N5 actual) ---
const kanjidic = gunzipSync(readFileSync(new URL('kanjidic2.xml.gz', FUENTES))).toString('utf8');
const kanji = [];
for (const bloque of kanjidic.split('<character>').slice(1)) {
  if (!/<jlpt>4<\/jlpt>/.test(bloque)) continue;
  const caracter = /<literal>([^<]+)<\/literal>/.exec(bloque)[1];
  const lecturas = (tipo) => [...bloque.matchAll(new RegExp(`<reading r_type="${tipo}">([^<]+)</reading>`, 'g'))].map((m) => m[1]);
  const significados = (idioma) => [...bloque.matchAll(/<meaning( m_lang="(\w+)")?>([^<]+)<\/meaning>/g)]
    .filter((m) => (m[2] ?? 'en') === idioma).map((m) => desescapar(m[3]));
  const es = unicas(significados('es'), 3);
  const deClaude = traducciones[`k:${caracter}`];
  const corregido = revision[`k:${caracter}`];
  kanji.push({
    kanji: caracter,
    on: lecturas('ja_on'),
    kun: lecturas('ja_kun'),
    es: corregido?.sugerencia ?? (es.length ? es : deClaude ?? null),
    origenEs: corregido ? 'claude-corrige' : es.length ? 'kanjidic2' : deClaude ? 'claude' : null,
    ...(corregido ? { original: es, problema: corregido.problema } : {}),
    en: unicas(significados('en'), 3),
    trazos: Number(/<stroke_count>(\d+)</.exec(bloque)[1]),
  });
}

writeFileSync(new URL('vocabulario-n5.json', DATOS), JSON.stringify(vocabulario, null, 1));
writeFileSync(new URL('kanji-n5.json', DATOS), JSON.stringify(kanji, null, 1));
const cuenta = (l, o) => l.filter((x) => x.origenEs === o).length;
console.log(`vocabulario: ${vocabulario.length} (jmdict ${cuenta(vocabulario, 'jmdict')}, claude ${cuenta(vocabulario, 'claude')}, ` +
  `corregidas ${cuenta(vocabulario, 'claude-corrige')}, ` +
  `sin español ${cuenta(vocabulario, null)}, sin entrada JMdict ${vocabulario.filter((v) => !v.jmdict).length})`);
console.log(`kanji: ${kanji.length} (kanjidic2 ${cuenta(kanji, 'kanjidic2')}, corregidos ${cuenta(kanji, 'claude-corrige')}, sin español ${cuenta(kanji, null)})`);
const huerfanas = Object.keys(revision).filter((k) => !(k.startsWith('v:') ? vistos.has(k.slice(2)) : kanji.some((x) => `k:${x.kanji}` === k)));
if (huerfanas.length) throw new Error(`revision-claude.json tiene claves que no existen: ${huerfanas.join(', ')}`);

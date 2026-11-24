// Plantillas de trazos de los kana para «Escribir» (iOS), a partir de KanjiVG (CC BY-SA 3.0), commit fijado abajo.
// Cada kana queda como una lista de trazos en orden; cada trazo, una polilínea en las coordenadas de KanjiVG
// (recuadro de 109 × 109, y hacia abajo). Salida: datos/trazos-kana.json. Uso: node scripts/trazos/construir.mjs [--descargar]
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';

export const KANJIVG_COMMIT = '9d7220dfca09107dca2e0b0e45f90f696185e3c3';
const FUENTES = new URL('../../datos/fuentes/kanjivg/', import.meta.url);
const SALIDA = new URL('../../datos/trazos-kana.json', import.meta.url);

// Hiragana ぁ–ゖ y katakana ァ–ヺ: KanjiVG no tiene algunos (se omiten); la app comprueba que estén los que pregunta.
const codigos = [];
for (let c = 0x3041; c <= 0x3096; c++) codigos.push(c);
for (let c = 0x30a1; c <= 0x30fa; c++) codigos.push(c);

mkdirSync(FUENTES, { recursive: true });
const plantillas = {};
for (const c of codigos) {
  const nombre = c.toString(16).padStart(5, '0') + '.svg';
  const ruta = new URL(nombre, FUENTES);
  if (process.argv.includes('--descargar') || !existsSync(ruta)) {
    const url = `https://raw.githubusercontent.com/KanjiVG/kanjivg/${KANJIVG_COMMIT}/kanji/${nombre}`;
    // Solo un 404 significa «KanjiVG no tiene ese kana»; cualquier otro fallo (red, 5xx) detiene el script.
    const codigo = execFileSync('curl', ['-s', '--max-time', '60', '-o', ruta.pathname, '-w', '%{http_code}', url]).toString();
    if (codigo === '404') { rmSync(ruta, { force: true }); continue; }
    if (codigo !== '200') throw new Error(`${url}: HTTP ${codigo}`);
  }
  const svg = readFileSync(ruta, 'utf8');
  // Solo los trazos (id kvg:XXXXX-sN), en el orden del archivo, que es el orden de escritura.
  const trazos = [...svg.matchAll(/<path id="kvg:[0-9a-f]+-s\d+"[^>]*\sd="([^"]+)"/g)].map((m) => polilinea(m[1]));
  if (trazos.length === 0) throw new Error(`${nombre}: sin trazos`);
  plantillas[String.fromCodePoint(c)] = trazos;
}
writeFileSync(SALIDA, JSON.stringify(plantillas) + '\n');
console.log(`${Object.keys(plantillas).length} kana → ${SALIDA.pathname}`);

// Trazado SVG (M, C, S, L y sus relativas, que es lo que usa KanjiVG) → puntos, 8 por curva.
function polilinea(d) {
  const fichas = d.match(/[MmCcSsLlZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?/g);
  const puntos = [];
  let i = 0, cmd = '', x = 0, y = 0, cx2 = 0, cy2 = 0;
  const num = () => Number(fichas[i++]);
  const redondo = (v) => Math.round(v * 10) / 10;
  while (i < fichas.length) {
    if (/[A-Za-z]/.test(fichas[i])) cmd = fichas[i++];
    const rel = cmd === cmd.toLowerCase();
    const ox = rel ? x : 0, oy = rel ? y : 0;
    switch (cmd.toUpperCase()) {
      case 'M': case 'L':
        x = ox + num(); y = oy + num(); cx2 = x; cy2 = y;
        puntos.push([redondo(x), redondo(y)]);
        if (cmd === 'M') cmd = 'L'; else if (cmd === 'm') cmd = 'l';
        break;
      case 'C': case 'S': {
        let x1, y1;
        if (cmd.toUpperCase() === 'C') { x1 = ox + num(); y1 = oy + num(); } else { x1 = 2 * x - cx2; y1 = 2 * y - cy2; }
        const x2 = ox + num(), y2 = oy + num(), x3 = ox + num(), y3 = oy + num();
        for (let k = 1; k <= 8; k++) {
          const t = k / 8, u = 1 - t;
          puntos.push([redondo(u ** 3 * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 * x3),
                       redondo(u ** 3 * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3 * y3)]);
        }
        x = x3; y = y3; cx2 = x2; cy2 = y2;
        break;
      }
      case 'Z': break; // la ficha «Z» ya se leyó arriba
      default: throw new Error(`comando SVG no soportado: ${cmd} en ${d}`);
    }
  }
  return puntos;
}

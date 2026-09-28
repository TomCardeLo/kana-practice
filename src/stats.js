// Estadísticas de aciertos/fallos por kana, persistidas en localStorage.
// Si localStorage no está disponible (modo privado, cuotas, etc.) la app sigue
// funcionando sin guardar: toda lectura/escritura va protegida con try/catch.

const KEY = 'kana-practice:stats:v1';
const BEST_KEY = 'kana-practice:cards-best:v1';

function vacio() {
  return { hiragana: {}, katakana: {} };
}

function leer() {
  try {
    const crudo = localStorage.getItem(KEY);
    if (!crudo) return vacio();
    const datos = JSON.parse(crudo);
    return { hiragana: datos.hiragana || {}, katakana: datos.katakana || {} };
  } catch {
    return vacio();
  }
}

function escribir(datos) {
  try {
    localStorage.setItem(KEY, JSON.stringify(datos));
  } catch {
    // Sin almacenamiento disponible: la práctica sigue, solo no se guarda el progreso.
  }
}

export function load() {
  return leer();
}

// Registra los resultados de una corrección (ver check.js) en el silabario indicado.
// Cada kana tiene su propio contador; hiragana y katakana nunca se mezclan.
export function record(results, silabario) {
  const datos = leer();
  const bucket = datos[silabario] || (datos[silabario] = {});
  for (const palabra of results.words) {
    for (const unidad of palabra) {
      const entrada = bucket[unidad.kana] || { ok: 0, fail: 0 };
      if (unidad.ok) entrada.ok += 1;
      else entrada.fail += 1;
      bucket[unidad.kana] = entrada;
    }
  }
  escribir(datos);
}

export function reset() {
  escribir(vacio());
}

// Mejor tiempo medio por tarjeta (ms) del minijuego de tarjetas, por combinación
// silabario+mazo+tamaño. Misma protección try/catch que el resto del módulo: sin
// localStorage, siempre devuelve null y saveBestTime no falla.
export function loadBestTime(clave) {
  try {
    const crudo = localStorage.getItem(BEST_KEY);
    const datos = crudo ? JSON.parse(crudo) : {};
    const valor = datos[clave];
    return typeof valor === 'number' ? valor : null;
  } catch {
    return null;
  }
}

// Guarda ms como récord de `clave` si es mejor que el anterior (o si no había ninguno).
// Devuelve true si quedó guardado un récord nuevo.
export function saveBestTime(clave, ms) {
  const anterior = loadBestTime(clave);
  if (anterior !== null && ms >= anterior) return false;
  try {
    const crudo = localStorage.getItem(BEST_KEY);
    const datos = crudo ? JSON.parse(crudo) : {};
    datos[clave] = ms;
    localStorage.setItem(BEST_KEY, JSON.stringify(datos));
    return true;
  } catch {
    return false;
  }
}

// Kana del silabario indicado, ordenados por porcentaje de error descendente.
export function ranking(silabario) {
  const bucket = leer()[silabario] || {};
  return Object.entries(bucket)
    .map(([kana, { ok, fail }]) => {
      const total = ok + fail;
      return { kana, ok, fail, total, errorRate: total > 0 ? fail / total : 0 };
    })
    .sort((a, b) => b.errorRate - a.errorRate);
}

// Conecta la UI con la lógica de conversión, corrección y estadísticas.
import { toSyllables } from './translit.js';
import { toUnits, rowOf, rowExample, ROWS } from './kana.js';
import { checkAnswer } from './check.js';
import * as stats from './stats.js';
import { words } from './words.js';

const ALL_ROW_IDS = ROWS.map((fila) => fila.id);

// --- elementos ---
const inputText = document.getElementById('input-text');
const btnRandom = document.getElementById('btn-random');
const btnGenerate = document.getElementById('btn-generate');
const rowChipsEl = document.getElementById('row-chips');
const kanaOutputEl = document.getElementById('kana-output');
const answerForm = document.getElementById('answer-form');
const inputAnswer = document.getElementById('input-answer');
const btnSolution = document.getElementById('btn-solution');
const scoreEl = document.getElementById('score');
const statsGridEl = document.getElementById('stats-grid');
const btnResetStats = document.getElementById('btn-reset-stats');
const messageEl = document.getElementById('message');
const silabarioRadios = [...document.querySelectorAll('input[name="silabario"]')];

// --- estado ---
let silabario = 'hiragana';
const activeRows = new Set(ALL_ROW_IDS);
let generated = null; // { silabario, words: [[{ romaji, kana, row, dimmed }]] }
let lastCheck = null; // resultado de checkAnswer, o null
let resetPending = false;
let resetTimer = null;

// Banco de palabras precalculado una sola vez (sin bucles de reintento al filtrar).
const wordBank = words
  .map((texto) => {
    const [silabas] = toSyllables(texto);
    if (!silabas || silabas.length === 0) return null;
    return { texto, silabas, rows: new Set(silabas.map(rowOf)) };
  })
  .filter(Boolean);

function showMessage(texto, { warning = true } = {}) {
  messageEl.textContent = texto;
  messageEl.classList.toggle('is-warning', Boolean(texto) && warning);
}

function clearMessage() {
  messageEl.textContent = '';
  messageEl.classList.remove('is-warning');
}

// --- filtro por filas ---
function renderRowChips() {
  rowChipsEl.innerHTML = '';
  for (const fila of ROWS) {
    const boton = document.createElement('button');
    boton.type = 'button';
    boton.className = 'chip';
    boton.dataset.testid = `row-chip-${fila.id}`;
    boton.setAttribute('aria-pressed', String(activeRows.has(fila.id)));
    boton.innerHTML = `<span>${rowExample(fila.id, silabario)}</span><span class="chip__label">${fila.label}</span>`;
    boton.addEventListener('click', () => toggleRow(fila.id));
    rowChipsEl.appendChild(boton);
  }
}

// Solo actualiza aria-pressed del chip pulsado: reconstruir todos los chips aquí
// perdería el foco del que se acaba de pulsar. Los chips se reconstruyen solo al
// cambiar de silabario (los kana de ejemplo cambian).
function toggleRow(rowId) {
  if (activeRows.has(rowId)) {
    activeRows.delete(rowId);
  } else {
    activeRows.add(rowId);
  }
  const boton = rowChipsEl.querySelector(`[data-testid="row-chip-${rowId}"]`);
  if (boton) boton.setAttribute('aria-pressed', String(activeRows.has(rowId)));
}

// --- palabra al azar ---
function pickRandomWord() {
  if (activeRows.size === 0) {
    showMessage('Selecciona al menos una fila del silabario.');
    return;
  }
  const candidatas = wordBank.filter((palabra) => [...palabra.rows].every((fila) => activeRows.has(fila)));
  if (candidatas.length === 0) {
    showMessage('Ninguna palabra usa solo las filas elegidas.');
    return;
  }
  const elegida = candidatas[Math.floor(Math.random() * candidatas.length)];
  inputText.value = elegida.texto;
  clearMessage();
}

// --- generar práctica ---
function generate() {
  if (activeRows.size === 0) {
    showMessage('Selecciona al menos una fila del silabario.');
    return;
  }
  const palabras = toSyllables(inputText.value);
  if (palabras.length === 0) {
    showMessage('Escribe un texto o pide una palabra al azar.');
    return;
  }
  const unidades = toUnits(palabras, silabario);
  const hayUnidadActiva = unidades.some((palabra) => palabra.some((unidad) => activeRows.has(unidad.row)));
  if (!hayUnidadActiva) {
    showMessage('Ningún kana del texto está en las filas elegidas.');
    return;
  }
  generated = {
    silabario,
    words: unidades.map((palabra) => palabra.map((unidad) => ({ ...unidad, dimmed: !activeRows.has(unidad.row) }))),
  };
  lastCheck = null;
  inputAnswer.value = '';
  kanaOutputEl.classList.remove('show-solution');
  clearMessage();
  renderKanaOutput();
  scoreEl.textContent = '';
}

function renderKanaOutput() {
  kanaOutputEl.innerHTML = '';
  if (!generated) {
    const vacio = document.createElement('p');
    vacio.className = 'kana-output__empty';
    vacio.textContent = 'Escribe un texto y pulsa «Generar» para ver el kana aquí.';
    kanaOutputEl.appendChild(vacio);
    return;
  }

  let cursor = 0;
  generated.words.forEach((palabra) => {
    const filaWord = document.createElement('div');
    filaWord.className = 'kana-word';
    palabra.forEach((unidad) => {
      const resultado = !unidad.dimmed && lastCheck ? buscarResultado(cursor) : null;
      if (!unidad.dimmed && lastCheck) cursor += 1;
      filaWord.appendChild(renderCelda(unidad, resultado));
    });
    kanaOutputEl.appendChild(filaWord);
  });
}

function buscarResultado(indiceActivo) {
  const activos = lastCheck.words.flat();
  return activos[indiceActivo] || null;
}

function renderCelda(unidad, resultado) {
  const celda = document.createElement('span');
  celda.className = 'kana-cell';
  celda.dataset.testid = 'kana-cell';
  celda.dataset.romaji = unidad.romaji;

  if (unidad.dimmed) {
    celda.classList.add('is-dimmed');
    celda.dataset.state = 'dimmed';
  } else if (resultado) {
    celda.classList.add(resultado.ok ? 'is-ok' : 'is-error');
    celda.dataset.state = resultado.ok ? 'ok' : 'error';
  } else {
    celda.dataset.state = 'pending';
  }

  const kanaSpan = document.createElement('span');
  kanaSpan.className = 'kana-cell__kana';
  kanaSpan.textContent = unidad.kana;
  celda.appendChild(kanaSpan);

  const romajiSpan = document.createElement('span');
  romajiSpan.className = 'kana-cell__romaji';
  romajiSpan.textContent = unidad.romaji;
  celda.appendChild(romajiSpan);

  if (resultado && !resultado.ok) {
    const typedSpan = document.createElement('span');
    typedSpan.className = 'kana-cell__typed';
    typedSpan.textContent = resultado.typed ? `escribiste: ${resultado.typed}` : 'falta';
    celda.appendChild(typedSpan);
  }

  return celda;
}

// --- corrección ---
function handleCheck(evento) {
  evento.preventDefault();
  if (!generated) {
    showMessage('Primero escribe un texto y pulsa «Generar».');
    return;
  }
  const expectedForCheck = generated.words.map((palabra) =>
    palabra.filter((unidad) => !unidad.dimmed).map(({ romaji, kana, row }) => ({ romaji, kana, row }))
  );
  const resultado = checkAnswer(expectedForCheck, inputAnswer.value);
  if (resultado === null) {
    showMessage('Escribe tu transcripción antes de corregir.');
    return;
  }
  lastCheck = resultado;
  stats.record(resultado, generated.silabario);
  clearMessage();
  renderKanaOutput();
  const sobrantes = resultado.extra > 0 ? ` · ${resultado.extra} sobrantes` : '';
  scoreEl.textContent = `${resultado.correct} / ${resultado.total} correctos${sobrantes}`;
  renderStats();
}

function showSolution() {
  kanaOutputEl.classList.add('show-solution');
}

// --- estadísticas ---
function renderStats() {
  const ranking = stats.ranking(silabario);
  statsGridEl.innerHTML = '';
  if (ranking.length === 0) {
    const vacio = document.createElement('p');
    vacio.className = 'stats-panel__empty';
    vacio.textContent = 'Todavía no hay estadísticas para este silabario. Corrige alguna práctica para empezar.';
    statsGridEl.appendChild(vacio);
    return;
  }
  for (const entrada of ranking) {
    const celda = document.createElement('div');
    celda.className = 'stats-cell';
    celda.dataset.testid = 'stats-cell';

    const kanaSpan = document.createElement('span');
    kanaSpan.className = 'stats-cell__kana';
    kanaSpan.textContent = entrada.kana;
    celda.appendChild(kanaSpan);

    const rateSpan = document.createElement('span');
    rateSpan.className = 'stats-cell__rate';
    rateSpan.textContent = `${Math.round(entrada.errorRate * 100)}% error`;
    celda.appendChild(rateSpan);

    statsGridEl.appendChild(celda);
  }
}

function resetStatsLabel(texto) {
  btnResetStats.textContent = texto;
}

function handleResetStatsClick() {
  if (!resetPending) {
    resetPending = true;
    resetStatsLabel('¿Confirmas el reinicio?');
    resetTimer = window.setTimeout(() => {
      resetPending = false;
      resetStatsLabel('Reiniciar estadísticas');
    }, 4000);
    return;
  }
  window.clearTimeout(resetTimer);
  resetPending = false;
  resetStatsLabel('Reiniciar estadísticas');
  stats.reset();
  renderStats();
  showMessage('Estadísticas reiniciadas.', { warning: false });
}

// --- silabario ---
function updateSegmentedClasses() {
  for (const radio of silabarioRadios) {
    radio.closest('.segmented__option').classList.toggle('is-checked', radio.checked);
  }
}

function handleSilabarioChange(evento) {
  silabario = evento.target.value;
  updateSegmentedClasses();
  renderRowChips();
  renderStats();
}

// --- eventos ---
btnRandom.addEventListener('click', pickRandomWord);
btnGenerate.addEventListener('click', generate);
answerForm.addEventListener('submit', handleCheck);
btnSolution.addEventListener('click', showSolution);
btnResetStats.addEventListener('click', handleResetStatsClick);
for (const radio of silabarioRadios) {
  radio.addEventListener('change', handleSilabarioChange);
}

// --- inicio ---
updateSegmentedClasses();
renderRowChips();
renderKanaOutput();
renderStats();

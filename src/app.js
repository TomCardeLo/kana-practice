// Conecta la UI con la lógica de conversión, corrección y estadísticas.
import { toSyllables } from './translit.js';
import { toUnits, rowOf, rowExample, ROWS, syllablesByRow } from './kana.js';
import { checkAnswer } from './check.js';
import * as stats from './stats.js';
import { words } from './words.js';

const ALL_ROW_IDS = ROWS.map((fila) => fila.id);
const TUTORIAL_SEEN_KEY = 'kana-practice:tutorial-seen:v1';

// --- elementos: práctica ---
const tabRandomBtn = document.getElementById('tab-random');
const tabTextBtn = document.getElementById('tab-text');
const panelRandomEl = document.getElementById('panel-random');
const panelTextEl = document.getElementById('panel-text');
const btnNewRound = document.getElementById('btn-new-round');
const inputText = document.getElementById('input-text');
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

// --- elementos: tutorial ---
const btnTutorial = document.getElementById('btn-tutorial');
const btnTutorialClose = document.getElementById('btn-tutorial-close');
const tutorialDialog = document.getElementById('tutorial-dialog');
const tutorialTabGuide = document.getElementById('tutorial-tab-guide');
const tutorialTabTable = document.getElementById('tutorial-tab-table');
const tutorialTabRules = document.getElementById('tutorial-tab-rules');
const tutorialPanelGuide = document.getElementById('tutorial-panel-guide');
const tutorialPanelTable = document.getElementById('tutorial-panel-table');
const tutorialPanelRules = document.getElementById('tutorial-panel-rules');
const tutorialTableWarning = document.getElementById('tutorial-table-warning');
const tutorialTableHiraganaBtn = document.getElementById('tutorial-table-hiragana');
const tutorialTableKatakanaBtn = document.getElementById('tutorial-table-katakana');
const tutorialTableGrid = document.getElementById('tutorial-table-grid');
const tutorialRulesTable = document.getElementById('tutorial-rules-table');

// --- estado ---
let silabario = 'hiragana';
let mode = 'random'; // 'random' | 'text'
const activeRows = new Set(ALL_ROW_IDS);
// generated: { mode, silabario, words: [[{romaji,kana,row}]], spanishWords?, wordsPerLine?, sourceText? }
let generated = null;
let lastCheck = null; // resultado de checkAnswer, o null
let resetPending = false;
let resetTimer = null;
let tutorialTableSilabario = 'hiragana';
let recorded = false; // ya se registraron estadísticas para la práctica generada actual
let solutionShown = false; // se pidió «Mostrar solución» en la práctica actual

// Ejemplos de §3 del tutorial, generados con toSyllables + toUnits (nunca kana escrito a
// mano), para que la tabla no se desincronice de las reglas reales. Definidos antes del
// banco de palabras porque este último excluye las palabras usadas como ejemplo (evita que
// el usuario vea la respuesta de una regla filtrando por la palabra al azar).
const RULE_EXAMPLES = [
  { regla: 'c/qu/k → k · c/z/s → s (ci/si → shi)', palabra: 'casa' },
  { regla: 'l, r, rr → r', palabra: 'luna' },
  { regla: 'j, g+e/i → h (ju → fu)', palabra: 'jugo' },
  { regla: 'consonante sin vocal siguiente → + u (t/d → + o)', palabra: 'tres' },
  { regla: 'consonante final → + u (t/d → + o)', palabra: 'sol' },
  { regla: 'h muda', palabra: 'hola' },
  { regla: 'v → b', palabra: 'vaca' },
  { regla: 'ñ → ny', palabra: 'niño' },
  { regla: 'tilde se pierde · n final o antes de consonante → ん', palabra: 'canción' },
];
export const RULE_EXAMPLE_WORDS = new Set(RULE_EXAMPLES.map((ejemplo) => ejemplo.palabra));

// Banco de palabras precalculado una sola vez (sin bucles de reintento al filtrar).
// Excluye las palabras usadas como ejemplo de regla en el tutorial: si salieran al azar,
// el usuario vería la respuesta (el kana) ya resuelta en la pestaña «Reglas de adaptación».
const wordBank = words
  .filter((texto) => !RULE_EXAMPLE_WORDS.has(texto))
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

// --- pestañas ARIA reutilizables (flechas izquierda/derecha, Home/End, selección + panel) ---
function setupTabs(tabs, onActivate) {
  let current = tabs.findIndex((tab) => tab.button.getAttribute('aria-selected') === 'true');
  if (current === -1) current = 0;
  function activate(index) {
    if (index === current) return; // ya está activa: no repetir onActivate ni el trabajo de DOM
    current = index;
    tabs.forEach((tab, i) => {
      const isActive = i === index;
      tab.button.setAttribute('aria-selected', String(isActive));
      tab.button.tabIndex = isActive ? 0 : -1;
      tab.button.classList.toggle('is-checked', isActive);
      if (tab.panel) tab.panel.hidden = !isActive;
    });
    onActivate(index);
  }
  tabs.forEach((tab, i) => {
    tab.button.addEventListener('click', () => activate(i));
    tab.button.addEventListener('keydown', (evento) => {
      if (evento.key === 'ArrowRight') {
        evento.preventDefault();
        const siguiente = (i + 1) % tabs.length;
        tabs[siguiente].button.focus();
        activate(siguiente);
      } else if (evento.key === 'ArrowLeft') {
        evento.preventDefault();
        const anterior = (i - 1 + tabs.length) % tabs.length;
        tabs[anterior].button.focus();
        activate(anterior);
      } else if (evento.key === 'Home') {
        evento.preventDefault();
        tabs[0].button.focus();
        activate(0);
      } else if (evento.key === 'End') {
        evento.preventDefault();
        const ultimo = tabs.length - 1;
        tabs[ultimo].button.focus();
        activate(ultimo);
      }
    });
  });
  return { activate };
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
  // El filtro cambió: si ya había corrección, se recalcula contra las filas activas nuevas
  // (sin volver a registrar estadísticas ni ocultar el español ya revelado).
  recheckIfNeeded();
}

// --- palabras al azar ---
function elegirDistintas(pool, cantidad) {
  const copia = [...pool];
  const elegidas = [];
  while (copia.length > 0 && elegidas.length < cantidad) {
    const indice = Math.floor(Math.random() * copia.length);
    elegidas.push(copia.splice(indice, 1)[0]);
  }
  return elegidas;
}

function buildRandomWords(spanishWords) {
  return spanishWords.map((texto) => {
    const silabas = toSyllables(texto)[0] || [];
    return toUnits([silabas], silabario)[0];
  });
}

function construirRondaAzar(spanishWords) {
  generated = { mode: 'random', silabario, words: buildRandomWords(spanishWords), spanishWords };
  terminarGeneracion();
}

function newRound() {
  if (activeRows.size === 0) {
    showMessage('Selecciona al menos una fila del silabario.');
    generated = null;
    renderKanaOutput();
    scoreEl.textContent = '';
    return;
  }
  const candidatas = wordBank.filter((palabra) => [...palabra.rows].every((fila) => activeRows.has(fila)));
  if (candidatas.length === 0) {
    showMessage('Ninguna palabra usa solo las filas elegidas.');
    generated = null;
    renderKanaOutput();
    scoreEl.textContent = '';
    return;
  }
  clearMessage();
  const spanishWords = elegirDistintas(candidatas, 5).map((palabra) => palabra.texto);
  construirRondaAzar(spanishWords);
}

// --- texto propio ---
// Respeta los saltos de línea: wordsPerLine guarda cuántas palabras tiene cada renglón
// para que renderKanaOutput() las agrupe visualmente, mientras que words queda plano
// (todas las palabras en orden) para que la corrección siga alineando la secuencia completa.
function procesarLineas(texto) {
  const lineas = texto.split('\n');
  const wordsPerLine = [];
  let palabras = [];
  for (const linea of lineas) {
    const silabasLinea = toSyllables(linea);
    wordsPerLine.push(silabasLinea.length);
    palabras = palabras.concat(toUnits(silabasLinea, silabario));
  }
  return { words: palabras, wordsPerLine };
}

function construirPracticaTexto(texto) {
  const { words: palabras, wordsPerLine } = procesarLineas(texto);
  generated = { mode: 'text', silabario, words: palabras, wordsPerLine, sourceText: texto };
  terminarGeneracion();
}

function generateFromText() {
  if (activeRows.size === 0) {
    showMessage('Selecciona al menos una fila del silabario.');
    return;
  }
  const texto = inputText.value;
  const { words: palabras } = procesarLineas(texto);
  if (palabras.length === 0) {
    showMessage('Escribe un texto en español para generar la práctica.');
    return;
  }
  const hayUnidadActiva = palabras.some((palabra) => palabra.some((unidad) => activeRows.has(unidad.row)));
  if (!hayUnidadActiva) {
    showMessage('Ningún kana del texto está en las filas elegidas.');
    return;
  }
  clearMessage();
  construirPracticaTexto(texto);
}

function terminarGeneracion() {
  lastCheck = null;
  recorded = false;
  solutionShown = false;
  inputAnswer.value = '';
  kanaOutputEl.classList.remove('show-solution');
  renderKanaOutput();
  scoreEl.textContent = '';
}

// Reconstruye `generated.words` con el silabario activo tras un cambio de silabario, sin
// tocar spanishWords/sourceText ni la respuesta ya escrita por el usuario.
function reconstruirGeneratedSilabario() {
  if (!generated) return;
  if (generated.mode === 'random') {
    generated = { ...generated, silabario, words: buildRandomWords(generated.spanishWords) };
  } else {
    const { words: palabras, wordsPerLine } = procesarLineas(generated.sourceText);
    generated = { ...generated, silabario, words: palabras, wordsPerLine };
  }
}

// Tras cambiar de silabario o de filtro de filas: si ya había una corrección, la recalcula
// (sin volver a registrar estadísticas, ver runCheck) conservando el español ya revelado;
// si no había corrección, solo vuelve a pintar el kana con el estado actual.
function recheckIfNeeded() {
  if (lastCheck) {
    runCheck();
  } else {
    renderKanaOutput();
  }
}

// --- salida de kana ---
function renderKanaOutput() {
  kanaOutputEl.innerHTML = '';
  if (!generated) {
    const vacio = document.createElement('p');
    vacio.className = 'kana-output__empty';
    vacio.textContent =
      mode === 'random'
        ? 'Selecciona al menos una fila para generar una ronda.'
        : 'Escribe un texto y pulsa «Generar» para ver el kana aquí.';
    kanaOutputEl.appendChild(vacio);
    return;
  }

  const revealed = Boolean(lastCheck) || kanaOutputEl.classList.contains('show-solution');
  const activosPlanos = lastCheck ? lastCheck.words.flat() : null;
  let cursor = 0;
  const siguienteResultado = (unidad) => {
    if (!activosPlanos || !activeRows.has(unidad.row)) return null;
    const resultado = activosPlanos[cursor] || null;
    cursor += 1;
    return resultado;
  };

  if (generated.mode === 'text') {
    let indice = 0;
    for (const cantidad of generated.wordsPerLine) {
      const lineaEl = document.createElement('div');
      lineaEl.className = 'kana-line';
      for (let i = 0; i < cantidad; i += 1) {
        lineaEl.appendChild(renderWordGroup(generated.words[indice], null, siguienteResultado));
        indice += 1;
      }
      kanaOutputEl.appendChild(lineaEl);
    }
  } else {
    generated.words.forEach((palabra, indice) => {
      const spanish = revealed ? generated.spanishWords[indice] : null;
      kanaOutputEl.appendChild(renderWordGroup(palabra, spanish, siguienteResultado));
    });
  }
}

function renderWordGroup(palabra, spanish, siguienteResultado) {
  const grupo = document.createElement('div');
  grupo.className = 'kana-word-group';

  const fila = document.createElement('div');
  fila.className = 'kana-word';
  palabra.forEach((unidad) => {
    const dimmed = !activeRows.has(unidad.row);
    fila.appendChild(renderCelda(unidad, siguienteResultado(unidad), dimmed));
  });
  grupo.appendChild(fila);

  if (spanish) {
    const reveal = document.createElement('p');
    reveal.className = 'word-reveal';
    reveal.dataset.testid = 'word-reveal';
    reveal.textContent = spanish;
    grupo.appendChild(reveal);
  }

  return grupo;
}

function renderCelda(unidad, resultado, dimmed) {
  const celda = document.createElement('span');
  celda.className = 'kana-cell';
  celda.dataset.testid = 'kana-cell';
  celda.dataset.romaji = unidad.romaji;

  if (dimmed) {
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
// Corrige contra la respuesta actual y actualiza kana + marcador. Registra estadísticas
// solo la primera vez para esta práctica (recorded) y nunca si se mostró la solución
// (solutionShown): reutilizada tanto por el envío manual como por el recálculo automático
// al cambiar silabario o filtro, para que ninguno de los dos duplique el conteo.
function runCheck() {
  if (!generated) return null;
  const expectedForCheck = generated.words.map((palabra) =>
    palabra.filter((unidad) => activeRows.has(unidad.row)).map(({ romaji, kana, row }) => ({ romaji, kana, row }))
  );
  const resultado = checkAnswer(expectedForCheck, inputAnswer.value);
  if (resultado === null) return null;
  lastCheck = resultado;
  if (!recorded && !solutionShown) {
    stats.record(resultado, generated.silabario);
    recorded = true;
    renderStats();
  }
  renderKanaOutput();
  const sobrantes = resultado.extra > 0 ? ` · ${resultado.extra} sobrantes` : '';
  const nota = solutionShown ? ' (no cuenta en estadísticas)' : '';
  scoreEl.textContent = `${resultado.correct} / ${resultado.total} correctos${sobrantes}${nota}`;
  return resultado;
}

function handleCheck(evento) {
  evento.preventDefault();
  if (!generated) {
    showMessage('Primero genera una práctica.');
    return;
  }
  const resultado = runCheck();
  if (resultado === null) {
    showMessage('Escribe tu transcripción antes de corregir.');
    return;
  }
  clearMessage();
}

function showSolution() {
  solutionShown = true;
  kanaOutputEl.classList.add('show-solution');
  renderKanaOutput();
}

function handleAnswerKeydown(evento) {
  if (evento.key === 'Enter' && (evento.ctrlKey || evento.metaKey)) {
    evento.preventDefault();
    answerForm.requestSubmit();
  }
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
  // Reconstruye solo `generated` (kana del nuevo silabario) y conserva la respuesta escrita;
  // si ya había corrección, recheckIfNeeded() la recalcula sin registrar de nuevo.
  reconstruirGeneratedSilabario();
  recheckIfNeeded();
}

// --- modos (pestañas) ---
function setMode(index) {
  mode = index === 0 ? 'random' : 'text';
  generated = null;
  lastCheck = null;
  recorded = false;
  solutionShown = false;
  inputAnswer.value = '';
  kanaOutputEl.classList.remove('show-solution');
  scoreEl.textContent = '';
  clearMessage();
  if (mode === 'random') {
    newRound();
  } else {
    renderKanaOutput();
  }
}

// --- tutorial ---
function tutorialSeenGet() {
  try {
    return localStorage.getItem(TUTORIAL_SEEN_KEY);
  } catch {
    return 'error';
  }
}

function tutorialSeenSet() {
  try {
    localStorage.setItem(TUTORIAL_SEEN_KEY, '1');
  } catch {
    // Sin almacenamiento disponible: no se recuerda la visita, no pasa nada.
  }
}

function updateTutorialTableWarning() {
  const ayudaEnCurso = Boolean(generated) && !lastCheck;
  tutorialTableWarning.hidden = !ayudaEnCurso;
}

function renderTutorialTable(silabarioTabla) {
  tutorialTableSilabario = silabarioTabla;
  tutorialTableHiraganaBtn.classList.toggle('is-checked', silabarioTabla === 'hiragana');
  tutorialTableHiraganaBtn.setAttribute('aria-pressed', String(silabarioTabla === 'hiragana'));
  tutorialTableKatakanaBtn.classList.toggle('is-checked', silabarioTabla === 'katakana');
  tutorialTableKatakanaBtn.setAttribute('aria-pressed', String(silabarioTabla === 'katakana'));

  const grupos = syllablesByRow();
  const tabla = document.createElement('table');
  tabla.className = 'kana-table';
  const cuerpo = document.createElement('tbody');
  for (const fila of ROWS) {
    const romajis = grupos[fila.id] || [];
    if (romajis.length === 0) continue;
    const unidades = toUnits([romajis], silabarioTabla)[0];
    const tr = document.createElement('tr');
    const th = document.createElement('th');
    th.scope = 'row';
    th.textContent = fila.label;
    tr.appendChild(th);
    unidades.forEach((unidad) => {
      const td = document.createElement('td');
      const kanaSpan = document.createElement('span');
      kanaSpan.className = 'kana-table__kana';
      kanaSpan.textContent = unidad.kana;
      const romajiSpan = document.createElement('span');
      romajiSpan.className = 'kana-table__romaji';
      romajiSpan.textContent = unidad.romaji;
      td.appendChild(kanaSpan);
      td.appendChild(romajiSpan);
      tr.appendChild(td);
    });
    cuerpo.appendChild(tr);
  }
  tabla.appendChild(cuerpo);
  tutorialTableGrid.innerHTML = '';
  tutorialTableGrid.appendChild(tabla);
}

function renderTutorialRules() {
  const tabla = tutorialRulesTable;
  tabla.innerHTML = '';
  const cabecera = document.createElement('tr');
  ['Regla', 'Ejemplo', 'Kana'].forEach((titulo) => {
    const th = document.createElement('th');
    th.scope = 'col';
    th.textContent = titulo;
    cabecera.appendChild(th);
  });
  tabla.appendChild(cabecera);

  for (const { regla, palabra } of RULE_EXAMPLES) {
    const silabas = toSyllables(palabra)[0] || [];
    // Siempre en hiragana: son los ejemplos de referencia del plan (casa→かさ...),
    // no deben cambiar según el silabario que el usuario tenga elegido en la práctica.
    const unidades = toUnits([silabas], 'hiragana')[0] || [];
    const kana = unidades.map((unidad) => unidad.kana).join('');

    const tr = document.createElement('tr');
    const tdRegla = document.createElement('td');
    tdRegla.textContent = regla;
    const tdPalabra = document.createElement('td');
    tdPalabra.textContent = palabra;
    const tdKana = document.createElement('td');
    tdKana.className = 'kana-table__kana';
    tdKana.textContent = kana;
    tr.append(tdRegla, tdPalabra, tdKana);
    tabla.appendChild(tr);
  }
}

function openTutorial() {
  renderTutorialRules();
  updateTutorialTableWarning();
  tutorialDialog.showModal();
}

// --- eventos ---
setupTabs(
  [
    { button: tabRandomBtn, panel: panelRandomEl },
    { button: tabTextBtn, panel: panelTextEl },
  ],
  setMode
);

setupTabs(
  [
    { button: tutorialTabGuide, panel: tutorialPanelGuide },
    { button: tutorialTabTable, panel: tutorialPanelTable },
    { button: tutorialTabRules, panel: tutorialPanelRules },
  ],
  (index) => {
    if (index === 1) updateTutorialTableWarning();
  }
);

btnNewRound.addEventListener('click', newRound);
btnGenerate.addEventListener('click', generateFromText);
answerForm.addEventListener('submit', handleCheck);
inputAnswer.addEventListener('keydown', handleAnswerKeydown);
btnSolution.addEventListener('click', showSolution);
btnResetStats.addEventListener('click', handleResetStatsClick);
for (const radio of silabarioRadios) {
  radio.addEventListener('change', handleSilabarioChange);
}

btnTutorial.addEventListener('click', openTutorial);
btnTutorialClose.addEventListener('click', () => tutorialDialog.close());
tutorialDialog.addEventListener('close', () => btnTutorial.focus());
tutorialTableHiraganaBtn.addEventListener('click', () => renderTutorialTable('hiragana'));
tutorialTableKatakanaBtn.addEventListener('click', () => renderTutorialTable('katakana'));

// --- inicio ---
updateSegmentedClasses();
renderRowChips();
renderTutorialTable(tutorialTableSilabario);
renderTutorialRules();
newRound();
renderStats();

if (tutorialSeenGet() === null) {
  tutorialSeenSet();
  tutorialDialog.showModal();
}

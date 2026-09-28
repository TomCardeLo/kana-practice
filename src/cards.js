// Minijuego de tarjetas: sale un kana suelto y hay que escribir su lectura en romaji.
import { cardDeck } from './kana.js';
import { isCorrectReading } from './check.js';
import * as stats from './stats.js';

const FEEDBACK_MS = 1200; // pausa tras un error antes de pasar a la siguiente tarjeta

// --- elementos: configuración ---
const configSection = document.getElementById('cards-config');
const gameSection = document.getElementById('cards-game');
const summarySection = document.getElementById('cards-summary');
const silabarioRadios = [...document.querySelectorAll('input[name="cards-silabario"]')];
const mazoRadios = [...document.querySelectorAll('input[name="cards-mazo"]')];
const sizeRadios = [...document.querySelectorAll('input[name="cards-size"]')];
const sizeFullCountEl = document.getElementById('size-full-count');
const btnStart = document.getElementById('btn-start');

// --- elementos: juego ---
const cardKanaEl = document.getElementById('card-kana');
const cardForm = document.getElementById('card-form');
const cardInput = document.getElementById('card-input');
const cardFeedbackEl = document.getElementById('card-feedback');
const livesEl = document.getElementById('lives');
const progressEl = document.getElementById('progress');
const cardTimerEl = document.getElementById('card-timer');
const btnSkip = document.getElementById('btn-skip');
const btnQuit = document.getElementById('btn-quit');

// --- elementos: resumen ---
const summaryTitleEl = document.getElementById('summary-title');
const summaryCorrectEl = document.getElementById('summary-correct');
const summaryTotalTimeEl = document.getElementById('summary-total-time');
const summaryAvgTimeEl = document.getElementById('summary-avg-time');
const summarySlowestEl = document.getElementById('summary-slowest');
const summaryErrorsEl = document.getElementById('summary-errors');
const summaryRecordEl = document.getElementById('summary-record');
const btnAgain = document.getElementById('btn-again');
const btnConfig = document.getElementById('btn-config');

// --- estado ---
// round: { config: {silabario, mazo, size}, cards, index, lives, correctCount, errors, respuestas, cardStartTime }
let round = null;
let timerInterval = null;
let feedbackTimeout = null;

// Barajado Fisher-Yates: no muta el array recibido.
function shuffle(array) {
  const copia = [...array];
  for (let i = copia.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copia[i], copia[j]] = [copia[j], copia[i]];
  }
  return copia;
}

// Mazo completo para la configuración elegida: "ambos" concatena hiragana + katakana
// (de ahí que Full se duplique con esa opción).
function deckFor(silabario, mazo) {
  if (silabario === 'ambos') {
    return [...cardDeck('hiragana', mazo), ...cardDeck('katakana', mazo)];
  }
  return cardDeck(silabario, mazo);
}

function getConfig() {
  return {
    silabario: silabarioRadios.find((radio) => radio.checked).value,
    mazo: mazoRadios.find((radio) => radio.checked).value,
    size: sizeRadios.find((radio) => radio.checked).value,
  };
}

function updateSegmentedClasses(radios) {
  for (const radio of radios) {
    radio.closest('.segmented__option').classList.toggle('is-checked', radio.checked);
  }
}

// Etiqueta «Full (N)»: el tamaño real del mazo elegido, que cambia con silabario y mazo.
function updateFullCount() {
  const { silabario, mazo } = getConfig();
  sizeFullCountEl.textContent = String(deckFor(silabario, mazo).length);
}

function buildRound(config) {
  const pool = shuffle(deckFor(config.silabario, config.mazo));
  const cantidad = config.size === 'full' ? pool.length : Number(config.size);
  return {
    config,
    cards: pool.slice(0, cantidad),
    index: 0,
    lives: 3,
    correctCount: 0,
    errors: [],
    respuestas: [], // { kana, romaji, ok, ms }
    cardStartTime: 0,
    nSobrante: false, // la tarjeta anterior fue ん (ver esLecturaCorrecta)
  };
}

function currentCard() {
  return round.cards[round.index];
}

function stopTimer() {
  if (timerInterval !== null) {
    window.clearInterval(timerInterval);
    timerInterval = null;
  }
}

function clearFeedbackTimeout() {
  if (feedbackTimeout !== null) {
    window.clearTimeout(feedbackTimeout);
    feedbackTimeout = null;
  }
}

function renderLives() {
  livesEl.textContent = '';
  for (let i = 0; i < 3; i += 1) {
    const corazon = document.createElement('span');
    corazon.setAttribute('aria-hidden', 'true');
    corazon.textContent = i < round.lives ? '♥' : '♡';
    livesEl.appendChild(corazon);
  }
  livesEl.dataset.lives = String(round.lives);
  livesEl.setAttribute('aria-label', `Vidas: ${round.lives} de 3`);
}

function renderProgress() {
  progressEl.textContent = `${round.index + 1}/${round.cards.length}`;
}

function updateCardTimer() {
  const segundos = (performance.now() - round.cardStartTime) / 1000;
  cardTimerEl.textContent = `${segundos.toFixed(1)} s`;
}

function showCard() {
  const tarjeta = currentCard();
  cardKanaEl.textContent = tarjeta.kana;
  cardInput.value = '';
  cardInput.disabled = false;
  cardFeedbackEl.textContent = '';
  renderLives();
  renderProgress();
  round.cardStartTime = performance.now();
  updateCardTimer();
  stopTimer();
  timerInterval = window.setInterval(updateCardTimer, 100);
  cardInput.focus();
}

// Registra el tiempo de respuesta (sin contar la pausa de feedback, porque se mide antes
// de programarla) y las estadísticas del kana en su propio silabario.
function registrarRespuesta(tarjeta, ok) {
  const ms = performance.now() - round.cardStartTime;
  round.respuestas.push({ kana: tarjeta.kana, romaji: tarjeta.romaji, ok, ms });
  stats.record({ words: [[{ kana: tarjeta.kana, ok }]] }, tarjeta.silabario);
}

function goNext() {
  round.index += 1;
  if (round.index >= round.cards.length) {
    endRound('complete');
  } else {
    showCard();
  }
}

// ん se acepta con una sola "n". Quien escribe "nn" deja la segunda "n" en la tarjeta
// siguiente: ahí se tolera una "n" inicial sobrante ("nka" vale para か, "nna" para な).
// ponytail: si la siguiente es ン (modo «Ambos»), esa "n" sobrante ya la responde.
function esLecturaCorrecta(valor) {
  const romaji = currentCard().romaji;
  if (isCorrectReading(romaji, valor)) return true;
  const escrito = valor.trim();
  return round.nSobrante && /^n/i.test(escrito) && isCorrectReading(romaji, escrito.slice(1));
}

function handleCorrect() {
  round.nSobrante = currentCard().romaji === 'n';
  registrarRespuesta(currentCard(), true);
  round.correctCount += 1;
  goNext();
}

function handleError() {
  round.nSobrante = false;
  const tarjeta = currentCard();
  registrarRespuesta(tarjeta, false);
  round.errors.push({ kana: tarjeta.kana, romaji: tarjeta.romaji });
  round.lives -= 1;
  renderLives();
  cardFeedbackEl.textContent = `${tarjeta.kana} se lee ${tarjeta.romaji}`;
  cardInput.disabled = true;
  stopTimer();
  feedbackTimeout = window.setTimeout(() => {
    feedbackTimeout = null;
    cardFeedbackEl.textContent = '';
    if (round.lives === 0) {
      endRound('gameover');
    } else {
      goNext();
    }
  }, FEEDBACK_MS);
}

// Acierto inmediato mientras se escribe, sin esperar Enter: una sílaba a medio escribir
// (isCorrectReading devuelve false) no hace nada.
function handleInput() {
  if (!round || cardInput.disabled) return;
  if (esLecturaCorrecta(cardInput.value)) {
    handleCorrect();
  }
}

function handleSubmit(evento) {
  evento.preventDefault();
  if (!round || cardInput.disabled) return;
  const valor = cardInput.value.trim();
  if (!valor) return; // campo vacío: no cuenta como error
  if (esLecturaCorrecta(valor)) {
    handleCorrect();
  } else {
    handleError();
  }
}

function handleSkip() {
  if (!round || cardInput.disabled) return;
  handleError();
}

function handleQuit() {
  if (!round) return;
  stopTimer();
  clearFeedbackTimeout();
  round = null;
  gameSection.hidden = true;
  summarySection.hidden = true;
  configSection.hidden = false;
  btnStart.focus();
}

function formatSegundos(ms) {
  return `${(ms / 1000).toFixed(1)} s`;
}

function renderSummaryLists() {
  summarySlowestEl.textContent = '';
  const masLentas = round.respuestas
    .filter((r) => r.ok)
    .sort((a, b) => b.ms - a.ms)
    .slice(0, 3);
  for (const respuesta of masLentas) {
    const li = document.createElement('li');
    li.textContent = `${respuesta.kana} · ${formatSegundos(respuesta.ms)}`;
    summarySlowestEl.appendChild(li);
  }

  summaryErrorsEl.textContent = '';
  if (round.errors.length === 0) {
    const li = document.createElement('li');
    li.textContent = 'Sin errores';
    summaryErrorsEl.appendChild(li);
  } else {
    for (const error of round.errors) {
      const li = document.createElement('li');
      li.textContent = `${error.kana} → ${error.romaji}`;
      summaryErrorsEl.appendChild(li);
    }
  }
}

function renderSummaryRecord(resultado, avgTimeMs) {
  const clave = `${round.config.silabario}-${round.config.mazo}-${round.config.size}`;
  if (resultado === 'complete' && stats.saveBestTime(clave, avgTimeMs)) {
    summaryRecordEl.textContent = `¡Nuevo récord! ${formatSegundos(avgTimeMs)} por tarjeta`;
    return;
  }
  // Sin récord nuevo: el anterior, o ninguno (ronda perdida, o sin localStorage).
  const anterior = stats.loadBestTime(clave);
  if (anterior !== null) {
    summaryRecordEl.textContent = `Récord: ${formatSegundos(anterior)} por tarjeta`;
  } else {
    summaryRecordEl.textContent = resultado === 'complete'
      ? 'No se pudo guardar el récord en este navegador.'
      : 'Completa la ronda para registrar un récord.';
  }
}

function endRound(resultado) {
  stopTimer();
  const totalTimeMs = round.respuestas.reduce((suma, respuesta) => suma + respuesta.ms, 0);
  // La media (y el récord) solo cuenta aciertos: un «No la sé» rápido no debe mejorarla.
  const aciertos = round.respuestas.filter((respuesta) => respuesta.ok);
  const avgTimeMs = aciertos.length > 0
    ? aciertos.reduce((suma, respuesta) => suma + respuesta.ms, 0) / aciertos.length
    : 0;

  gameSection.hidden = true;
  summarySection.hidden = false;
  summarySection.dataset.result = resultado;
  summaryTitleEl.textContent = resultado === 'complete' ? '¡Ronda completada!' : 'Sin vidas';
  summaryCorrectEl.textContent = `${round.correctCount}/${round.cards.length}`;
  summaryTotalTimeEl.textContent = formatSegundos(totalTimeMs);
  summaryAvgTimeEl.textContent = formatSegundos(avgTimeMs);
  renderSummaryLists();
  renderSummaryRecord(resultado, avgTimeMs);
  summaryTitleEl.focus();
}

function startRound() {
  round = buildRound(getConfig());
  configSection.hidden = true;
  summarySection.hidden = true;
  gameSection.hidden = false;
  showCard();
}

function playAgain() {
  round = buildRound(round.config);
  summarySection.hidden = true;
  gameSection.hidden = false;
  showCard();
}

function backToConfig() {
  round = null;
  summarySection.hidden = true;
  configSection.hidden = false;
  btnStart.focus();
}

// --- eventos ---
for (const radio of [...silabarioRadios, ...mazoRadios]) {
  radio.addEventListener('change', () => {
    updateSegmentedClasses(silabarioRadios);
    updateSegmentedClasses(mazoRadios);
    updateFullCount();
  });
}
for (const radio of sizeRadios) {
  radio.addEventListener('change', () => updateSegmentedClasses(sizeRadios));
}

btnStart.addEventListener('click', startRound);
cardForm.addEventListener('submit', handleSubmit);
cardInput.addEventListener('input', handleInput);
btnSkip.addEventListener('click', handleSkip);
btnQuit.addEventListener('click', handleQuit);
btnAgain.addEventListener('click', playAgain);
btnConfig.addEventListener('click', backToConfig);

// --- inicio ---
updateSegmentedClasses(silabarioRadios);
updateSegmentedClasses(mazoRadios);
updateSegmentedClasses(sizeRadios);
updateFullCount();

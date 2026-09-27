# Kana Practice

Web estática para practicar la lectura de kana (hiragana y katakana). La app adapta texto en
español fonéticamente al japonés y lo muestra en kana. Después transcribes de vuelta a romaji
y la app corrige kana por kana. No traduce nada, no usa kanji.

Sin backend, sin cuentas: todo corre en el navegador. HTML + CSS + JavaScript con módulos ES,
sin framework ni paso de build. Única dependencia: [wanakana](https://github.com/WaniKani/WanaKana)
5.3.1, vendorizada en `vendor/wanakana-5.3.1.js`.

## Modos de práctica

- **Palabras al azar** (por defecto): genera una ronda de 5 palabras distintas con el botón
  «Nueva ronda». El español queda oculto hasta que corriges o pides «Mostrar solución»; ahí se
  revela bajo cada grupo de kana.
- **Texto propio**: escribe o pega un párrafo en el área de texto y pulsa «Generar». Respeta los
  saltos de línea (cada renglón se muestra como su propio bloque de kana); la corrección sigue
  alineando la transcripción completa.

Ambos modos comparten el silabario (hiragana/katakana), el filtro por filas y las estadísticas.
Cambiar de silabario en modo al azar regenera la misma ronda en el otro silabario.

## Tutorial

El botón «Tutorial» de la cabecera abre un panel con tres pestañas: **Cómo funciona** (guía
rápida), **Tabla de kana** (gojūon, dakuten y combinaciones ゃゅょ, generada con wanakana, con
conmutador hiragana/katakana) y **Reglas de adaptación** (resumen de las reglas español → romaji
con ejemplos calculados por la propia app). Se abre solo la primera vez que se visita la app
(bandera en `localStorage`) y se puede reabrir siempre con el botón.

## Uso local

No hace falta instalar nada, es un sitio estático. Basta con servir la carpeta:

```bash
python3 -m http.server 8765
```

Y abrir `http://localhost:8765` en el navegador.

## Pruebas E2E

Las pruebas viven en `tests/e2e/` y usan Playwright:

```bash
npm install
npx playwright install chromium
npx playwright test
```

El reporte HTML generado (`playwright-report/`) es el artefacto verificable de cada corrida.

## Deploy

Sitio en producción: https://kana-practice-green.vercel.app

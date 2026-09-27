# Kana Practice

Web estática para practicar la lectura de kana (hiragana y katakana), adaptando texto en
español al japonés fonéticamente.

**Pruébala:** https://kana-practice-green.vercel.app

[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-brightgreen)](LICENSE)
[![Deploy en Vercel](https://img.shields.io/badge/deploy-Vercel-000000?logo=vercel&logoColor=white)](https://kana-practice-green.vercel.app)
[![Tests con Playwright](https://img.shields.io/badge/tests-Playwright-2EAD33?logo=playwright&logoColor=white)](tests/e2e)
[![Sin dependencias de runtime](https://img.shields.io/badge/dependencias%20de%20runtime-ninguna-blue)](vendor/wanakana-5.3.1.js)

![Corrección de una ronda, con aciertos en verde, errores en rojo y las palabras en español reveladas](docs/screenshots/corrected.png)

## ¿Qué hace?

- Convierte una palabra al azar o un texto propio en español a kana (hiragana o katakana),
  siguiendo reglas fonéticas fijas: es una adaptación de sonido, no una traducción.
- Escondes el español y transcribes el kana de vuelta a romaji; la app corrige kana por kana
  y marca cada unidad en verde (correcta) o rojo (incorrecta).
- Acepta las variantes romaji habituales (shi/si, tsu/tu, fu/hu, ji/zi, n/nn) para no penalizar
  estilos de romanización distintos.
- Lleva estadísticas de acierto por kana en el navegador, para detectar qué sílabas cuestan más.

## Cómo se usa

1. Elige el modo: **Palabras al azar** genera una ronda de 5 palabras con un clic; **Texto
   propio** convierte cualquier párrafo que escribas o pegues.
2. Elige el silabario (hiragana o katakana) y, si quieres, filtra qué filas del silabario
   entran en práctica.
3. Lee el kana generado y escribe la transcripción en romaji en el cuadro de respuesta.
4. Pulsa **Corregir** (o Ctrl/Cmd+Enter) para ver el resultado kana por kana, o **Mostrar
   solución** para revelar la respuesta completa sin que cuente en las estadísticas.

<table>
<tr>
<th>Palabras al azar</th>
<th>Texto propio</th>
</tr>
<tr>
<td><img src="docs/screenshots/random-mode.png" width="420" alt="Modo Palabras al azar, con el kana visible y el español oculto"></td>
<td><img src="docs/screenshots/text-mode.png" width="420" alt="Modo Texto propio con un párrafo generado y parte de la transcripción escrita"></td>
</tr>
</table>

## De español a kana

La app no traduce: reescribe cada palabra en español como una secuencia de sílabas romaji
canónicas (reglas fijas como c/qu→k, g/j→h, ll→y, ñ→ny) y esas sílabas se convierten a kana con
[wanakana](https://github.com/WaniKani/WanaKana). El resultado suena parecido en japonés, no
significa lo mismo.

| Español | Kana | Romaji |
|---|---|---|
| casa | かさ | ka-sa |
| tres | とれす | to-re-su |
| hola | おら | o-ra |
| luna | るな | ru-na |
| jugo | ふご | fu-go |
| canción | かんしおん | ka-n-shi-o-n |

El tutorial de la app (pestaña **Reglas**) documenta cada regla con ejemplos calculados en
vivo por el mismo código, para que nunca queden desincronizados.

## Funciones

- **Variantes aceptadas al corregir:** shi/si, chi/ti, tsu/tu, fu/hu, ji/zi, sha/sya, n/nn, y
  `n'` antes de vocal o "y" (por ejemplo, `kon'yu`).
- **Estadísticas por kana:** cada silabario guarda su propio historial de aciertos/errores en
  `localStorage`, ordenado de mayor a menor porcentaje de error.
- **Filtro por filas:** puedes limitar la práctica a filas concretas del silabario (por
  ejemplo, solo あ/か/さ mientras aprendes las primeras).
- **Tutorial integrado:** guía rápida, tabla completa de kana (con conmutador
  hiragana/katakana) y las reglas de adaptación con ejemplos. Se abre solo en la primera
  visita y siempre se puede reabrir con el botón de la cabecera.
- **Responsive:** la interfaz se adapta a pantallas de escritorio y móviles.

<table>
<tr>
<th>Tutorial (pestaña Tabla)</th>
<th>Móvil</th>
</tr>
<tr>
<td><img src="docs/screenshots/tutorial.png" width="420" alt="Diálogo de tutorial abierto en la pestaña Tabla"></td>
<td><img src="docs/screenshots/mobile.png" width="180" alt="La app en un viewport móvil, modo Palabras al azar"></td>
</tr>
</table>

Katakana funciona igual que hiragana, con el mismo texto o la misma ronda:

<img src="docs/screenshots/katakana.png" width="480" alt="El mismo texto de ejemplo generado en katakana">

## Flujo de datos

```mermaid
flowchart LR
  A["Texto propio / palabra al azar"] --> B["translit.js<br/>sílabas romaji canónicas"]
  B --> C["kana.js + wanakana<br/>kana (hiragana/katakana)"]
  C --> D["El usuario transcribe en romaji"]
  D --> E["check.js<br/>corrección kana por kana"]
  E --> F["stats.js<br/>estadísticas por kana"]
```

## Ejecutar en local

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

El reporte HTML generado (`playwright-report/index.html`) es el artefacto verificable de cada
corrida.

Para correr la misma suite contra producción:

```bash
BASE_URL=https://kana-practice-green.vercel.app npx playwright test
```

## Stack

- HTML + CSS + JavaScript con módulos ES, sin framework ni paso de build.
- [wanakana](https://github.com/WaniKani/WanaKana) 5.3.1, vendorizada en
  `vendor/wanakana-5.3.1.js` (única dependencia de runtime).
- [Playwright](https://playwright.dev/) para las pruebas E2E.
- Deploy en [Vercel](https://vercel.com/), automático desde `main`.

## Estructura del proyecto

```
index.html          Marcado y estructura de la página
style.css            Estilos
src/
  app.js             Conecta la UI con el resto de módulos
  translit.js         Español -> sílabas romaji canónicas
  kana.js             Sílabas romaji -> unidades de kana (usa wanakana)
  check.js            Corrección kana por kana
  stats.js            Estadísticas por kana (localStorage)
  words.js            Banco de palabras para el modo al azar
vendor/
  wanakana-5.3.1.js    Dependencia vendorizada
tests/e2e/           Suite Playwright
docs/screenshots/    Capturas usadas en este README
```

## Licencia

MIT, ver [LICENSE](LICENSE). Incluye wanakana 5.3.1 (MIT) en `vendor/`.

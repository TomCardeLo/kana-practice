# Kana Practice — Plan

Web sencilla para practicar la **lectura de kana**. El usuario escribe un texto en español, la app lo adapta fonéticamente al japonés y lo muestra en **hiragana o katakana** (a elección). El usuario lo transcribe de vuelta a romaji y la app corrige kana por kana.

## 1. Objetivo y alcance

- Practicar la lectura de kana, no vocabulario ni traducción.
- Conversión **fonética** (opción B): "gato" → *gato* → がと / ガト. No se traduce nada.
- Sin backend, sin cuentas, sin costos. Todo corre en el navegador.

## 2. Flujo principal

La app tiene **dos modos de práctica**, en pestañas:

**Modo A — Palabras al azar (por defecto).** La app elige una ronda de 5 palabras de `words.js` y muestra **solo el kana**. El español **no aparece en ningún momento antes de corregir**: si el usuario viera la palabra en español, adivinaría la lectura sin leer el kana. Tras "Corregir" o "Mostrar solución" se revela la palabra en español bajo cada grupo de kana. Botón "Nueva ronda".

**Modo B — Texto propio.** El usuario pega o escribe un párrafo o texto largo en español; la app muestra su conversión a kana (respetando saltos de línea como separación visual) y el usuario lo transcribe.

Pasos comunes:
1. Elegir modo y silabario: **Hiragana** o **Katakana**.
2. La app convierte: español → romaji (reglas propias, §3) → kana (wanakana).
3. Se muestra el kana. El romaji intermedio queda oculto.
4. El usuario escribe su transcripción en romaji.
5. La app corrige **kana por kana**: verde = correcto, rojo = error (se muestra el romaji esperado en ese kana).
6. Botón "Mostrar solución" para ver el romaji completo (y, en modo A, las palabras en español).

## 3. Reglas de adaptación español → romaji

Preprocesado: pasar a minúsculas, quitar tildes (`á→a`, `ü→u`), conservar `ñ`. Espacios y puntuación separan palabras y se mantienen.

Solo se usan kana básicos (gojūon + dakuten + combinaciones ゃゅょ), sin katakana extendido (ティ, ファ…), para que funcione igual en hiragana.

| Español | Romaji | Ejemplo |
|---|---|---|
| vocales | igual | `casa` → kasa |
| `c` + a/o/u, `qu` + e/i, `k` | k | `queso` → keso |
| `c` + e/i, `z`, `s` | s (`si` → shi) | `cine` → shine, `zapato` → sapato |
| `g` + a/o/u, `gu` + e/i | g | `guitarra` → gitara |
| `g` + e/i, `j` | h (`ju` → fu) | `jugo` → fugo, `gente` → hente |
| `h` | muda | `hola` → ora |
| `l`, `r`, `rr` | r | `perro` → pero, `luna` → runa |
| `v`, `b` | b | `vaca` → baka |
| `ll`, `y` + vocal | y (`ye` → ie, `yi` → i) | `llave` → yabe |
| `y` final o sola | i | `rey` → rei |
| `ñ` | ny (`ñe` → nie, `ñi` → ni) | `niño` → ninyo |
| `ch` | ch (`che` → chie) | `leche` → rechie |
| `t` + i / u | chi / tsu | `tina` → china |
| `d` + i / u | ji / zu | `dime` → jime |
| `f` | fu + vocal (`fa` → fua) | `foto` → fuoto |
| `x` | kus | `taxi` → takushi |
| `w` | u | `web` → uebu |
| consonante sin vocal (grupos) | + u (t/d → + o) | `tres` → toresu, `plato` → purato |
| `n` final o antes de consonante | n (ん) | `canto` → kanto |
| otra consonante final | + u (t/d → + o) | `sol` → soru, `red` → redo |

Las reglas se aplican en ese orden de prioridad (dígrafos `ch`, `ll`, `rr`, `qu`, `gu` antes que letras sueltas). La tabla vive en un único módulo (`translit.js`) para poder ajustarla sin tocar el resto.

## 4. Corrección

- La salida en kana se guarda como lista de unidades `{ kana, romaji }` (p. ej. `{ "しゃ", "sha" }`, `{ "っ", "" }`), no como texto plano. Así cada kana sabe qué romaji espera.
- La respuesta del usuario se normaliza (minúsculas, sin espacios extra) y se compara unidad por unidad.
- **Variantes aceptadas** para el mismo kana: shi/si, chi/ti, tsu/tu, fu/hu, ji/zi/di, zu/du, sha/sya, cha/tya, ja/zya/jya, n/nn (ん), o/wo (を).
- Resultado: cada kana marcado como correcto o incorrecto + contador de aciertos.

## 5. Funcionalidades extra (incluidas en el plan)

### 5.1 Modo palabras al azar
- Ronda de 5 palabras elegidas de una lista fija en español (`words.js`, ~280 palabras comunes), sin repetir dentro de la ronda.
- El español se oculta hasta corregir o mostrar la solución (ver §2, modo A).
- Si el filtro de filas deja menos de 5 palabras válidas, la ronda usa las que haya; si no queda ninguna, se avisa.

### 5.2 Estadísticas de errores por kana
- Cada corrección registra aciertos y fallos por kana en `localStorage`.
- Panel "Mis estadísticas": lista de kana ordenados por porcentaje de error, separados por hiragana/katakana.
- Botón para reiniciar estadísticas.
- Si `localStorage` no está disponible (modo privado), la app sigue funcionando sin guardar.

### 5.3 Filtro por filas
- Selector de filas del silabario: あ, か, さ, た, な, は, ま, や, ら, わ, + dakuten (が, ざ, だ, ば, ぱ) + combinaciones (ゃゅょ).
- Aplica al modo palabras al azar: solo se eligen palabras cuya conversión use únicamente kana de las filas activas.
- En modo texto propio, los kana fuera del filtro se muestran igual pero atenuados y no cuentan en la corrección ni en las estadísticas.

### 5.4 Tutorial
Botón "Tutorial" en la cabecera que abre un panel (`<dialog>` nativo) con tres pestañas:
- **Cómo funciona:** 4 pasos cortos (elige modo → lee el kana → transcribe en romaji → corrige). Se abre solo en la primera visita (bandera en `localStorage`, con try/catch) y se puede reabrir siempre.
- **Tabla de kana:** hiragana y katakana con su romaji (gojūon, dakuten, combinaciones ゃゅょ). Desde el propio tutorial se puede consultar en cualquier momento; si se abre con una ronda sin corregir, se muestra un aviso de que consultarla cuenta como ayuda.
- **Reglas de adaptación:** versión resumida de la tabla §3 con ejemplos (l→r, j→h, tres→toresu, sol→soru…), para entender por qué un kana es el que es.

## 6. Arquitectura

**Stack:** HTML + CSS + JavaScript (módulos ES) estáticos. Sin framework ni paso de build.

**Dependencia única:** [wanakana](https://github.com/WaniKani/WanaKana) `5.3.1` (versión fija), servida desde el propio repo en `vendor/wanakana-5.3.1.js` (bundle ESM descargado de jsDelivr) para no depender del CDN. Se usa `toHiragana` / `toKatakana` para romaji → kana.

```
kana_practice/
├── index.html          # UI: entrada, selector de silabario, filtro, práctica, estadísticas
├── style.css
├── vendor/wanakana-5.3.1.js
├── src/
│   ├── app.js          # conecta UI y lógica
│   ├── translit.js     # español → romaji (tabla §3)
│   ├── kana.js         # romaji → unidades {kana, romaji} con wanakana
│   ├── check.js        # corrección kana por kana + variantes
│   ├── stats.js        # estadísticas en localStorage
│   └── words.js        # lista de palabras para modo al azar
├── tests/e2e/          # Playwright
├── playwright.config.js
├── package.json        # solo devDependencies de testing
└── plan.md
```

**Repositorio y deploy:**
- Repositorio **público** en GitHub (`kana-practice`), rama principal `main`.
- Proyecto en **Vercel** conectado al repo de GitHub, tipo "Other" (sitio estático, sin comando de build, directorio de salida la raíz).
- Cada push a `main` → deploy a producción. Cada PR → deploy de vista previa.
- `.vercelignore` para excluir `tests/`, `node_modules/` y reportes de Playwright.

## 7. Pruebas

Pruebas **E2E con Playwright** como único mecanismo (sin unit tests).

Antes de implementar `translit.js` y `check.js` se escribe la lista de formas en que pueden fallar (en `tests/e2e/failure-modes.md`), por ejemplo:
- Dígrafos mal priorizados (`ch` convertido como `c` + `h`).
- Grupos consonánticos sin vocal insertada (`tres` → `tres` en lugar de `toresu`).
- Consonante final perdida o mal adaptada.
- ん antes de vocal confundida con な行 (`kan'i` vs `kani`).
- っ y combinaciones ゃゅょ desalineadas al corregir.
- Variante válida marcada como error (`si` por `shi`).
- Estadísticas que no persisten o rompen la app sin `localStorage`.
- Filtro por filas que deja pasar kana fuera del filtro.

Escenarios E2E (en ambos silabarios):
1. Texto libre → kana correcto → transcripción perfecta → todo en verde.
2. Transcripción con errores → solo los kana fallados en rojo.
3. Transcripción con variantes (si/tu/hu) → aceptadas.
4. Palabra al azar con filtro de filas activo → solo kana permitidos.
5. Estadísticas se acumulan, persisten al recargar y se reinician.

Artefacto: reporte HTML de Playwright (`npx playwright test` lo regenera), con `trace: 'retain-on-failure'` y capturas en 375 px y 1440 px.

## 8. Fases

1. **Base:** `git init`, repo público en GitHub, proyecto en Vercel conectado. `index.html` mínimo desplegado.
2. **Conversión:** `translit.js` + `kana.js`; mostrar kana en hiragana/katakana.
3. **Práctica y corrección:** `check.js`, romaji oculto, resaltado por kana, botón de solución.
4. **Extras:** modos (palabras al azar / texto propio), filtro por filas, estadísticas, tutorial.
5. **Pruebas E2E** y reporte.
6. **Diseño visual** y adaptación a móvil.

## 9. Fuera de alcance

- Traducción real al japonés.
- Kanji.
- Katakana extendido (ティ, ファ, ヴ…).
- Vocales largas (ー) y acento tonal.
- Cuentas de usuario o sincronización entre dispositivos.

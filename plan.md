# Kana Practice — Plan

Web sencilla para practicar la **lectura de kana**. El usuario escribe un texto en español, la app lo adapta fonéticamente al japonés y lo muestra en **hiragana o katakana** (a elección). El usuario lo transcribe de vuelta a romaji y la app corrige kana por kana.

## 1. Objetivo y alcance

- Practicar la lectura de kana, no vocabulario ni traducción.
- Conversión **fonética** (opción B): "gato" → *gato* → がと / ガト. No se traduce nada.
- Sin backend, sin cuentas, sin costos. Todo corre en el navegador.

## 2. Flujo principal

1. El usuario escribe un texto en español (o pide una palabra al azar, ver §5.1).
2. Elige el silabario: **Hiragana** o **Katakana**.
3. La app convierte: español → romaji (reglas propias, §3) → kana (wanakana).
4. Se muestra **solo el kana**. El romaji intermedio queda oculto.
5. El usuario escribe su transcripción en romaji.
6. La app corrige **kana por kana**: verde = correcto, rojo = error (se muestra el romaji esperado en ese kana).
7. Botón "Mostrar solución" para ver el romaji completo.

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

### 5.1 Modo palabra al azar
- Botón "Palabra al azar" que elige una palabra de una lista fija en español (`words.js`, ~200 palabras comunes) y la pasa por el mismo flujo.
- Permite practicar sin tener que inventar texto.

### 5.2 Estadísticas de errores por kana
- Cada corrección registra aciertos y fallos por kana en `localStorage`.
- Panel "Mis estadísticas": lista de kana ordenados por porcentaje de error, separados por hiragana/katakana.
- Botón para reiniciar estadísticas.
- Si `localStorage` no está disponible (modo privado), la app sigue funcionando sin guardar.

### 5.3 Filtro por filas
- Selector de filas del silabario: あ, か, さ, た, な, は, ま, や, ら, わ, + dakuten (が, ざ, だ, ば, ぱ) + combinaciones (ゃゅょ).
- Aplica al modo palabra al azar: solo se eligen palabras cuya conversión use únicamente kana de las filas activas.
- En modo texto libre, los kana fuera del filtro se muestran igual pero atenuados y no cuentan en la corrección ni en las estadísticas.

## 6. Arquitectura

**Stack:** HTML + CSS + JavaScript (módulos ES) estáticos. Sin framework ni paso de build.

**Dependencia única:** [wanakana](https://github.com/WaniKani/WanaKana) `5.3.1` (versión fija), cargada como módulo desde `cdn.jsdelivr.net`. Se usa `toHiragana` / `toKatakana` para romaji → kana.

```
kana_practice/
├── index.html          # UI: entrada, selector de silabario, filtro, práctica, estadísticas
├── style.css
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
4. **Extras:** modo palabra al azar, filtro por filas, estadísticas.
5. **Pruebas E2E** y reporte.
6. **Diseño visual** y adaptación a móvil.

## 9. Fuera de alcance

- Traducción real al japonés.
- Kanji.
- Katakana extendido (ティ, ファ, ヴ…).
- Vocales largas (ー) y acento tonal.
- Cuentas de usuario o sincronización entre dispositivos.

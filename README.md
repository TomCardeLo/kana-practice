# Kana Practice

Web estática para practicar la lectura de kana (hiragana y katakana). Escribe un texto en
español, la app lo adapta fonéticamente al japonés y lo muestra en kana. Después transcribes
de vuelta a romaji y la app corrige kana por kana. No traduce nada, no usa kanji.

Sin backend, sin cuentas: todo corre en el navegador. HTML + CSS + JavaScript con módulos ES,
sin framework ni paso de build. Única dependencia: [wanakana](https://github.com/WaniKani/WanaKana)
cargada desde un CDN.

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

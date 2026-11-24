# Datos de vocabulario y kanji (fase 4)

`vocabulario-n5.json` y `kanji-n5.json` se generan con `node scripts/vocab/construir.mjs` a partir de:

- **Lista JLPT N5** de Jonathan Waller (tanos.co.uk), en la versión mantenida por
  [open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks) (licencia MIT), commit fijado en el script.
  El JLPT no publica listas oficiales desde 2010: es una estimación de la comunidad.
- **JMdict** y **KANJIDIC2**, del Electronic Dictionary Research and Development Group (EDRDG),
  <https://www.edrdg.org/>, bajo licencia [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
  Los kanji son el antiguo nivel 4 del JLPT (anterior a 2010), equivalente aproximado al N5 actual.

Los significados en español que faltaban en JMdict (`traducciones-claude.json`) y las correcciones de los que eran de
otro sentido o regionales (`revision-claude.json`) los hizo Claude y los revisó el usuario el 2026-11-12. Al derivar de
JMdict y KANJIDIC2, los dos JSON generados se comparten bajo la misma licencia CC BY-SA 4.0.

# Trazos de los kana («Escribir», app iOS)

`trazos-kana.json` se genera con `node scripts/trazos/construir.mjs` a partir de **KanjiVG**, de Ulrich Apel
(<https://kanjivg.tagaini.net>, commit fijado en el script), bajo licencia
[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). Cada trazo del SVG se convierte en una polilínea en
el mismo orden; al derivar de KanjiVG, el JSON se comparte bajo la misma licencia CC BY-SA 3.0.

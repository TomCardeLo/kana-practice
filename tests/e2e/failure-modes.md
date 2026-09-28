# Modos de fallo (escritos antes de implementar)

## translit.js (español → sílabas romaji)
1. Dígrafos mal priorizados: `ch`, `ll`, `rr`, `qu`, `gu` convertidos letra por letra (`leche` → `rekhe`).
2. `c`/`g` ignoran la vocal siguiente (`cine` → `kine`, `gente` → `gente`).
3. `gue`/`gui` conservan la `u` (`guitarra` → `guitara`).
4. `h` no se omite (`hola` → `hora` con h pronunciada, o sílaba suelta `h`).
5. Grupos consonánticos sin vocal insertada (`tres` → `tres`); `t`/`d` insertan `u` en vez de `o` (`tres` → `turesu`).
6. Consonante final perdida (`sol` → `so`) o `n` final convertida en `nu` en vez de `ん`.
7. `n` antes de vocal confundida con `ん` (`luna` → `ru` + `ん` + `a`).
8. `si`/`ti`/`tu`/`di`/`du`/`hu`/`fa` generan sílabas que no existen en kana básico.
9. Tildes y diéresis no normalizadas (`canción` rompe la conversión); `ñ` perdida al quitar tildes.
10. Mayúsculas, puntuación, números o emojis rompen la conversión en vez de ignorarse o separar palabras.
11. Texto vacío o solo espacios produce una práctica vacía en lugar de un aviso.
12. `y` como vocal (`rey`, `y`) tratada como consonante.

## kana.js (sílabas → kana)
13. Hiragana y katakana no coinciden sílaba a sílaba.
14. `n` suelta no se convierte en `ん`/`ン`.
15. Combinaciones `sha`/`nyo`/`cho` separadas en dos kana grandes (`しや` en vez de `しゃ`).

## check.js (corrección)
16. Variante válida marcada como error: si/shi, ti/chi, tu/tsu, hu/fu, zi/ji, di/ji, du/zu, sya/sha, tya/cha, zya/ja, nn/n.
17. Un kana faltante o sobrante desalinea el resto de la palabra (todo en rojo en cascada).
18. Mayúsculas o espacios extra en la respuesta cuentan como error.
19. Letras sueltas sin convertir (`k`) se ignoran en vez de marcarse como error.
20. Respuesta vacía se acepta como corrección válida.

## stats.js
21. Estadísticas no persisten al recargar.
22. Sin `localStorage` (modo privado / acceso bloqueado) la app se rompe.
23. Hiragana y katakana se mezclan en el mismo contador.
24. Reiniciar no borra todo.

## Filtro por filas
25. Palabra al azar contiene kana fuera de las filas activas.
26. Ninguna palabra cumple el filtro y la app se queda colgada en un bucle.
27. En texto libre, kana fuera del filtro cuentan en la corrección o en las estadísticas.
28. Filtro sin filas seleccionadas no avisa.

## Minijuego de tarjetas (tarjetas.html)
29. Una tarjeta se repite dentro de la misma ronda (o «Full» no recorre el mazo completo).
30. «Básicos» incluye dakuten o combinados, o «Todos» omite alguno de los 102 kana (ぢ/づ se fusionan con じ/ず).
31. «Ambos» solo muestra un silabario, o una tarjeta se registra en el silabario equivocado de las estadísticas.
32. Una variante válida (si, ti, tu, hu, zi, sya, tya, zya, nn) se marca como error en una tarjeta.
33. Una sílaba a medio escribir (`k`, `sh`, `ky`) cuenta como error o avanza la tarjeta; `ki` se acepta ante きゃ, o `o` se acepta ante を.
34. Un error no resta vida, resta más de una, o la ronda sigue con 0 vidas.
35. Tras un error no se muestra el romaji correcto, o el campo acepta texto mientras se muestra y ese texto cuenta para la tarjeta siguiente.
36. El tiempo incluye la pausa de la respuesta tras un error, o es negativo/NaN.
37. El récord se guarda con una ronda perdida, o una ronda más lenta sobrescribe un récord mejor.
38. Récords de combinaciones distintas (silabario, mazo, tamaño) se pisan entre sí.
39. Enter con el campo vacío cuenta como error.
40. Sin localStorage, el minijuego no arranca.
41. Empezar otra ronda conserva vidas, progreso o tiempos de la anterior.

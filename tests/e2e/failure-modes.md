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

## App iOS (fase 1, escritos antes del port a Swift)

### Romaji.swift (sustituye a wanakana)
42. Las variantes kunrei/nihon-shiki (si, tu, hu, zi, di, du, sya, tya, zya, jya, cya) dan otro kana
    que wanakana; la conversión nativa de iOS (ICU) falla justo aquí (`si` → せぃ), por eso no se usa.
43. Una consonante suelta al final (`k`, `sh`, `ky`) se convierte en kana (ICU: `k` → く) en vez de
    quedarse en latín, y una sílaba a medio escribir avanza la tarjeta o cuenta como unidad completa.
44. `n` antes de vocal o `y` se convierte en ん; `n'` no separa (`kan'yu` → かにゅ); `nn` final o
    ante consonante deja una ん de más.
45. Consonante doble (`kka`, `tta`, `cchi`) no produce っ, o `nn` produce っん.
46. `toRomaji` de una unidad escrita no coincide con el romaji Hepburn que muestra la web
    (`escribiste: si` en vez de `shi`).

### Paridad con la web
47. `Translit`, `Kana` o `Check` en Swift dan un resultado distinto al JS para la misma entrada.
    Se verifica con `ios/Paridad/paridad.json`, generado desde los módulos JS reales
    (`npm run paridad`), y `ios/scripts/paridad.sh` lo compara contra el código Swift.

### Progreso local (SwiftData)
48. Un intento no se guarda (o se guarda dos veces) al acertar, fallar, saltar o corregir.
49. Al recalcular una corrección (cambio de filtro o silabario) se vuelven a registrar intentos.
50. «Mostrar solución» registra intentos.
51. Los intentos de hiragana y katakana se mezclan en las estadísticas.
52. Cerrar la app a mitad de una ronda pierde los intentos ya respondidos.
53. Cada intento no lleva lo que necesitará la sincronización de la fase 2 (id único, fecha,
    dispositivo, ejercicio, latencia, marca de sincronizado).

### Interfaz
54. El teclado autocorrige o pone mayúscula inicial y altera la respuesta.
55. En el iPad la pantalla queda como un iPhone estirado, o algo se corta al girarlo.
56. El temporizador de la tarjeta sigue corriendo con la app en segundo plano y se cuenta en la
    latencia.

## Enganche: sonido, rachas, mensajes e hitos (escritos antes del código)

### Sonido y vibración
57. Suena con el interruptor de silencio activado, o corta la música que el usuario está escuchando
    (categoría de sesión de audio equivocada: debe ser `.ambient`).
58. Suena o vibra con el ajuste correspondiente desactivado.
59. El primer sonido llega tarde (motor sin arrancar) o respuestas muy seguidas se cortan o se pisan mal.
60. Tras una interrupción (llamada, Siri) el motor queda detenido y no vuelve a sonar nada.

### Rachas y meta diaria (meta: 50 respuestas)
61. El cambio de día se calcula en UTC y no en la zona local: la racha se rompe a media tarde en Bogotá.
62. Hoy todavía sin la meta rompe la racha antes de que termine el día (debe seguir viva desde ayer).
63. Un día con menos de 50 respuestas cuenta para la racha, o un día sin práctica no la reinicia.
64. El aviso de «meta cumplida» sale más de una vez el mismo día, o no sale al llegar justo a 50.
65. Borrar el progreso deja rachas, récords o hitos de antes.

### Combo dentro de la ronda
66. El combo no se reinicia con un error o un «No la sé», o pasa de una ronda a la siguiente.

### Mensajes al terminar
67. El mensaje contradice el resultado (felicita al perder todas las vidas, anuncia un récord que no hubo,
    llama «perfecta» a una ronda con errores).

### Hitos (fila dominada)
68. Un hito se anuncia más de una vez, con datos insuficientes (un solo intento), o mezclando hiragana y
    katakana.
69. Un kana de la fila que nunca se ha practicado no impide que la fila cuente como dominada.

### Confeti
70. Ignora «Reducir movimiento» o bloquea los toques mientras cae.

### Conexión de las piezas a las pantallas (escritos antes del código)
71. Al bajar historial (reinstalar, o respuestas del otro equipo) se anuncian de golpe la meta o hitos
    viejos que no se lograron en este momento ni en este equipo.
72. La meta se cumple a mitad de ronda y el aviso no aparece, aparece solo al salir, o tapa la tarjeta
    y bloquea el campo de respuesta.
73. El combo se muestra con menos de 3 aciertos seguidos o sigue visible después de un error.
74. El mensaje de fin cambia mientras se mira el resumen (se vuelve a sortear en cada redibujado) o
    usa el récord ya actualizado para decir «a un paso del récord».
75. La cabecera de racha no refleja las respuestas recién guardadas o las del otro equipo ya bajadas.

## Fase 3a: repaso espaciado (FSRS) y «Hoy» (escritos antes del código)
76. El port de FSRS a Swift se aparta de `ts-fsrs` 5.4.2 (parámetros, redondeos, orden de intervalos
    otra vez ≤ difícil < bien < fácil): repasos en días equivocados.
77. Respuestas con la misma fecha (una lectura las guarda todas juntas) se ordenan distinto en el
    iPhone y en el iPad, y los dos equipos proponen repasos distintos.
78. Muchas respuestas al mismo kana el mismo día cuentan como muchos repasos e inflan la estabilidad.
79. Las respuestas de lectura (sin latencia) rompen el cálculo o se califican como «difícil»/«otra vez».
80. Lo que no es una tarjeta del mazo (っ suelta, ー, signos) aparece como tarjeta o rompe el plan.
81. Se introducen más kana nuevos al día que el tope, el tope se reinicia al reabrir la app, o el
    orden de los nuevos es al azar en vez de seguir la tabla (hiragana básico primero).
    (El tope limita los nuevos que propone «Hoy»; un kana visto por primera vez en una ronda libre o en
    una lectura también cuenta como introducido ese día.)
86. Las unidades de una lectura que no se llegaron a escribir cuentan como repasos fallidos.
82. En el repaso, fallar quita vidas y corta la sesión, o la sesión guarda un récord de ronda libre.
83. Al volver de la sesión, «Hoy» sigue mostrando como pendientes los kana ya repasados.
84. El día del repaso se calcula en UTC y no en la zona local.
85. El plan se recalcula con cada respuesta guardada durante la ronda y retrasa la tarjeta siguiente.

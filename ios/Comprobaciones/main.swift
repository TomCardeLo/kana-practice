import Foundation

// Comprobaciones de la lógica de enganche (rachas, hitos, mensajes, combo) contra los modos de fallo
// 61–69 de tests/e2e/failure-modes.md. Uso: ios/scripts/comprobar_enganche.sh
var fallos = 0
func comprobar(_ ok: Bool, _ que: String, linea: Int = #line) {
    if !ok { fallos += 1; print("✗ [\(linea)] \(que)") }
}

var bogota = Calendar(identifier: .gregorian)
bogota.timeZone = TimeZone(identifier: "America/Bogota")!
func fecha(_ texto: String) -> Date {  // "2026-11-10 19:30" en hora de Bogotá
    let f = DateFormatter(); f.calendar = bogota; f.timeZone = bogota.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: texto)!
}
func dia(_ d: String, _ n: Int, hora: String = "10:00") -> [Date] { Array(repeating: fecha("\(d) \(hora)"), count: n) }

// 61: 50 respuestas a las 19:30 de Bogotá (00:30 UTC del día siguiente) cuentan para ese día local.
let ahora61 = fecha("2026-11-10 21:00")
var e = Rachas.calcular(dia("2026-11-10", 50, hora: "19:30"), ahora: ahora61, calendario: bogota)
comprobar(e.hoy == 50 && e.racha == 1 && e.metaCumplida, "61: el día se cuenta en la zona local (\(e))")

// 61: en Santiago de Chile el 2026-09-06 el reloj salta de 23:59 a 01:00 (el día empieza a la 01:00):
// seis días seguidos alrededor del salto son una racha de 6, no se parte en dos.
var santiago = Calendar(identifier: .gregorian)
santiago.timeZone = TimeZone(identifier: "America/Santiago")!
let mediodia = { (d: Int) in santiago.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))! }
e = Rachas.calcular((3 ... 8).flatMap { Array(repeating: mediodia($0), count: 50) }, ahora: mediodia(8), calendario: santiago)
comprobar(e.racha == 6 && e.mejor == 6, "61: el cambio de horario a medianoche no corta la racha (\(e))")

// 62: ayer y anteayer cumplidos, hoy 10: la racha sigue en 2 y no se rompe.
let ahora = fecha("2026-11-12 09:00")
e = Rachas.calcular(dia("2026-11-10", 50) + dia("2026-11-11", 60) + dia("2026-11-12", 10), ahora: ahora, calendario: bogota)
comprobar(e.racha == 2 && e.hoy == 10 && !e.metaCumplida && e.faltan == 40, "62: hoy sin la meta no rompe la racha (\(e))")
// Al cumplir hoy, pasa a 3.
e = Rachas.calcular(dia("2026-11-10", 50) + dia("2026-11-11", 60) + dia("2026-11-12", 50), ahora: ahora, calendario: bogota)
comprobar(e.racha == 3 && e.mejor == 3, "62: cumplir hoy suma a la racha (\(e))")

// 63: un día con 49 no cuenta; un día sin práctica reinicia.
e = Rachas.calcular(dia("2026-11-10", 50) + dia("2026-11-11", 49), ahora: ahora, calendario: bogota)
comprobar(e.racha == 0 && e.mejor == 1, "63: 49 respuestas no cumplen la meta (\(e))")
e = Rachas.calcular(dia("2026-11-08", 50) + dia("2026-11-09", 50) + dia("2026-11-11", 50), ahora: ahora, calendario: bogota)
comprobar(e.racha == 1 && e.mejor == 2, "63: un día sin práctica reinicia la racha (\(e))")
e = Rachas.calcular([], ahora: ahora, calendario: bogota)
comprobar(e == Rachas.Estado(hoy: 0, racha: 0, mejor: 0), "65: sin intentos no hay racha")

// 66: el combo se reinicia con un error y no pasa a la ronda siguiente.
var ronda = RondaTarjetas(config: .init(silabario: .hiragana, mazo: .basicos, tamano: .diez))
ronda.acertar(ms: 500); ronda.acertar(ms: 500); ronda.acertar(ms: 500)
comprobar(ronda.combo == 3 && ronda.mejorCombo == 3, "66: tres aciertos dan combo 3")
ronda.fallar(ms: 500)
comprobar(ronda.combo == 0 && ronda.mejorCombo == 3, "66: un error reinicia el combo y conserva el mejor")
comprobar(RondaTarjetas(config: ronda.config).combo == 0, "66: una ronda nueva empieza sin combo")

// 67: los mensajes no contradicen el resultado (se revisan todas las variantes).
func todas(_ f: Mensajes.FinTarjetas) -> [String] {
    var vistas: [String] = []
    _ = Mensajes.tarjetas(f) { opciones in vistas = opciones; return opciones[0] }
    return vistas
}
let perdida = todas(.init(completa: false, aciertos: 4, total: 10, recordNuevo: false, mediaMs: 900, recordAnteriorMs: 800, mejorCombo: 2))
comprobar(perdida.allSatisfy { !$0.localizedCaseInsensitiveContains("récord") && !$0.contains("perfect") && !$0.contains("completada") },
          "67: al perder no se felicita ni se anuncia récord: \(perdida)")
let conErrores = todas(.init(completa: true, aciertos: 8, total: 10, recordNuevo: false, mediaMs: 2000, recordAnteriorMs: 900, mejorCombo: 5))
comprobar(conErrores.allSatisfy { !$0.contains("perfect") && !$0.contains("Ni un error") && !$0.contains("Nuevo récord") },
          "67: una ronda con errores no es perfecta ni récord: \(conErrores)")
let record = todas(.init(completa: true, aciertos: 9, total: 10, recordNuevo: true, mediaMs: 700, recordAnteriorMs: 900, mejorCombo: 5))
comprobar(record.allSatisfy { $0.localizedCaseInsensitiveContains("récord") }, "67: el récord se anuncia: \(record)")
comprobar(!Mensajes.lectura(correctas: 3, total: 4) { $0[0] }.contains("perfect"), "67: lectura con errores no es perfecta")

// 68 y 69: hitos.
let filaA = ["あ", "い", "う", "え", "お"]
func practicar(_ kanas: [String], _ s: Silabario, veces: Int, ok: Bool = true, ms: Int = 1200) -> [Respuesta] {
    kanas.flatMap { k in (0 ..< veces).map { i in
        Respuesta(fecha: Date(timeIntervalSince1970: Double(i)), item: k, silabario: s, correcto: ok, ejercicio: "tarjeta", latenciaMs: ms)
    } }
}
comprobar(Hitos.dominadas(practicar(filaA, .hiragana, veces: 1)).isEmpty, "68: un solo intento no domina la fila")
let dominaA = Hitos.dominadas(practicar(filaA, .hiragana, veces: 6))
comprobar(dominaA == [Hitos.Hito(fila: "a", silabario: .hiragana)], "68: seis aciertos rápidos dominan la fila あ: \(dominaA)")
comprobar(Hitos.dominadas(practicar(filaA, .hiragana, veces: 6)).allSatisfy { $0.silabario == .hiragana },
          "68: dominar hiragana no domina katakana")
comprobar(Hitos.dominadas(practicar(Array(filaA.prefix(4)), .hiragana, veces: 8)).isEmpty, "69: falta お: la fila no está dominada")
comprobar(Hitos.dominadas(practicar(filaA, .hiragana, veces: 6, ms: 5000)).isEmpty, "68: leer lento no domina la fila")
comprobar(Hitos.dominadas(practicar(filaA, .hiragana, veces: 6) + practicar(["う"], .hiragana, veces: 2, ok: false)
    .map { Respuesta(fecha: Date(timeIntervalSince1970: 100), item: $0.item, silabario: $0.silabario, correcto: false, ejercicio: "tarjeta", latenciaMs: nil) }).isEmpty,
          "68: dos errores recientes en う quitan el dominio")

comprobarTrazos()

print(fallos == 0 ? "✓ Enganche y trazos: todas las comprobaciones pasan" : "✗ \(fallos) comprobaciones fallan")
exit(fallos == 0 ? 0 : 1)

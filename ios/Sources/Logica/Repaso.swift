import Foundation

/// Port del planificador de largo plazo de `ts-fsrs` 5.4.2 (FSRS-6, sin pasos cortos ni fuzz), verificado
/// contra la librería por `ios/scripts/paridad.sh` (modo de fallo 76). Trabaja en días enteros.
enum FSRS {
    enum Nota: Int, CaseIterable { case otraVez = 1, dificil, bien, facil }

    struct Memoria: Equatable {
        let dificultad: Double
        let estabilidad: Double
    }

    /// Parámetros por defecto de ts-fsrs 5.4.2 (`default_w`).
    static let w: [Double] = [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
                              1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]
    static let retencion = 0.9
    static let intervaloMaximo = 36500
    private static let sMin = 0.001
    private static let decaimiento = -w[20]
    private static let factor = redondear(exp(log(0.9) / decaimiento) - 1)
    private static let modificador = redondear((pow(retencion, 1 / decaimiento) - 1) / factor)

    private static func redondear(_ x: Double) -> Double { (x * 1e8).rounded(.toNearestOrAwayFromZero) / 1e8 }
    private static func acotar(_ x: Double, _ a: Double, _ b: Double) -> Double { min(max(x, a), b) }
    /// `Math.round` de JS: las mitades suben (también las negativas, que aquí no hay).
    private static func redondearJS(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    static func recuerdo(dias t: Int, _ s: Double) -> Double {
        redondear(pow(1 + factor * Double(t) / s, decaimiento))
    }

    private static func dificultadInicial(_ g: Nota) -> Double { redondear(w[4] - exp(Double(g.rawValue - 1) * w[5]) + 1) }

    private static func siguienteDificultad(_ d: Double, _ g: Nota) -> Double {
        let delta = -w[6] * Double(g.rawValue - 3)
        let siguiente = d + redondear(delta * (10 - d) / 9)
        return acotar(redondear(w[7] * dificultadInicial(.facil) + (1 - w[7]) * siguiente), 1, 10)
    }

    private static func estado(_ m: Memoria?, dias t: Int, _ g: Nota, r: Double) -> Memoria {
        guard let m else {
            return Memoria(dificultad: acotar(dificultadInicial(g), 1, 10), estabilidad: max(w[g.rawValue - 1], 0.1))
        }
        let (d, s) = (m.dificultad, m.estabilidad)
        let nuevaS: Double
        if g == .otraVez {
            let trasFallo = redondear(acotar(w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14]), sMin, 36500))
            nuevaS = acotar(redondear(s), sMin, trasFallo)
        } else {
            let castigo = g == .dificil ? w[15] : 1, premio = g == .facil ? w[16] : 1
            nuevaS = redondear(acotar(s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * castigo * premio),
                                      sMin, 36500))
        }
        return Memoria(dificultad: siguienteDificultad(d, g), estabilidad: nuevaS)
    }

    private static func intervalo(_ s: Double) -> Int { min(max(1, redondearJS(s * modificador)), intervaloMaximo) }

    /// Repaso `g` tras `t` días desde el anterior (`m` nil: primera vez). Devuelve la memoria nueva y en
    /// cuántos días toca otra vez. Calcula las cuatro notas porque los intervalos se ordenan entre sí.
    static func repasar(_ m: Memoria?, dias t: Int, _ g: Nota) -> (memoria: Memoria, dias: Int) {
        let r = m.map { recuerdo(dias: t, $0.estabilidad) } ?? 0
        let todas = Nota.allCases.map { estado(m, dias: t, $0, r: r) }
        var iv = todas.map { intervalo($0.estabilidad) }
        iv[0] = min(iv[0], iv[1])
        iv[1] = max(iv[1], iv[0] + 1)
        iv[2] = max(iv[2], iv[1] + 1)
        iv[3] = max(iv[3], iv[2] + 1)
        return (todas[g.rawValue - 1], iv[g.rawValue - 1])
    }
}

/// Qué repasar hoy a partir de todas las respuestas guardadas (las de los dos equipos). Determinista: con el
/// mismo historial, el iPhone y el iPad proponen lo mismo (modo de fallo 77).
enum Repaso {
    static let nuevasPorDia = 10
    static let maximoPendientes = 40
    /// Con opción múltiple se acierta al azar 1 de cada 4: nunca «fácil»; un acierto lento es «difícil».
    static let bienMs = 2000

    struct Plan: Equatable {
        /// Vencidas, de la más atrasada a la menos.
        let pendientes: [Tarjeta]
        let nuevas: [Tarjeta]
        var sesion: [Tarjeta] { pendientes + nuevas }
    }

    /// Opción múltiple: acierto rápido = bien, lento = difícil, error = otra vez; nunca «fácil» (modo de fallo 94).
    /// Lectura (sin latencia) correcta = bien (modo de fallo 79).
    static func nota(correcto: Bool, latenciaMs: Int?, bienMs: Int = bienMs) -> FSRS.Nota {
        guard correcto else { return .otraVez }
        guard let ms = latenciaMs else { return .bien }
        return ms <= bienMs ? .bien : .dificil
    }

    /// Orden de introducción de los nuevos: tabla de hiragana (básicos primero), luego katakana (modo de fallo 81).
    static let orden: [Tarjeta] = Silabario.allCases.flatMap { s in
        let basicos = Kana.mazo(s, .basicos)
        return basicos + Kana.mazo(s, .todos).filter { !basicos.contains($0) }
    }

    private static let porClave: [String: Tarjeta] = Dictionary(orden.map { ("\($0.silabario.rawValue)|\($0.kana)", $0) }) { a, _ in a }

    /// Un repaso de cualquier mazo: kana («hiragana|か»), palabra («会う|あう») o kanji («会»).
    struct Paso {
        let clave: String
        let fecha: Date
        let correcto: Bool
        let latenciaMs: Int?
    }

    /// Núcleo común a kana, vocabulario y kanji: vencidas (de la más atrasada a la menos, hasta `maximoPendientes`)
    /// y nuevas en el orden de `orden`, con su propio tope diario (modo de fallo 99). Solo cuentan las claves de `orden`.
    /// `bienMs`: hasta cuánto un acierto es «bien» y no «difícil» (un kana se reconoce antes que leer 4 significados).
    static func planificar(_ pasos: [Paso], orden: [String], nuevasPorDia: Int, maximoPendientes: Int = maximoPendientes,
                           bienMs: Int = bienMs, ahora: Date = .now, calendario: Calendar = .current)
        -> (pendientes: [String], nuevas: [String]) {
        // Día local (modo de fallo 84) con el desfase de esa fecha, que ya incluye el cambio de horario. Mucho más
        // barato que Calendar por respuesta (modo de fallo 85).
        let zona = calendario.timeZone
        func dia(_ f: Date) -> Int {
            Int(((f.timeIntervalSince1970 + Double(zona.secondsFromGMT(for: f))) / 86400).rounded(.down))
        }
        let hoy = dia(ahora)
        let validas = Set(orden)

        // Al sincronizar, la fecha viaja redondeada a milisegundos: se compara así para que el equipo que respondió
        // y el que bajó la respuesta ordenen igual. A igual instante, el error primero (modo de fallo 77).
        func ms(_ f: Date) -> Double { (f.timeIntervalSince1970 * 1000).rounded() }
        let ordenados = pasos.sorted {
            (ms($0.fecha), $0.correcto ? 1 : 0, $0.latenciaMs ?? -1) < (ms($1.fecha), $1.correcto ? 1 : 0, $1.latenciaMs ?? -1)
        }
        struct Estado { var memoria: FSRS.Memoria; var dia: Int; var vence: Int; let primerDia: Int }
        var estados: [String: Estado] = [:]
        for p in ordenados where validas.contains(p.clave) {  // modo de fallo 80
            let d = dia(p.fecha)
            let previo = estados[p.clave]
            if let previo, previo.dia == d { continue }  // un repaso por clave y día: el primero (modo de fallo 78)
            let (memoria, dias) = FSRS.repasar(previo?.memoria, dias: previo.map { d - $0.dia } ?? 0,
                                               nota(correcto: p.correcto, latenciaMs: p.latenciaMs, bienMs: bienMs))
            estados[p.clave] = Estado(memoria: memoria, dia: d, vence: d + dias, primerDia: previo?.primerDia ?? d)
        }

        let pendientes = estados.filter { $0.value.vence <= hoy }
            .sorted { ($0.value.vence, $0.key) < ($1.value.vence, $1.key) }
            .prefix(maximoPendientes).map(\.key)
        let nuevasHoy = estados.values.filter { $0.primerDia == hoy }.count
        let nuevas = orden.filter { estados[$0] == nil }.prefix(max(0, nuevasPorDia - nuevasHoy))
        return (Array(pendientes), Array(nuevas))
    }

    static func plan(_ respuestas: [Respuesta], ahora: Date = .now, calendario: Calendar = .current) -> Plan {
        let pasos = respuestas.map { Paso(clave: "\($0.silabario.rawValue)|\($0.item)", fecha: $0.fecha, correcto: $0.correcto,
                                          latenciaMs: $0.latenciaMs) }
        let (pendientes, nuevas) = planificar(pasos, orden: ordenClaves, nuevasPorDia: nuevasPorDia, ahora: ahora,
                                              calendario: calendario)
        return Plan(pendientes: pendientes.compactMap { porClave[$0] }, nuevas: nuevas.compactMap { porClave[$0] })
    }

    private static let ordenClaves = orden.map { "\($0.silabario.rawValue)|\($0.kana)" }
}

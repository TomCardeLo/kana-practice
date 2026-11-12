import Foundation

/// Lo mínimo de un intento que necesitan las rachas y los hitos (sin depender de SwiftData).
struct Respuesta {
    let fecha: Date
    let item: String
    let silabario: Silabario
    let correcto: Bool
    let ejercicio: String
    let latenciaMs: Int?
}

/// Racha diaria: días seguidos cumpliendo la meta. Los días van en la zona local (modo de fallo 61).
enum Rachas {
    static let metaDiaria = 50

    struct Estado: Equatable {
        let hoy: Int
        let racha: Int
        let mejor: Int
        var metaCumplida: Bool { hoy >= Rachas.metaDiaria }
        var faltan: Int { max(0, Rachas.metaDiaria - hoy) }
    }

    static func calcular(_ fechas: [Date], ahora: Date = .now, calendario: Calendar = .current) -> Estado {
        var porDia: [Date: Int] = [:]
        for fecha in fechas { porDia[calendario.startOfDay(for: fecha), default: 0] += 1 }
        let cumplidos = Set(porDia.filter { $0.value >= metaDiaria }.keys)  // modo de fallo 63
        let hoy = calendario.startOfDay(for: ahora)
        // startOfDay otra vez: donde el cambio de horario salta la medianoche, el día empieza a la 01:00 (modo de fallo 61).
        func anterior(_ dia: Date) -> Date { calendario.startOfDay(for: calendario.date(byAdding: .day, value: -1, to: dia)!) }

        // Si hoy aún no se cumplió, la racha sigue viva desde ayer hasta que acabe el día (modo de fallo 62).
        var dia = cumplidos.contains(hoy) ? hoy : anterior(hoy)
        var racha = 0
        while cumplidos.contains(dia) {
            racha += 1
            dia = anterior(dia)
        }

        var mejor = 0, seguidos = 0
        var previo: Date?
        for d in cumplidos.sorted() {
            seguidos = previo.map { calendario.startOfDay(for: calendario.date(byAdding: .day, value: 1, to: $0)!) == d } == true ? seguidos + 1 : 1
            mejor = max(mejor, seguidos)
            previo = d
        }
        return Estado(hoy: porDia[hoy] ?? 0, racha: racha, mejor: mejor)
    }
}

/// Fila dominada: todos sus kana con pocos errores recientes y lectura rápida en tarjetas.
enum Hitos {
    static let minimoIntentos = 5
    static let ventana = 10
    static let aciertoMinimo = 0.9
    static let minimoTarjetas = 3
    static let latenciaMaximaMs = 3000

    struct Hito: Hashable, Comparable {
        let fila: String
        let silabario: Silabario
        var clave: String { "\(silabario.rawValue)-\(fila)" }
        var ejemplo: String { Kana.ejemplo(fila: fila, silabario) }
        static func < (a: Hito, b: Hito) -> Bool { a.clave < b.clave }
    }

    /// kana → fila, por silabario. Las filas no se mezclan entre hiragana y katakana (modo de fallo 68).
    private static let kanaDeFila: [Silabario: [String: [String]]] = Dictionary(uniqueKeysWithValues:
        Silabario.allCases.map { s in
            (s, Dictionary(grouping: Kana.silabaFila, by: \.1).mapValues { $0.map { Kana.silabaAKana($0.0, s) } })
        })

    private static func dominado(_ intentos: [Respuesta]) -> Bool {
        guard intentos.count >= minimoIntentos else { return false }  // modos de fallo 68 y 69
        let recientes = intentos.suffix(ventana)
        let acierto = Double(recientes.filter(\.correcto).count) / Double(recientes.count)
        let tiempos = intentos.filter { $0.correcto && $0.ejercicio == "tarjeta" }.compactMap(\.latenciaMs).suffix(ventana)
        guard acierto >= aciertoMinimo, tiempos.count >= minimoTarjetas else { return false }
        let mediana = tiempos.sorted()[tiempos.count / 2]
        return mediana <= latenciaMaximaMs
    }

    /// Filas dominadas. `respuestas` en cualquier orden: aquí se ordenan por fecha.
    static func dominadas(_ respuestas: [Respuesta]) -> Set<Hito> {
        let porKana = Dictionary(grouping: respuestas.sorted { $0.fecha < $1.fecha }) { "\($0.silabario.rawValue)|\($0.item)" }
        var hitos: Set<Hito> = []
        for (silabario, filas) in kanaDeFila {
            for (fila, kanas) in filas where kanas.allSatisfy({ dominado(porKana["\(silabario.rawValue)|\($0)"] ?? []) }) {
                hitos.insert(Hito(fila: fila, silabario: silabario))
            }
        }
        return hitos
    }
}

/// Mensajes al terminar. Nunca contradicen el resultado (modo de fallo 67).
enum Mensajes {
    struct FinTarjetas {
        let completa: Bool
        let aciertos: Int
        let total: Int
        let recordNuevo: Bool
        let mediaMs: Int
        let recordAnteriorMs: Int?
        let mejorCombo: Int
    }

    static func tarjetas(_ f: FinTarjetas, elegir: ([String]) -> String = { $0.randomElement()! }) -> String {
        if f.completa, f.recordNuevo {
            return elegir([
                "すごい！ Nuevo récord: \(segundos(f.mediaMs)) por tarjeta.",
                "Récord batido: \(segundos(f.mediaMs)) por tarjeta. Cada vez lees más rápido.",
                "¡Nuevo récord! Tu yo de ayer no te alcanza.",
            ])
        }
        if f.completa, f.aciertos == f.total {
            return elegir([
                "Ronda perfecta: \(f.total) de \(f.total). かんぺき (perfecto).",
                "Ni un error. Así se construye la memoria.",
                "\(f.total) de \(f.total). Esto ya no es suerte.",
            ])
        }
        if f.completa, let anterior = f.recordAnteriorMs, f.mediaMs <= anterior * 11 / 10 {
            return elegir([
                "A un paso del récord: \(segundos(f.mediaMs)) frente a \(segundos(anterior)).",
                "Casi récord. La próxima cae.",
            ])
        }
        if f.completa {
            return elegir([
                "Ronda completada. Los errores de hoy son los aciertos de mañana.",
                "Hecho. Repasa los que fallaste y vuelve por más.",
                "おつかれさま (buen trabajo). Ronda completada.",
            ])
        }
        if f.aciertos > 0 {
            return elegir([
                "Sin vidas, pero acertaste \(f.aciertos). がんばって (ánimo): otra ronda.",
                "Se acabaron las vidas en la tarjeta \(f.aciertos + 3). Mira los errores y vuelve a intentarlo.",
            ] + (f.mejorCombo >= 3 ? ["Hiciste un combo de \(f.mejorCombo). Con eso, la próxima ronda es tuya."] : []))
        }
        return elegir([
            "Empezar cuesta. Prueba el mazo de básicos y pocas tarjetas.",
            "Sin vidas esta vez. Revisa la tabla de la fila que más te cuesta y vuelve.",
        ])
    }

    static func lectura(correctas: Int, total: Int, elegir: ([String]) -> String = { $0.randomElement()! }) -> String {
        guard total > 0 else { return "" }
        if correctas == total {
            return elegir(["Lectura perfecta. かんぺき。", "Todo bien leído. Prueba un texto más largo.", "Sin errores. すごい！"])
        }
        let porcentaje = correctas * 100 / total
        if porcentaje >= 80 { return elegir(["Muy bien: \(porcentaje) % correcto.", "Casi perfecto. Mira en rojo lo que se escapó."]) }
        if porcentaje >= 50 { return elegir(["Vas bien: \(porcentaje) %. Repite con las mismas filas.", "Más de la mitad. Cada lectura suma."]) }
        return elegir(["Esta costó. Filtra menos filas y vuelve a intentarlo.", "Paso a paso: elige solo las filas que ya conoces."])
    }

    static func meta(_ racha: Int) -> String {
        racha > 1 ? "Meta del día cumplida. Racha de \(racha) días." : "Meta del día cumplida. Mañana empieza la racha."
    }

    static func hito(_ h: Hitos.Hito) -> String {
        "Dominaste la fila \(h.ejemplo) de \(h.silabario.nombre.lowercased())."
    }

    private static func segundos(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }
}

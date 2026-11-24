import Foundation

// Comprobaciones del revisor de «Escribir» (modos de fallo 113–118 y 123). Se ejecutan desde main.swift.
private typealias P = Trazos.Punto

/// Generador fijo (SplitMix64): las deformaciones son las mismas en cada corrida.
private struct Azar {
    var s: UInt64
    mutating func r(_ a: Double) -> Double {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return (Double(z >> 11) / Double(1 << 53) * 2 - 1) * a
    }
}

/// Plantilla deformada como la mano: más ancha o alta, inclinada, girada, trazos corridos, de otro tamaño y
/// temblorosos, y todo el kana en otra escala y posición (como en la cuadrícula del iPad).
private func deformar(_ t: [Trazos.Trazo], _ g: inout Azar, fuerza f: Double) -> [Trazos.Trazo] {
    let sx = 1 + g.r(0.2 * f), sy = 1 + g.r(0.2 * f), sesgo = g.r(0.15 * f), giro = g.r(0.1 * f)
    return t.map { trazo in
        let corrido = P(g.r(5 * f), g.r(5 * f)), escala = 1 + g.r(0.12 * f), fase = (g.r(1.5), g.r(1.5))
        let c = trazo.reduce(.zero, +) / Double(trazo.count)
        return trazo.enumerated().map { k, p0 in
            var p = c + (p0 - c) * escala + corrido
            p += P(sin(Double(k) * 0.5 + fase.0), cos(Double(k) * 0.4 + fase.1)) * 1.2 * f
            let x = p.x * sx + p.y * sesgo, y = p.y * sy
            return P(x * cos(giro) - y * sin(giro), x * sin(giro) + y * cos(giro)) * 3 + P(200, 50)
        }
    }
}

func comprobarTrazos() {
    guard let datos = FileManager.default.contents(atPath: "../datos/trazos-kana.json"),
          let plantillas = try? Trazos.cargar(datos) else {
        comprobar(false, "no se pudo leer datos/trazos-kana.json (node scripts/trazos/construir.mjs)")
        return
    }
    // 118: todos los kana sueltos que se preguntan tienen plantilla.
    let preguntados = Silabario.allCases.flatMap { Kana.mazo($0, .todos) }.map(\.kana).filter { $0.count == 1 }
    let faltan = preguntados.filter { plantillas[$0] == nil }
    comprobar(faltan.isEmpty && preguntados.count == 138, "118: faltan plantillas: \(faltan) (\(preguntados.count) kana; 69 por silabario, sin ぢ ni づ)")

    var g = Azar(s: 42)
    var rechazados: [String] = []
    for k in preguntados {
        guard let t = plantillas[k] else { continue }
        comprobar(Trazos.revisar(t, contra: t) == .bien, "113: la plantilla de \(k) no pasa contra sí misma")
        // 123: pequeño en una esquina.
        let pequeno = t.map { $0.map { $0 * 0.3 + P(5, 70) } }
        comprobar(Trazos.revisar(pequeno, contra: t) == .bien, "123: \(k) pequeño y en una esquina sale mal")
        // 113: deformaciones moderadas, 10 por kana.
        for _ in 0 ..< 10 where Trazos.revisar(deformar(t, &g, fuerza: 0.5), contra: t) != .bien { rechazados.append(k) }
    }
    comprobar(rechazados.isEmpty, "113: letra deformada rechazada: \(rechazados)")

    // 114: ningún kana distinto con los mismos trazos pasa, salvo los que son el mismo dibujo, y う/ラ, que queda justo
    // en el umbral (0,118): no se confunden por el romaji que se pide.
    let mismoDibujo: Set = ["へ/ヘ", "べ/ベ", "ぺ/ペ", "う/ラ"]
    var confundidos: [String] = []
    for a in preguntados {
        for b in preguntados where a != b && !mismoDibujo.contains("\(a)/\(b)") && !mismoDibujo.contains("\(b)/\(a)") {
            guard let ta = plantillas[a], let tb = plantillas[b], ta.count == tb.count else { continue }
            if Trazos.revisar(ta, contra: tb) == .bien { confundidos.append("\(a)→\(b)") }
        }
    }
    comprobar(confundidos.isEmpty, "114: kana distintos aceptados: \(confundidos)")
    for (a, b) in [("シ", "ツ"), ("ソ", "ン"), ("ぬ", "め"), ("れ", "わ"), ("ね", "れ"), ("る", "ろ"), ("は", "ほ")] {
        comprobar(Trazos.revisar(plantillas[a]!, contra: plantillas[b]!) != .bien, "114: \(a) pasa por \(b)")
    }

    // 115: orden cambiado y trazo al revés, con el número de trazo.
    let e = plantillas["エ"]!
    comprobar(Trazos.revisar([e[1], e[0], e[2]], contra: e) == .orden(trazo: 1), "115: エ con el palo primero")
    comprobar(Trazos.revisar([e[0], Array(e[1].reversed()), e[2]], contra: e) == .alReves(trazo: 2), "115: エ con el palo hacia arriba")
    // 116: が sin dakuten; 117: nada dibujado y un toque suelto.
    comprobar(Trazos.revisar(plantillas["か"]!, contra: plantillas["が"]!) == .cantidad(esperados: 5, dibujados: 3), "116: が sin dakuten")
    comprobar(Trazos.revisar([], contra: e) == .cantidad(esperados: 3, dibujados: 0), "117: sin dibujo")
    comprobar(Trazos.revisar([[P(10, 10)], e[1], e[2]], contra: e) == .forma(trazo: 1), "117: un toque en lugar del primer trazo")
}

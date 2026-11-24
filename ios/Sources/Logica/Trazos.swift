import Foundation

/// Revisa un kana escrito a mano contra su plantilla de KanjiVG, trazo a trazo y en orden (modos de fallo 113–117, 123).
/// Vision no sirve para esto: con letra de imprenta reconoció entre 15 y 60 de 96 kana sueltos.
enum Trazos {
    typealias Punto = SIMD2<Double>
    typealias Trazo = [Punto]

    enum Veredicto: Equatable {
        case bien
        case cantidad(esperados: Int, dibujados: Int)
        /// El trazo n (desde 1) se parece a otro de la plantilla: va en otro orden.
        case orden(trazo: Int)
        case alReves(trazo: Int)
        case forma(trazo: Int)
    }

    /// Distancia máxima entre un trazo y el de la plantilla (ver `distancia`), en fracciones del lado del kana.
    /// Calibrada el 2026-11-24 contra plantillas deformadas como letra a mano (escala, inclinación, giro, trazos
    /// corridos y temblorosos): el 95 % queda por debajo de 0,117, y los pares distintos más cercanos, por encima
    /// (う/ラ 0,118, れ/わ 0,130, ス/ヌ 0,135). Más alto acepta kana parecidos; más bajo rechaza letra real.
    /// Lo vigila ios/scripts/comprobar_enganche.sh.
    static let umbral = 0.12
    static let muestras = 24

    /// `datos`: datos/trazos-kana.json (kana → trazos → puntos [x, y]).
    static func cargar(_ datos: Data) throws -> [String: [Trazo]] {
        try JSONDecoder().decode([String: [[[Double]]]].self, from: datos)
            .mapValues { $0.map { $0.map { Punto($0[0], $0[1]) } } }
    }

    static func revisar(_ dibujo: [Trazo], contra plantilla: [Trazo]) -> Veredicto {
        let dibujo = dibujo.filter { !$0.isEmpty }
        guard dibujo.count == plantilla.count, !dibujo.isEmpty else {
            return .cantidad(esperados: plantilla.count, dibujados: dibujo.count)
        }
        let u = normalizar(dibujo), t = normalizar(plantilla)
        for i in u.indices where distancia(u[i], t[i]) > umbral {
            if distancia(u[i], Array(t[i].reversed())) <= umbral { return .alReves(trazo: i + 1) }
            if t.indices.contains(where: { $0 != i && distancia(u[i], t[$0]) <= umbral }) { return .orden(trazo: i + 1) }
            return .forma(trazo: i + 1)
        }
        return .bien
    }

    /// Mayor distancia entre trazos alineados (para calibrar el umbral).
    static func peorDistancia(_ dibujo: [Trazo], _ plantilla: [Trazo]) -> Double {
        guard dibujo.count == plantilla.count else { return .infinity }
        let u = normalizar(dibujo), t = normalizar(plantilla)
        return zip(u, t).map { distancia($0, $1) }.max() ?? .infinity
    }

    /// Centra el dibujo y lo lleva a lado 1 sin deformarlo (escala uniforme): el tamaño y la posición no cuentan (123).
    /// Cada trazo queda remuestreado a `muestras` puntos a la misma distancia entre sí.
    static func normalizar(_ trazos: [Trazo]) -> [Trazo] {
        let todos = trazos.flatMap { $0 }
        let minimo = todos.reduce(todos[0]) { pointwiseMin($0, $1) }
        let maximo = todos.reduce(todos[0]) { pointwiseMax($0, $1) }
        let lado = max(maximo.x - minimo.x, maximo.y - minimo.y, 1e-9)
        let centro = (minimo + maximo) / 2
        return trazos.map { remuestrear($0.map { ($0 - centro) / lado }) }
    }

    /// Forma (los dos trazos centrados, punto a punto y en el sentido del trazo) más media distancia entre centros:
    /// así un trazo bien hecho pero algo corrido pesa menos que uno con otra forma.
    private static func distancia(_ a: Trazo, _ b: Trazo) -> Double {
        let ca = centro(a), cb = centro(b)
        let forma = zip(a, b).map { simd_length(($0 - ca) - ($1 - cb)) }.reduce(0, +) / Double(a.count)
        return forma + 0.5 * simd_length(ca - cb)
    }

    private static func centro(_ t: Trazo) -> Punto { t.reduce(.zero, +) / Double(t.count) }

    /// `muestras` puntos repartidos por longitud de arco. Un toque (longitud 0) queda como un punto repetido (117).
    static func remuestrear(_ trazo: Trazo) -> Trazo {
        let tramos = zip(trazo, trazo.dropFirst()).map { simd_length($1 - $0) }
        let total = tramos.reduce(0, +)
        guard total > 0 else { return Array(repeating: trazo[0], count: muestras) }
        var salida: Trazo = [trazo[0]]
        var j = 0, recorrido = 0.0
        for k in 1 ..< muestras {
            let objetivo = total * Double(k) / Double(muestras - 1)
            while j < tramos.count - 1, recorrido + tramos[j] < objetivo { recorrido += tramos[j]; j += 1 }
            let f = tramos[j] > 0 ? min((objetivo - recorrido) / tramos[j], 1) : 0
            salida.append(trazo[j] + (trazo[j + 1] - trazo[j]) * f)
        }
        return salida
    }
}

private func simd_length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

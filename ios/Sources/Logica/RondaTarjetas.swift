import Foundation

/// Port de la lógica de `src/cards.js`: una ronda de tarjetas con 3 vidas. Sin UI ni reloj.
struct RondaTarjetas {
    enum OpcionSilabario: String, CaseIterable, Identifiable {
        case hiragana, katakana, ambos
        var id: String { rawValue }
        var nombre: String { rawValue == "ambos" ? "Ambos" : Silabario(rawValue: rawValue)!.nombre }
    }

    enum Tamano: String, CaseIterable, Identifiable {
        case cinco = "5", diez = "10", veinte = "20", completo = "full"
        var id: String { rawValue }
    }

    struct Config: Hashable {
        var silabario: OpcionSilabario = .hiragana
        var mazo: Kana.Mazo = .basicos
        var tamano: Tamano = .diez
        /// Clave del récord: cada combinación lleva el suyo (modo de fallo 38).
        /// «-op»: los récords de opción múltiple no se comparan con los de cuando se escribía la lectura.
        var claveRecord: String { "\(silabario.rawValue)-\(mazo.rawValue)-\(tamano.rawValue)-op" }
    }

    struct Contestada { let tarjeta: Tarjeta; let ok: Bool; let ms: Int }
    enum Resultado { case completa, sinVidas }

    static let vidasIniciales = 3

    let config: Config
    let tarjetas: [Tarjeta]
    /// Sesión de «Hoy»: sin vidas ni récord (modo de fallo 82).
    let repaso: Bool
    private(set) var indice = 0
    private(set) var vidas = vidasIniciales
    private(set) var respuestas: [Contestada] = []
    /// Aciertos seguidos; se reinicia con cada error y con cada ronda nueva (modo de fallo 66).
    private(set) var combo = 0
    private(set) var mejorCombo = 0
    /// Las 4 lecturas que se muestran para la tarjeta actual (opción múltiple).
    private(set) var opciones: [String] = []

    static func mazo(_ s: OpcionSilabario, _ m: Kana.Mazo) -> [Tarjeta] {
        switch s {
        case .ambos: Kana.mazo(.hiragana, m) + Kana.mazo(.katakana, m)
        case .hiragana: Kana.mazo(.hiragana, m)
        case .katakana: Kana.mazo(.katakana, m)
        }
    }

    init(config: Config) {
        let pool = Self.mazo(config.silabario, config.mazo).shuffled()
        let cantidad = config.tamano == .completo ? pool.count : Int(config.tamano.rawValue)!
        self.config = config
        tarjetas = Array(pool.prefix(cantidad))
        repaso = false
        prepararOpciones()
    }

    init(repaso tarjetas: [Tarjeta]) {
        config = Config()
        self.tarjetas = tarjetas
        repaso = true
        prepararOpciones()
    }

    private mutating func prepararOpciones() {
        guard indice < tarjetas.count else { return opciones = [] }
        var azar = SystemRandomNumberGenerator()
        // En el repaso, un kana básico toma las falsas de los básicos (sin «pa» ni «kya» para quien empieza).
        let basicos = Kana.mazo(actual.silabario, .basicos)
        let mazo = repaso ? (basicos.contains(actual) ? basicos : Kana.mazo(actual.silabario, .todos))
                          : Self.mazo(config.silabario, config.mazo)
        opciones = Opciones.para(actual, mazo: mazo, azar: &azar)
    }

    var actual: Tarjeta { tarjetas[indice] }
    var aciertos: Int { respuestas.filter(\.ok).count }
    var resultado: Resultado? {
        if vidas == 0 { return .sinVidas }
        return indice >= tarjetas.count ? .completa : nil
    }

    mutating func acertar(ms: Int) {
        combo += 1
        mejorCombo = max(mejorCombo, combo)
        respuestas.append(Contestada(tarjeta: actual, ok: true, ms: ms))
        indice += 1
        prepararOpciones()
    }

    /// Error o «No la sé»: resta una vida. La vista avanza con `siguiente()` tras mostrar la lectura.
    mutating func fallar(ms: Int) {
        combo = 0
        respuestas.append(Contestada(tarjeta: actual, ok: false, ms: ms))
        if !repaso { vidas -= 1 }
    }

    mutating func siguiente() {
        if vidas > 0 { indice += 1 }
        prepararOpciones()
    }

    var tiempoTotalMs: Int { respuestas.reduce(0) { $0 + $1.ms } }
    /// Solo cuenta aciertos: un «No la sé» rápido no mejora la media.
    var mediaAciertosMs: Int {
        let ok = respuestas.filter(\.ok)
        return ok.isEmpty ? 0 : ok.reduce(0) { $0 + $1.ms } / ok.count
    }
    var masLentas: [Contestada] { Array(respuestas.filter(\.ok).sorted { $0.ms > $1.ms }.prefix(3)) }
    var errores: [Tarjeta] { respuestas.filter { !$0.ok }.map(\.tarjeta) }
}

/// Tiempo activo de una tarjeta: se pausa con la app en segundo plano (modo de fallo 56).
struct Cronometro {
    private var inicio: Date?
    private var acumulado: TimeInterval = 0

    mutating func iniciar(_ ahora: Date = .now) { inicio = ahora; acumulado = 0 }
    mutating func pausar(_ ahora: Date = .now) {
        if let inicio { acumulado += ahora.timeIntervalSince(inicio) }
        inicio = nil
    }
    mutating func reanudar(_ ahora: Date = .now) { if inicio == nil { inicio = ahora } }
    func ms(_ ahora: Date = .now) -> Int {
        Int(((inicio.map { ahora.timeIntervalSince($0) } ?? 0) + acumulado) * 1000)
    }
}

import Foundation

/// Una pregunta de vocabulario o kanji: se ve la palabra (con su lectura) o el kanji y se elige el significado.
struct Pregunta: Hashable {
    enum Tipo: String, CaseIterable { case vocabulario, kanji }

    let tipo: Tipo
    /// Lo que se guarda como `item`: «会う|あう» o «会».
    let clave: String
    /// Lo que se muestra grande: 会う, キロ・キログラム, 会.
    let texto: String
    /// Lectura en kana, si no es la misma que el texto (modo de fallo 102).
    let lectura: String?
    /// La opción correcta: hasta dos significados.
    let significado: String
    let glosas: [String]
    /// Tras responder mal: lecturas del kanji (音・訓).
    let detalle: String?
}

/// Vocabulario y kanji N5 (`datos/*.json`, en el bundle; ver datos/LICENCIAS.md).
enum Vocabulario {
    static let nuevasPorDia: [Pregunta.Tipo: Int] = [.vocabulario: 10, .kanji: 5]  // modo de fallo 99
    /// Leer la palabra y 4 significados lleva más que reconocer un kana: hasta 4 s un acierto es «bien».
    static let bienMs = 4000

    private struct Palabra: Decodable { let id: String; let palabra: String; let lectura: String; let es: [String] }
    private struct KanjiN5: Decodable { let kanji: String; let on: [String]; let kun: [String]; let es: [String]; let trazos: Int }

    private static func variantes(_ s: String) -> String {
        s.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "・")
    }
    private static func significado(_ es: [String]) -> String { es.prefix(2).joined(separator: ", ") }

    /// FNV-1a de 64 bits: el mismo número en cualquier equipo y ejecución (el `Hasher` de Swift cambia en cada una).
    static func huella(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }

    /// En el orden en que se introducen: mezclado pero fijo, para no pasar días con palabras de あ (modos 97 y 98).
    static func palabras(_ datos: Data) throws -> [Pregunta] {
        try JSONDecoder().decode([Palabra].self, from: datos).map { p in
            let texto = variantes(p.palabra), lectura = variantes(p.lectura)
            return Pregunta(tipo: .vocabulario, clave: p.id, texto: texto, lectura: lectura == texto ? nil : lectura,
                            significado: significado(p.es), glosas: p.es, detalle: nil)
        }
        .sorted { (huella($0.clave), $0.clave) < (huella($1.clave), $1.clave) }
    }

    /// Kanji de menos a más trazos (一 antes que 曜).
    static func kanji(_ datos: Data) throws -> [Pregunta] {
        try JSONDecoder().decode([KanjiN5].self, from: datos)
            .sorted { ($0.trazos, $0.kanji) < ($1.trazos, $1.kanji) }
            .map { k in
                let on = k.on.isEmpty ? "" : "音 " + k.on.joined(separator: "、")
                let kun = k.kun.isEmpty ? "" : "訓 " + k.kun.joined(separator: "、")
                return Pregunta(tipo: .kanji, clave: k.kanji, texto: k.kanji, lectura: nil, significado: significado(k.es),
                                glosas: k.es, detalle: [on, kun].filter { !$0.isEmpty }.joined(separator: "  ·  "))
            }
    }

    /// Palabras de un significado, para compararlo con otro: sin tildes, mayúsculas, signos, paréntesis ni artículo
    /// inicial («La mañana» y «mañana», «(sala de) cine» y «cine» quedan iguales).
    static func nucleo(_ glosa: String) -> [String] {
        let sinParentesis = glosa.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        let palabras = sinParentesis.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        return Array(palabras.drop { ["el", "la", "los", "las", "un", "una"].contains($0) })
    }

    /// Dos significados chocan si, sin lo accesorio, uno contiene todas las palabras del otro («bien» y «estar bien»).
    static func chocan(_ a: [String], _ b: [String]) -> Bool {
        let na = a.map { Set(nucleo($0)) }.filter { !$0.isEmpty }, nb = b.map { Set(nucleo($0)) }.filter { !$0.isEmpty }
        return na.contains { x in nb.contains { y in x.isSubset(of: y) || y.isSubset(of: x) } }
    }

    /// La correcta y 3 falsas que no chocan con ella en ningún significado (青 y 青い son «azul»; «mañana» y «la
    /// mañana») (modo de fallo 96).
    static func opciones(para p: Pregunta, entre todas: [Pregunta], azar: inout some RandomNumberGenerator) -> [String] {
        var vistas: Set<String> = [p.significado]
        var elegidas: [Pregunta] = []
        for q in todas.shuffled(using: &azar) where elegidas.count < 3 {
            guard q.clave != p.clave, !chocan(p.glosas, q.glosas), !elegidas.contains(where: { chocan($0.glosas, q.glosas) }),
                  vistas.insert(q.significado).inserted else { continue }
            elegidas.append(q)
        }
        let falsas = elegidas.map(\.significado)
        return (falsas + [p.significado]).shuffled(using: &azar)
    }
}

/// Una sesión de preguntas sin vidas (como el repaso de kana): se responden todas.
struct RondaPreguntas {
    struct Contestada { let pregunta: Pregunta; let ok: Bool; let ms: Int }

    let preguntas: [Pregunta]
    private let todas: [Pregunta]
    private(set) var indice = 0
    private(set) var respuestas: [Contestada] = []
    private(set) var combo = 0
    private(set) var mejorCombo = 0
    private(set) var opciones: [String] = []

    init(_ preguntas: [Pregunta], todas: [Pregunta]) {
        self.preguntas = preguntas
        self.todas = todas
        prepararOpciones()
    }

    var actual: Pregunta { preguntas[indice] }
    var terminada: Bool { indice >= preguntas.count }
    var aciertos: Int { respuestas.filter(\.ok).count }
    var errores: [Pregunta] { respuestas.filter { !$0.ok }.map(\.pregunta) }
    var mediaAciertosMs: Int {
        let ok = respuestas.filter(\.ok)
        return ok.isEmpty ? 0 : ok.reduce(0) { $0 + $1.ms } / ok.count
    }

    private mutating func prepararOpciones() {
        guard !terminada else { return opciones = [] }
        var azar = SystemRandomNumberGenerator()
        opciones = Vocabulario.opciones(para: actual, entre: todas, azar: &azar)
    }

    mutating func acertar(ms: Int) {
        combo += 1
        mejorCombo = max(mejorCombo, combo)
        respuestas.append(Contestada(pregunta: actual, ok: true, ms: ms))
        indice += 1
        prepararOpciones()
    }

    /// Error o «No la sé». La vista avanza con `siguiente()` tras mostrar la correcta.
    mutating func fallar(ms: Int) {
        combo = 0
        respuestas.append(Contestada(pregunta: actual, ok: false, ms: ms))
    }

    mutating func siguiente() {
        indice += 1
        prepararOpciones()
    }
}

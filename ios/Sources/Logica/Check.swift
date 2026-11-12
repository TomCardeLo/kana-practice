import Foundation

/// Port de `src/check.js`: corrección kana por kana con alineación por distancia de edición.
struct UnidadCorregida: Hashable, Codable {
    let romaji: String
    let kana: String
    let row: String
    let ok: Bool
    let typed: String?
}

struct Correccion: Hashable, Codable {
    let words: [[UnidadCorregida]]
    let correct: Int
    let total: Int
    let extra: Int
}

enum Check {
    private static let yoonPequenos: Set<Character> = ["ゃ", "ゅ", "ょ"]
    private static let nnSinSilaba = try! NSRegularExpression(pattern: "nn(?=[^aeiouy]|$)")

    /// ぢ/づ cuentan como じ/ず.
    private static func canonizar(_ hiragana: String) -> String {
        hiragana.replacingOccurrences(of: "ぢ", with: "じ").replacingOccurrences(of: "づ", with: "ず")
    }

    /// Un kana grande + su ゃゅょ es una unidad; cada letra latina sin convertir es otra (inválida).
    private static func tokenizar(_ hiragana: String) -> [String] {
        var unidades: [String] = []
        for c in canonizar(hiragana) {
            if yoonPequenos.contains(c), !unidades.isEmpty {
                unidades[unidades.count - 1].append(c)
            } else {
                unidades.append(String(c))
            }
        }
        return unidades
    }

    /// "nn" sin sílaba que la reclame es ん ("kannto" → かんと, pero "kanna" → かんな).
    private static func normalizarNN(_ palabra: String) -> String {
        nnSinSilaba.stringByReplacingMatches(
            in: palabra, range: NSRange(palabra.startIndex..., in: palabra), withTemplate: "n'")
    }

    private static func normalizar(_ respuesta: String) -> [String] {
        respuesta.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Cada palabra se convierte por separado: "pan agua" es ぱん + あぐあ, no ぱなぐあ.
    private static func hiraganaEscrito(_ palabras: [String]) -> String {
        palabras.map { Romaji.aHiragana(normalizarNN($0)) }.joined()
    }

    private struct Par { let esperado: String?; let escrito: String? }

    /// Ante empate se prefiere emparejar (sustitución) antes que marcar falta o sobra.
    private static func alinear(_ esperado: [String], _ escrito: [String]) -> [Par] {
        let n = esperado.count, m = escrito.count
        var dist = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0 ... n { dist[i][0] = i }
        for j in 0 ... m { dist[0][j] = j }
        if n > 0, m > 0 {
            for i in 1 ... n {
                for j in 1 ... m {
                    let costo = esperado[i - 1] == escrito[j - 1] ? 0 : 1
                    dist[i][j] = min(dist[i - 1][j - 1] + costo, dist[i - 1][j] + 1, dist[i][j - 1] + 1)
                }
            }
        }
        var pares: [Par] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, dist[i][j] == dist[i - 1][j - 1] + (esperado[i - 1] == escrito[j - 1] ? 0 : 1) {
                pares.append(Par(esperado: esperado[i - 1], escrito: escrito[j - 1])); i -= 1; j -= 1
            } else if i > 0, dist[i][j] == dist[i - 1][j] + 1 {
                pares.append(Par(esperado: esperado[i - 1], escrito: nil)); i -= 1
            } else {
                pares.append(Par(esperado: nil, escrito: escrito[j - 1])); j -= 1
            }
        }
        return pares.reversed()
    }

    /// Unidades completas escritas hasta ahora (la sílaba latina a medio escribir no cuenta).
    static func unidadesEscritas(_ respuesta: String) -> Int {
        let palabras = normalizar(respuesta)
        guard !palabras.isEmpty else { return 0 }
        var completo = hiraganaEscrito(palabras)
        while let ultimo = completo.unicodeScalars.last, !(0x3040 ... 0x30FF).contains(ultimo.value) {
            completo.unicodeScalars.removeLast()
        }
        return completo.isEmpty ? 0 : tokenizar(completo).count
    }

    /// Lectura de una tarjeta. Espacios internos siempre son error: una tarjeta es una sola sílaba.
    static func esLecturaCorrecta(_ romaji: String, _ escrito: String) -> Bool {
        let limpio = escrito.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, !limpio.contains(where: \.isWhitespace) else { return false }
        return canonizar(Romaji.aHiragana(normalizarNN(limpio))) == canonizar(Romaji.aHiragana(romaji))
    }

    /// Corrige la respuesta contra las palabras esperadas (ya filtradas por fila). nil si está vacía.
    static func corregir(_ esperadas: [[Unidad]], _ respuesta: String) -> Correccion? {
        let palabras = normalizar(respuesta)
        guard !palabras.isEmpty else { return nil }
        let plano = esperadas.flatMap { $0 }
        let kanaEsperado = plano.map { canonizar(Romaji.aHiragana($0.romaji)) }
        let completos = alinear(kanaEsperado, tokenizar(hiraganaEscrito(palabras)))
        let extra = completos.filter { $0.esperado == nil }.count
        var pares = completos.filter { $0.esperado != nil }.makeIterator()

        var correctas = 0
        let words = esperadas.map { palabra in
            palabra.map { unidad -> UnidadCorregida in
                let par = pares.next()!
                let ok = par.escrito != nil && par.escrito == par.esperado
                if ok { correctas += 1 }
                return UnidadCorregida(romaji: unidad.romaji, kana: unidad.kana, row: unidad.row, ok: ok,
                                       typed: par.escrito.map(Romaji.aRomaji))
            }
        }
        return Correccion(words: words, correct: correctas, total: plano.count, extra: extra)
    }
}

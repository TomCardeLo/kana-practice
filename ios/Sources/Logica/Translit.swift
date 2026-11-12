import Foundation

/// Port de `src/translit.js`: texto en español → sílabas romaji canónicas. No traduce: adapta el sonido.
enum Translit {
    private static let vocales: Set<Character> = ["a", "e", "i", "o", "u"]

    // Reescritura ortográfica en orden de prioridad (dígrafos antes que letras sueltas). "G" marca la g
    // dura de gue/gui; "C" marca "ch".
    private static let reescrituras: [(NSRegularExpression, String)] = [
        ("qu", "k"), ("q", "k"), ("gu([ei])", "G$1"), ("ch", "C"), ("ll", "y"), ("rr", "r"), ("l", "r"),
        ("g([ei])", "j$1"), ("c([ei])", "s$1"), ("c", "k"), ("z", "s"), ("v", "b"), ("h", ""), ("G", "g"),
        ("ü", "u"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static let combinaciones: [Character: [Character: [String]]] = [
        "s": ["i": ["shi"]],
        "t": ["i": ["chi"], "u": ["tsu"]],
        "d": ["i": ["ji"], "u": ["zu"]],
        "j": ["a": ["ha"], "i": ["hi"], "u": ["fu"], "e": ["he"], "o": ["ho"]],
        "f": ["a": ["fu", "a"], "e": ["fu", "e"], "i": ["fu", "i"], "o": ["fu", "o"], "u": ["fu"]],
        "y": ["e": ["i", "e"], "i": ["i"]],
        "ñ": ["a": ["nya"], "e": ["ni", "e"], "i": ["ni"], "o": ["nyo"], "u": ["nyu"]],
        "C": ["e": ["chi", "e"], "i": ["chi"]],
        "w": ["a": ["wa"], "e": ["u", "e"], "i": ["u", "i"], "o": ["u", "o"], "u": ["u"]],
        "x": ["a": ["ku", "sa"], "e": ["ku", "se"], "i": ["ku", "shi"], "o": ["ku", "so"], "u": ["ku", "su"]],
    ]

    private static func etiqueta(_ c: Character) -> String { c == "C" ? "ch" : String(c) }

    private static func combinar(_ consonante: Character, _ vocal: Character) -> [String] {
        combinaciones[consonante]?[vocal] ?? [etiqueta(consonante) + String(vocal)]
    }

    /// Consonante sin vocal detrás: + "u", salvo t/d (+ "o") y casos irregulares.
    private static func consonanteSuelta(_ c: Character) -> [String] {
        switch c {
        case "y": ["i"]
        case "j": ["fu"]
        case "ñ": ["ni"]
        case "x": ["ku", "su"]
        case "t": ["to"]
        case "d": ["do"]
        default: [etiqueta(c) + "u"]
        }
    }

    /// Minúsculas y sin tildes, conservando ñ y ü (güe/güi no son gue/gui).
    private static func normalizar(_ texto: String) -> String {
        let protegido = texto.lowercased().precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "ñ", with: "\u{1}")
            .replacingOccurrences(of: "ü", with: "\u{2}")
            .decomposedStringWithCanonicalMapping
        let sinMarcas = String(String.UnicodeScalarView(protegido.unicodeScalars.filter {
            !(0x0300 ... 0x036F).contains($0.value)
        }))
        return sinMarcas.replacingOccurrences(of: "\u{1}", with: "ñ").replacingOccurrences(of: "\u{2}", with: "ü")
    }

    private static func reescribir(_ palabra: String) -> String {
        reescrituras.reduce(palabra) { texto, regla in
            regla.0.stringByReplacingMatches(
                in: texto, range: NSRange(texto.startIndex..., in: texto), withTemplate: regla.1)
        }
    }

    private static func parsear(_ fonemico: String) -> [String] {
        let letras = Array(fonemico)
        var silabas: [String] = []
        var i = 0
        while i < letras.count {
            let actual = letras[i]
            if vocales.contains(actual) {
                silabas.append(String(actual)); i += 1; continue
            }
            let siguiente: Character? = i + 1 < letras.count ? letras[i + 1] : nil
            let vocalDetras = siguiente.map { vocales.contains($0) } ?? false
            if actual == "n" {
                silabas.append(vocalDetras ? "n" + String(siguiente!) : "n")
                i += vocalDetras ? 2 : 1
                continue
            }
            if vocalDetras {
                silabas += combinar(actual, siguiente!); i += 2; continue
            }
            silabas += consonanteSuelta(actual); i += 1
        }
        return silabas
    }

    private static func esLetra(_ c: Character) -> Bool {
        ("a" ... "z").contains(c) || c == "ñ" || c == "ü"
    }

    /// Texto → palabras, cada una como sílabas romaji. Números, puntuación y emojis separan palabras.
    static func silabas(_ texto: String) -> [[String]] {
        normalizar(texto)
            .split(whereSeparator: { !esLetra($0) })
            .map { parsear(reescribir(String($0))) }
    }
}

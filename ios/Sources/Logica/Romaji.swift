import Foundation

/// Romaji ⇄ kana, compatible con wanakana 5.3.1 (la que usa la web) en todo lo que escribe un usuario.
/// No se usa la transliteración de iOS (ICU): no acepta si/tu/hu/zi/sya y convierte consonantes
/// sueltas (`k` → く), lo que rompería las tarjetas (modos de fallo 42–46). Verificado contra wanakana
/// con `ios/scripts/paridad.sh`.
enum Romaji {
    private static let vocales = Array("aiueo")
    private static let largoMaximo = 4
    private static let tabla: [String: String] = construirTabla()

    private static func construirTabla() -> [String: String] {
        var t: [String: String] = [:]
        func fila(_ consonante: String, _ kana: String) {
            for (vocal, k) in zip(vocales, kana) { t[consonante + String(vocal)] = String(k) }
        }
        fila("", "あいうえお")
        fila("k", "かきくけこ"); fila("c", "かきくけこ"); fila("s", "さしすせそ"); fila("t", "たちつてと")
        fila("n", "なにぬねの"); fila("h", "はひふへほ"); fila("m", "まみむめも"); fila("r", "らりるれろ")
        fila("g", "がぎぐげご"); fila("z", "ざじずぜぞ"); fila("d", "だぢづでど"); fila("b", "ばびぶべぼ")
        fila("p", "ぱぴぷぺぽ")

        func cinco(_ prefijo: String, _ kana: [String]) {
            for (vocal, k) in zip(vocales, kana) { t[prefijo + String(vocal)] = k }
        }
        cinco("y", ["や", "い", "ゆ", "いぇ", "よ"])
        cinco("w", ["わ", "うぃ", "う", "うぇ", "を"])
        cinco("f", ["ふぁ", "ふぃ", "ふ", "ふぇ", "ふぉ"])
        cinco("v", ["ゔぁ", "ゔぃ", "ゔ", "ゔぇ", "ゔぉ"])
        cinco("q", ["くぁ", "くぃ", "くぅ", "くぇ", "くぉ"])
        cinco("sh", ["しゃ", "し", "しゅ", "しぇ", "しょ"])
        cinco("ch", ["ちゃ", "ち", "ちゅ", "ちぇ", "ちょ"])
        cinco("j", ["じゃ", "じ", "じゅ", "じぇ", "じょ"])
        cinco("ts", ["つぁ", "つぃ", "つ", "つぇ", "つぉ"])

        // Combinados: consonante + y + vocal (きゃ, じぃ, ふゅ...).
        let pequenasY = ["ゃ", "ぃ", "ゅ", "ぇ", "ょ"]
        let baseY: [String: String] = [
            "k": "き", "s": "し", "t": "ち", "c": "ち", "n": "に", "h": "ひ", "m": "み", "r": "り", "g": "ぎ",
            "z": "じ", "j": "じ", "d": "ぢ", "b": "び", "p": "ぴ", "v": "ゔ", "f": "ふ", "q": "く",
        ]
        for (consonante, base) in baseY { cinco(consonante + "y", pequenasY.map { base + $0 }) }

        // Pequeñas con x/l (xa → ぁ, lyo → ょ, xtsu → っ).
        for prefijo in ["x", "l"] {
            cinco(prefijo, ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"])
            cinco(prefijo + "y", pequenasY)
            t[prefijo + "tu"] = "っ"; t[prefijo + "tsu"] = "っ"
            t[prefijo + "ka"] = "ヵ"; t[prefijo + "ke"] = "ヶ"; t[prefijo + "wa"] = "ゎ"
        }
        t["xn"] = "ん"; t["n'"] = "ん"
        t["thi"] = "てぃ"; t["dhi"] = "でぃ"; t["whi"] = "うぃ"; t["kwa"] = "くぁ"; t["gwa"] = "ぐぁ"
        let simbolos: [String: String] = [
            ".": "。", ",": "、", "?": "？", "!": "！", "~": "〜", "/": "・", ":": "：", "-": "ー",
        ]
        t.merge(simbolos) { actual, _ in actual }
        return t
    }

    /// Busca la entrada más larga de la tabla que empieza en `i`.
    private static func coincidencia(_ letras: [Character], desde i: Int) -> (kana: String, largo: Int)? {
        for largo in stride(from: min(largoMaximo, letras.count - i), through: 1, by: -1) {
            if let kana = tabla[String(letras[i ..< i + largo])] { return (kana, largo) }
        }
        return nil
    }

    /// Romaji en minúsculas → hiragana. Lo que no forma sílaba se deja en latín (`kak` → かk).
    static func aHiragana(_ texto: String) -> String {
        let letras = Array(texto)
        var salida = ""
        var i = 0
        while i < letras.count {
            let actual = letras[i]
            let siguiente: Character? = i + 1 < letras.count ? letras[i + 1] : nil
            // Consonante doble → っ, solo si lo que sigue forma sílaba (`tts` queda en latín).
            if let siguiente, siguiente == actual, actual.isLetter, !vocales.contains(actual),
               !"nxl".contains(actual), let m = coincidencia(letras, desde: i + 1) {
                salida += "っ" + m.kana
                i += 1 + m.largo
                continue
            }
            if let m = coincidencia(letras, desde: i) {
                salida += m.kana
                i += m.largo
                continue
            }
            // `n` sin vocal detrás es ん, salvo `ny` a medio escribir.
            if actual == "n", siguiente != "y" {
                salida += "ん"
            } else {
                salida.append(actual)
            }
            i += 1
        }
        return salida
    }

    static func aKatakana(_ texto: String) -> String {
        deHiraganaAKatakana(aHiragana(texto))
    }

    /// Desplazamiento Unicode ぁ–ゖ → ァ–ヶ; el resto queda igual.
    static func deHiraganaAKatakana(_ texto: String) -> String {
        String(String.UnicodeScalarView(texto.unicodeScalars.map { s in
            (0x3041 ... 0x3096).contains(s.value) ? Unicode.Scalar(s.value + 0x60)! : s
        }))
    }

    static func deKatakanaAHiragana(_ texto: String) -> String {
        String(String.UnicodeScalarView(texto.unicodeScalars.map { s in
            (0x30A1 ... 0x30F6).contains(s.value) ? Unicode.Scalar(s.value - 0x60)! : s
        }))
    }

    /// Lectura Hepburn de una unidad de kana (し → shi, ぢ → ji). Lo desconocido se devuelve igual.
    static func aRomaji(_ unidad: String) -> String {
        let hiragana = deKatakanaAHiragana(unidad)
        if let romaji = hepburn[hiragana] { return romaji }
        return unidad
    }

    private static let hepburn: [String: String] = {
        var r: [String: String] = ["ぢ": "ji", "づ": "zu", "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "っ": "",
                                     "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o"]
        for (romaji, _) in Kana.silabaFila { r[aHiragana(romaji)] = romaji }
        return r
    }()
}

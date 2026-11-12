import Foundation

/// Port de `src/kana.js`: filas del silabario, mazos de tarjetas y sílabas → unidades de kana.
enum Silabario: String, CaseIterable, Codable, Identifiable {
    case hiragana, katakana
    var id: String { rawValue }
    var nombre: String { self == .hiragana ? "Hiragana" : "Katakana" }
}

struct Unidad: Hashable, Codable {
    let romaji: String
    let kana: String
    let row: String
}

struct Tarjeta: Hashable, Codable {
    let romaji: String
    let kana: String
    let silabario: Silabario
}

struct Fila: Identifiable {
    let id: String
    let label: String
    let example: String
}

enum Kana {
    static let filas: [Fila] = [
        ("a", "A", "あ"), ("ka", "KA", "か"), ("sa", "SA", "さ"), ("ta", "TA", "た"), ("na", "NA", "な"),
        ("ha", "HA", "は"), ("ma", "MA", "ま"), ("ya", "YA", "や"), ("ra", "RA", "ら"), ("wa", "WA/N", "わ"),
        ("ga", "GA", "が"), ("za", "ZA", "ざ"), ("da", "DA", "だ"), ("ba", "BA", "ば"), ("pa", "PA", "ぱ"),
        ("kya", "KYA", "きゃ"), ("sha", "SHA", "しゃ"), ("cha", "CHA", "ちゃ"), ("nya", "NYA", "にゃ"),
        ("hya", "HYA", "ひゃ"), ("mya", "MYA", "みゃ"), ("rya", "RYA", "りゃ"), ("gya", "GYA", "ぎゃ"),
        ("ja", "JA", "じゃ"), ("bya", "BYA", "びゃ"), ("pya", "PYA", "ぴゃ"),
    ].map { Fila(id: $0.0, label: $0.1, example: $0.2) }

    /// Romaji → fila, en el mismo orden que `SYLLABLE_ROW` de la web (el orden fija el del mazo).
    static let silabaFila: [(String, String)] = {
        var r: [(String, String)] = []
        func agregar(_ fila: String, _ silabas: String) {
            r += silabas.split(separator: " ").map { (String($0), fila) }
        }
        agregar("a", "a i u e o"); agregar("ka", "ka ki ku ke ko"); agregar("sa", "sa shi su se so")
        agregar("ta", "ta chi tsu te to"); agregar("na", "na ni nu ne no"); agregar("ha", "ha hi fu he ho")
        agregar("ma", "ma mi mu me mo"); agregar("ya", "ya yu yo"); agregar("ra", "ra ri ru re ro")
        agregar("wa", "wa wo n"); agregar("ga", "ga gi gu ge go"); agregar("za", "za ze zo")
        agregar("da", "da"); agregar("za", "ji zu"); agregar("da", "de do"); agregar("ba", "ba bi bu be bo")
        agregar("pa", "pa pi pu pe po")
        for fila in ["kya", "sha", "cha", "nya", "hya", "mya", "rya", "gya", "ja", "bya", "pya"] {
            let base = String(fila.dropLast())
            agregar(fila, "\(base)a \(base)u \(base)o")
        }
        return r
    }()

    private static let filaPorSilaba = Dictionary(uniqueKeysWithValues: silabaFila)
    private static let filasBasicas: Set = ["a", "ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa"]

    enum Mazo: String, CaseIterable, Codable { case basicos, todos }

    static func mazo(_ silabario: Silabario, _ mazo: Mazo) -> [Tarjeta] {
        silabaFila
            .filter { mazo == .todos || filasBasicas.contains($0.1) }
            .map { Tarjeta(romaji: $0.0, kana: silabaAKana($0.0, silabario), silabario: silabario) }
    }

    /// Fila de una sílaba ("n" y "wo" viven en la fila わ).
    static func fila(de romaji: String) -> String { filaPorSilaba[romaji] ?? "a" }

    static func silabaAKana(_ romaji: String, _ silabario: Silabario) -> String {
        if romaji == "n" { return silabario == .katakana ? "ン" : "ん" }
        return silabario == .katakana ? Romaji.aKatakana(romaji) : Romaji.aHiragana(romaji)
    }

    static func unidades(_ palabras: [[String]], _ silabario: Silabario) -> [[Unidad]] {
        palabras.map { $0.map { Unidad(romaji: $0, kana: silabaAKana($0, silabario), row: fila(de: $0)) } }
    }

    static func ejemplo(fila id: String, _ silabario: Silabario) -> String {
        guard let fila = filas.first(where: { $0.id == id }) else { return "" }
        return silabario == .katakana ? Romaji.deHiraganaAKatakana(fila.example) : fila.example
    }
}

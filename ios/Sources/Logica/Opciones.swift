import Foundation

/// Opciones de una tarjeta de opción múltiple: la lectura correcta y 3 falsas del mismo silabario. Primero kana que
/// se confunden a la vista con el mostrado, luego de su misma fila o columna, luego cualquiera (modo de fallo 89).
enum Opciones {
    static let cantidad = 4

    /// Grupos de kana que se confunden a la vista.
    private static let parecidos: [Set<String>] = [
        ["ぬ", "め", "の", "あ", "お", "む"], ["わ", "れ", "ね"], ["る", "ろ", "う"], ["さ", "ち", "き", "ら"],
        ["は", "ほ", "け", "よ", "ま"], ["い", "り", "こ", "に"], ["く", "へ", "し", "つ"], ["た", "な", "に"],
        ["そ", "て", "ろ"], ["ゆ", "や", "わ"], ["み", "む", "も"], ["す", "お", "む"], ["ひ", "ふ", "う"],
        ["シ", "ツ", "ソ", "ン", "ノ", "リ"], ["ク", "ケ", "タ", "ワ", "ウ", "フ", "ヌ", "ス", "ラ", "ヲ"],
        ["コ", "ユ", "ロ", "エ", "ヨ"], ["チ", "テ", "ナ", "ト"], ["ア", "マ", "ヤ", "ム"], ["カ", "ヤ", "セ"],
        ["ル", "レ", "ハ"], ["メ", "ヌ", "ナ", "オ"], ["セ", "サ", "ヒ", "モ"], ["キ", "モ", "チ", "サ"], ["ホ", "オ", "ネ"],
    ]

    private static func vocal(_ r: String) -> Character? { r.last.flatMap { "aeiou".contains($0) ? $0 : nil } }
    private static func consonante(_ r: String) -> String { vocal(r) == nil ? r : String(r.dropLast()) }

    /// Lecturas para mostrar, ya barajadas. `mazo`: tarjetas de donde salen las falsas.
    static func para(_ t: Tarjeta, mazo: [Tarjeta], azar: inout some RandomNumberGenerator) -> [String] {
        var vistas: Set<String> = [t.romaji]
        // Nada que también sea una lectura válida de la tarjeta (じ y ぢ son «ji»; し acepta «si») (modo de fallo 88).
        func filtrar(_ lista: [Tarjeta]) -> [Tarjeta] {
            lista.filter { x in
                x.silabario == t.silabario && !Check.esLecturaCorrecta(t.romaji, x.romaji)
                    && !Check.esLecturaCorrecta(x.romaji, t.romaji) && vistas.insert(x.romaji).inserted
            }
        }
        // Del mazo que se juega (en básicos no salen «pa» ni «kya»); del mazo completo solo si no alcanza.
        var validas = filtrar(mazo)
        if validas.count < cantidad - 1 { validas += filtrar(Kana.mazo(t.silabario, .todos)) }
        let visuales = validas.filter { x in parecidos.contains { $0.contains(t.kana) && $0.contains(x.kana) } }
        let fila = validas.filter { consonante($0.romaji) == consonante(t.romaji) || vocal($0.romaji) == vocal(t.romaji) }
        var falsas: [String] = []
        for (grupo, maximo) in [(visuales, 2), (fila, cantidad - 1), (validas, cantidad - 1)] {
            for x in grupo.shuffled(using: &azar) where falsas.count < maximo && !falsas.contains(x.romaji) {
                falsas.append(x.romaji)
            }
        }
        return (falsas.prefix(cantidad - 1) + [t.romaji]).shuffled(using: &azar)  // posición al azar (modo de fallo 90)
    }
}

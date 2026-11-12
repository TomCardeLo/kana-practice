import Foundation

// Compara la lógica Swift (ios/Sources/Logica) con ios/Paridad/paridad.json, generado desde los módulos
// JS reales (npm run paridad). Modo de fallo 47. Uso: ios/scripts/paridad.sh
let ruta = CommandLine.arguments.dropFirst().first ?? "ios/Paridad/paridad.json"
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ruta))) as! [String: Any]
var fallos = 0, casos = 0

/// JSONEncoder omite las claves nil; se quitan también los null de JS para comparar igual.
func sinNulos(_ v: Any) -> Any {
    if let d = v as? [String: Any] { return d.filter { !($0.value is NSNull) }.mapValues(sinNulos) }
    if let a = v as? [Any] { return a.map(sinNulos) }
    return v
}

func comparar(_ seccion: String, _ entrada: Any, _ esperado: Any, _ obtenido: Any) {
    casos += 1
    let e = try! JSONSerialization.data(withJSONObject: ["v": sinNulos(esperado)], options: .sortedKeys)
    let o = try! JSONSerialization.data(withJSONObject: ["v": obtenido], options: .sortedKeys)
    if e != o {
        fallos += 1
        if fallos <= 40 {
            print("✗ \(seccion) \(entrada)\n   JS:    \(String(decoding: e, as: UTF8.self))\n   Swift: \(String(decoding: o, as: UTF8.self))")
        }
    }
}

func filas(_ s: String) -> [[String: Any]] { json[s] as! [[String: Any]] }
func dic<T: Encodable>(_ v: T) -> Any { try! JSONSerialization.jsonObject(with: JSONEncoder().encode(v), options: .fragmentsAllowed) }
func silabario(_ s: Any?) -> Silabario { Silabario(rawValue: s as! String)! }

for c in filas("translit") { comparar("translit", c["entrada"]!, c["silabas"]!, Translit.silabas(c["entrada"] as! String)) }
for c in filas("toHiragana") { comparar("toHiragana", c["entrada"]!, c["salida"]!, Romaji.aHiragana((c["entrada"] as! String).lowercased())) }
for c in filas("toKatakana") { comparar("toKatakana", c["entrada"]!, c["salida"]!, Romaji.aKatakana((c["entrada"] as! String).lowercased())) }
for c in filas("toRomaji") { comparar("toRomaji", c["entrada"]!, c["salida"]!, Romaji.aRomaji(c["entrada"] as! String)) }
for c in filas("units") {
    comparar("units", "\(c["entrada"]!) \(c["silabario"]!)", c["units"]!,
             dic(Kana.unidades(Translit.silabas(c["entrada"] as! String), silabario(c["silabario"]))))
}
for c in filas("deck") {
    comparar("deck", "\(c["silabario"]!) \(c["mazo"]!)", c["cartas"]!,
             dic(Kana.mazo(silabario(c["silabario"]), Kana.Mazo(rawValue: c["mazo"] as! String)!)))
}
for c in filas("isCorrectReading") {
    comparar("isCorrectReading", "\(c["romaji"]!) ← \(c["escrito"]!)", c["ok"]!,
             Check.esLecturaCorrecta(c["romaji"] as! String, c["escrito"] as! String))
}
for c in filas("countTypedUnits") { comparar("countTypedUnits", c["entrada"]!, c["n"]!, Check.unidadesEscritas(c["entrada"] as! String)) }
for c in filas("checkAnswer") {
    let esperadas = Kana.unidades(Translit.silabas(c["texto"] as! String), .hiragana)
    let r = Check.corregir(esperadas, c["respuesta"] as! String)
    comparar("checkAnswer", "\(c["texto"]!) ← \(c["respuesta"]!)", c["resultado"] ?? NSNull(), r.map(dic) ?? NSNull())
}

print(fallos == 0 ? "✓ Paridad JS/Swift: \(casos) casos" : "✗ \(fallos) de \(casos) casos difieren")
exit(fallos == 0 ? 0 : 1)

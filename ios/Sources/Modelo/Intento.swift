import Foundation
import SwiftData
import OSLog
import UIKit

/// Una respuesta a un kana. Solo se añade, nunca se edita: es la fuente de verdad del progreso y lo que
/// se sincronizará con el servidor en la fase 2 (modo de fallo 53).
@Model
final class Intento {
    @Attribute(.unique) var id: UUID
    var fecha: Date
    var dispositivo: String
    /// "tarjeta" o "lectura".
    var ejercicio: String
    /// El kana tal como se mostró (か, キャ).
    var item: String
    var silabario: String
    var correcto: Bool
    var respuesta: String?
    var latenciaMs: Int?
    var sincronizado: Bool

    convenience init(ejercicio: String, item: String, silabario: Silabario, correcto: Bool, respuesta: String?,
         latenciaMs: Int?, dispositivo: String, fecha: Date = .now) {
        self.init(id: UUID(), ejercicio: ejercicio, item: item, silabario: silabario, correcto: correcto,
                  respuesta: respuesta, latenciaMs: latenciaMs, dispositivo: dispositivo, fecha: fecha, sincronizado: false)
    }

    /// Intento bajado de Deepy (de otro dispositivo): conserva su id y ya está sincronizado.
    convenience init(remoto id: UUID, fecha: Date, dispositivo: String, ejercicio: String, item: String,
                     silabario: Silabario, correcto: Bool, respuesta: String?, latenciaMs: Int?) {
        self.init(id: id, ejercicio: ejercicio, item: item, silabario: silabario, correcto: correcto,
                  respuesta: respuesta, latenciaMs: latenciaMs, dispositivo: dispositivo, fecha: fecha, sincronizado: true)
    }

    private init(id: UUID, ejercicio: String, item: String, silabario: Silabario, correcto: Bool, respuesta: String?,
                 latenciaMs: Int?, dispositivo: String, fecha: Date, sincronizado: Bool) {
        self.id = id
        self.fecha = fecha
        self.dispositivo = dispositivo
        self.ejercicio = ejercicio
        self.item = item
        self.silabario = silabario.rawValue
        self.correcto = correcto
        self.respuesta = respuesta
        self.latenciaMs = latenciaMs
        self.sincronizado = sincronizado
    }
}

@MainActor
enum Progreso {
    static let dispositivo = UIDevice.current.identifierForVendor?.uuidString ?? "desconocido"

    static let log = Logger(subsystem: "com.tommycardelo.kana", category: "progreso")

    /// Guarda en el acto: cerrar la app a mitad de ronda no pierde lo respondido (modo de fallo 52).
    /// Si falla, lanza el error para que la vista lo muestre: nunca se pierde progreso en silencio.
    static func registrar(_ intentos: [Intento], en contexto: ModelContext) throws {
        intentos.forEach(contexto.insert)
        do {
            try contexto.save()
        } catch {
            log.error("No se pudo guardar el progreso: \(error, privacy: .public)")
            throw error
        }
    }

    // Récord de tarjetas por configuración: comodidad local del dispositivo, no progreso.
    static func record(_ clave: String) -> Int? {
        UserDefaults.standard.object(forKey: "record-tarjetas.\(clave)") as? Int
    }

    /// Guarda `ms` si mejora el récord. Devuelve true si es récord nuevo.
    static func guardarRecord(_ clave: String, _ ms: Int) -> Bool {
        if let anterior = record(clave), ms >= anterior { return false }
        UserDefaults.standard.set(ms, forKey: "record-tarjetas.\(clave)")
        return true
    }
}

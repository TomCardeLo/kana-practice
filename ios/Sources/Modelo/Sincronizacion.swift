import Foundation
import OSLog
import Security
import SwiftData

/// Sincroniza los intentos con Deepy (`/api/v1/kana/intentos`, contrato en deepy_web/docs/api-v1.md):
/// cada dispositivo sube los suyos y baja los de los demás, así rachas y estadísticas suman el iPhone y el
/// iPad. Se puede practicar sin red: lo pendiente sube en la siguiente sincronización.
///
/// Modos de fallo (escritos antes del código):
/// Y1 Un lote se sube dos veces (la red se cortó tras guardar): el servidor no duplica por id; aquí solo
///    se marca `sincronizado` tras un 200.
/// Y2 Se bajan los intentos propios o los mismos dos veces: se pide con `excluir` y se descartan los ids
///    que ya existen.
/// Y3 Dos subidas casi simultáneas se confirman en desorden y el cursor se salta filas: se pide con un
///    solape de 400 (el doble del lote máximo).
/// Y4 Sin red, token vencido o servidor caído: el estado lo dice en pantalla; nunca se pierde lo local.
/// Y5 Dos sincronizaciones a la vez suben el mismo lote: una sola a la vez.
/// Y6 La compilación Release habla con otro servidor que no sea producción.
@MainActor
@Observable
final class Sincronizador {
    enum Estado: Equatable {
        case sinConexion  // no hay token: falta conectar con Deepy
        case inactivo
        case sincronizando
        case listo(Date)
        case error(String)
    }

    enum Fallo: LocalizedError {
        case sinRed, noAutorizado, servidor(String), respuestaInvalida, llavero(OSStatus)
        var errorDescription: String? {
            switch self {
            case .sinRed: "Sin conexión con Deepy. Lo pendiente se subirá al volver la red."
            case .noAutorizado: "La sesión con Deepy expiró. Vuelve a conectar."
            case let .servidor(mensaje): mensaje
            case .respuestaInvalida: "Deepy respondió algo inesperado."
            case let .llavero(estado): "No se pudo guardar la sesión en el llavero (código \(estado))."
            }
        }
    }

    static let loteMaximo = 200
    static let solape = 400  // Y3
    private static let claveCursor = "sync.cursor"
    private static let log = Logger(subsystem: "com.tommycardelo.kana", category: "sincronizacion")

    private(set) var estado: Estado = .inactivo
    private(set) var pendientes = 0
    private let contexto: ModelContext
    private let llavero: Llavero
    private let base: URL
    private let sesion: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    var conectado: Bool { llavero.leer() != nil }

    init(contexto: ModelContext, enPrueba: Bool) {
        self.contexto = contexto
        llavero = Llavero(servicio: enPrueba ? "com.tommycardelo.kana.uitest" : "com.tommycardelo.kana")
        if enPrueba {
            llavero.borrar()
            UserDefaults.standard.removeObject(forKey: Self.claveCursor)
        }
        base = Self.urlBase()
        if !conectado { estado = .sinConexion }
    }

    /// `KANA_BASE_URL` solo existe en Debug (las pruebas E2E); Release siempre usa producción (Y6).
    private static func urlBase() -> URL {
        let produccion = URL(string: "https://asistente.tommycardelo.com/api/v1")!
        #if DEBUG
        guard var texto = ProcessInfo.processInfo.environment["KANA_BASE_URL"], !texto.isEmpty else { return produccion }
        while texto.hasSuffix("/") { texto.removeLast() }
        if !texto.hasSuffix("/api/v1") { texto += "/api/v1" }
        guard let url = URL(string: texto) else { preconditionFailure("KANA_BASE_URL inválida: \(texto)") }
        return url
        #else
        return produccion
        #endif
    }

    // MARK: Conexión

    /// Entra con la contraseña de Deepy y guarda el token. Lanza un error con texto para mostrar.
    func conectar(password: String) async throws {
        struct Entrada: Encodable { let password: String }
        struct Salida: Decodable { let token: String }
        let salida: Salida = try await pedir("POST", "/acceso", cuerpo: Entrada(password: password), autenticada: false)
        let estadoLlavero = llavero.guardar(salida.token)
        guard estadoLlavero == errSecSuccess else { throw Fallo.llavero(estadoLlavero) }
        estado = .inactivo
        await sincronizar()
    }

    func desconectar() {
        llavero.borrar()
        estado = .sinConexion
    }

    // MARK: Sincronización

    func sincronizar() async {
        guard conectado else { estado = .sinConexion; return }
        guard estado != .sincronizando else { return }  // Y5
        estado = .sincronizando
        do {
            try await subir()
            try await bajar()
            estado = .listo(.now)
        } catch Fallo.noAutorizado {
            llavero.borrar()
            estado = .error(Fallo.noAutorizado.localizedDescription)
        } catch {
            Self.log.error("Sincronización: \(error.localizedDescription, privacy: .public)")
            estado = .error(error.localizedDescription)  // Y4
        }
        contarPendientes()
    }

    func contarPendientes() {
        pendientes = (try? contexto.fetchCount(FetchDescriptor<Intento>(predicate: #Predicate { !$0.sincronizado }))) ?? 0
    }

    private struct IntentoAPI: Codable {
        let id: String
        let fecha: String
        let dispositivo: String
        let ejercicio: String
        let item: String
        let silabario: String
        let correcto: Bool
        let respuesta: String?
        let latenciaMs: Int?
    }

    private static let fechaISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func subir() async throws {
        struct Lote: Encodable { let intentos: [IntentoAPI] }
        struct Respuesta: Decodable { let recibidos: Int }
        while true {
            var consulta = FetchDescriptor<Intento>(predicate: #Predicate { !$0.sincronizado }, sortBy: [SortDescriptor(\.fecha)])
            consulta.fetchLimit = Self.loteMaximo
            let lote = try contexto.fetch(consulta)
            guard !lote.isEmpty else { return }
            let cuerpo = Lote(intentos: lote.map {
                IntentoAPI(id: $0.id.uuidString.lowercased(), fecha: Self.fechaISO.string(from: $0.fecha),
                           dispositivo: $0.dispositivo, ejercicio: $0.ejercicio, item: $0.item,
                           silabario: $0.silabario, correcto: $0.correcto, respuesta: $0.respuesta,
                           latenciaMs: $0.latenciaMs)
            })
            let _: Respuesta = try await pedir("POST", "/kana/intentos", cuerpo: cuerpo)
            lote.forEach { $0.sincronizado = true }  // Y1: solo tras el 200
            try contexto.save()
        }
    }

    private func bajar() async throws {
        struct Pagina: Decodable { let intentos: [IntentoAPI]; let siguiente: Int; let hayMas: Bool }
        var cursor = UserDefaults.standard.integer(forKey: Self.claveCursor)
        var desde = max(0, cursor - Self.solape)  // Y3
        while true {
            let excluir = Progreso.dispositivo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let pagina: Pagina = try await pedir("GET", "/kana/intentos?desde=\(desde)&limite=1000&excluir=\(excluir)")
            let ids = pagina.intentos.compactMap { UUID(uuidString: $0.id) }
            let existentes = Set(try contexto.fetch(FetchDescriptor<Intento>(predicate: #Predicate { ids.contains($0.id) })).map(\.id))
            for remoto in pagina.intentos {  // Y2
                guard let id = UUID(uuidString: remoto.id), !existentes.contains(id),
                      let fecha = Self.fechaISO.date(from: remoto.fecha),
                      let silabario = Silabario(rawValue: remoto.silabario)
                else { continue }
                contexto.insert(Intento(remoto: id, fecha: fecha, dispositivo: remoto.dispositivo,
                                        ejercicio: remoto.ejercicio, item: remoto.item, silabario: silabario,
                                        correcto: remoto.correcto, respuesta: remoto.respuesta,
                                        latenciaMs: remoto.latenciaMs))
            }
            try contexto.save()
            cursor = max(cursor, pagina.siguiente)
            UserDefaults.standard.set(cursor, forKey: Self.claveCursor)
            guard pagina.hayMas else { return }
            desde = pagina.siguiente
        }
    }

    // MARK: HTTP

    private struct CuerpoError: Decodable { let error: String? }

    private func pedir<T: Decodable>(_ metodo: String, _ ruta: String, cuerpo: (some Encodable)? = Optional<String>.none,
                                     autenticada: Bool = true) async throws -> T {
        guard let url = URL(string: base.absoluteString + ruta) else { throw Fallo.respuestaInvalida }
        var req = URLRequest(url: url)
        req.httpMethod = metodo
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if autenticada {
            guard let token = llavero.leer() else { throw Fallo.noAutorizado }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let cuerpo {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(cuerpo)
        }
        let datos: Data, respuesta: URLResponse
        do {
            (datos, respuesta) = try await sesion.data(for: req)
        } catch {
            Self.log.error("Red \(metodo) \(ruta, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw Fallo.sinRed
        }
        guard let http = respuesta as? HTTPURLResponse else { throw Fallo.respuestaInvalida }
        guard (200 ..< 300).contains(http.statusCode) else {
            let mensaje = (try? JSONDecoder().decode(CuerpoError.self, from: datos))?.error
            Self.log.error("HTTP \(http.statusCode) \(metodo) \(ruta, privacy: .public): \(mensaje ?? "-", privacy: .public)")
            if http.statusCode == 401 { throw autenticada ? Fallo.noAutorizado : Fallo.servidor(mensaje ?? "Contraseña incorrecta.") }
            throw Fallo.servidor(mensaje ?? "Error del servidor (\(http.statusCode)).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: datos)
        } catch {
            throw Fallo.respuestaInvalida
        }
    }
}

/// Token de Deepy en el llavero, solo en este dispositivo y tras el primer desbloqueo.
struct Llavero {
    let servicio: String
    private var consulta: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio,
         kSecAttrAccount as String: "token"]
    }

    func leer() -> String? {
        var q = consulta
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data else { return nil }
        return String(data: datos, encoding: .utf8)
    }

    func guardar(_ token: String) -> OSStatus {
        borrar()
        var q = consulta
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil)
    }

    func borrar() { SecItemDelete(consulta as CFDictionary) }
}

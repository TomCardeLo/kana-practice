import SwiftData
import SwiftUI

@main
struct KanaApp: App {
    /// Las pruebas E2E arrancan con `-uitest`: progreso en memoria, récords y sesión limpios.
    private static let enPrueba = ProcessInfo.processInfo.arguments.contains("-uitest")

    private let contenedor: ModelContainer
    @State private var sincronizador: Sincronizador

    init() {
        if Self.enPrueba, let dominio = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: dominio)
        }
        do {
            contenedor = try ModelContainer(for: Intento.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: Self.enPrueba))
        } catch {
            fatalError("No se pudo abrir el almacén de progreso: \(error)")
        }
        _sincronizador = State(initialValue: Sincronizador(contexto: contenedor.mainContext, enPrueba: Self.enPrueba))
        // E2E del modo de fallo Y7: un intento que el servidor rechaza (fecha anterior a 2026) no debe bloquear
        // la subida del otro, válido.
        if Self.enPrueba, ProcessInfo.processInfo.arguments.contains("-uitest-intento-rechazado") {
            contenedor.mainContext.insert(Intento(ejercicio: "tarjeta", item: "あ", silabario: .hiragana, correcto: true,
                                                  respuesta: "a", latenciaMs: 900, dispositivo: Progreso.dispositivo,
                                                  fecha: Date(timeIntervalSince1970: 1_735_689_600)))  // 2025-01-01
            contenedor.mainContext.insert(Intento(ejercicio: "tarjeta", item: "ア", silabario: .katakana, correcto: true,
                                                  respuesta: "a", latenciaMs: 900, dispositivo: Progreso.dispositivo))
        }
    }

    var body: some Scene {
        WindowGroup {
            RaizVista()
                .environment(sincronizador)
        }
        .modelContainer(contenedor)
    }
}

struct RaizVista: View {
    @Environment(Sincronizador.self) private var sincronizador
    @Environment(\.scenePhase) private var fase
    @State private var pedirConexion = false

    var body: some View {
        TabView {
            Tab("Tarjetas", systemImage: "rectangle.on.rectangle.angled") { TarjetasVista() }
            Tab("Leer", systemImage: "character.book.closed.ja") { LecturaVista() }
            Tab("Progreso", systemImage: "chart.bar.xaxis") { ProgresoVista() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.verde)
        .sheet(isPresented: $pedirConexion) { ConexionVista() }
        // La sesión venció a mitad de una sincronización: se vuelve a pedir, no solo se dice en Progreso.
        .onChange(of: sincronizador.necesitaConexion) { _, pedir in if pedir { pedirConexion = true } }
        .task {
            // Una vez al abrir: sin sesión se pide conectar (se puede posponer; practicar no depende de la red).
            // En las pruebas E2E solo si la prueba lo pide, para no tapar las demás.
            let argumentos = ProcessInfo.processInfo.arguments
            let silenciar = argumentos.contains("-uitest") && !argumentos.contains("-uitest-conexion")
            if !sincronizador.conectado, !silenciar { pedirConexion = true }
        }
        .onChange(of: fase, initial: true) { _, nueva in
            if nueva == .active { Task { await sincronizador.sincronizar() } }
        }
    }
}

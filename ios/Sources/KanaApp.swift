import SwiftData
import SwiftUI

@main
struct KanaApp: App {
    /// Las pruebas E2E arrancan con `-uitest`: progreso en memoria y récords limpios.
    private static let enPrueba = ProcessInfo.processInfo.arguments.contains("-uitest")

    private let contenedor: ModelContainer = {
        if enPrueba, let dominio = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: dominio)
        }
        do {
            return try ModelContainer(for: Intento.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: enPrueba))
        } catch {
            fatalError("No se pudo abrir el almacén de progreso: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RaizVista()
        }
        .modelContainer(contenedor)
    }
}

struct RaizVista: View {
    var body: some View {
        TabView {
            Tab("Tarjetas", systemImage: "rectangle.on.rectangle.angled") { TarjetasVista() }
            Tab("Leer", systemImage: "character.book.closed.ja") { LecturaVista() }
            Tab("Progreso", systemImage: "chart.bar.xaxis") { ProgresoVista() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.verde)
    }
}

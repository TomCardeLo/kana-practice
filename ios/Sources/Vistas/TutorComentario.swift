import SwiftUI

/// Comentario del tutor (Claude en Deepy) sobre la sesión que empezó en `inicio`. Se pide al aparecer el resumen.
/// Compartido por Tarjetas y Palabras: las protecciones contra respuestas tardías viven aquí una sola vez.
struct TutorComentario: View {
    let inicio: Date
    @Environment(Sincronizador.self) private var sincronizador
    @State private var estado = Estado.nada
    /// El resumen está en pantalla. Oculto (otra pestaña) no se gasta la llamada a Claude: se pide al volver.
    @State private var visible = true

    private enum Estado: Equatable { case nada, sinConexion, pensando, listo(String), error(String, reintentable: Bool) }

    var body: some View {
        Seccion(numero: "·", titulo: "Tutor") {
            switch estado {
            case .nada, .pensando:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("El tutor está mirando tu sesión…").foregroundStyle(Color.tintaSuave)
                }
                .accessibilityIdentifier("tutor-pensando")
            case .sinConexion:
                Text("Conecta con Deepy (Progreso → Ajustes) para recibir el comentario del tutor.")
                    .foregroundStyle(Color.tintaSuave).accessibilityIdentifier("tutor-sin-conexion")
            case let .listo(texto):
                Text(texto).accessibilityIdentifier("tutor-comentario")
            case let .error(mensaje, reintentable):
                Text(mensaje).foregroundStyle(reintentable ? Color.rojo : Color.tintaSuave).accessibilityIdentifier("tutor-error")
                if reintentable {
                    Button("Reintentar", action: pedir).buttonStyle(.bordered).accessibilityIdentifier("btn-tutor-reintentar")
                }
            }
        }
        .onAppear {
            visible = true
            if estado == .nada { pedir() }  // volver a la pestaña no pide otro comentario
        }
        .onDisappear { visible = false }
        // Terminó sin conexión y luego se conectó: se pide el comentario de esa sesión.
        .onChange(of: sincronizador.conectado) { _, conectado in
            if conectado, estado == .sinConexion { pedir() }
        }
    }

    /// Una tarea propia (no la de la vista): cancelarla a mitad de una sincronización dejaría el estado global en
    /// error.
    private func pedir() {
        guard sincronizador.conectado else { estado = .sinConexion; return }
        estado = .pensando
        Task {
            let nuevo: Estado
            do {
                guard let texto = try await sincronizador.comentarSesion(desde: inicio, vigente: { visible }) else {
                    estado = .nada  // se ocultó antes de llamar a Claude: el próximo onAppear lo vuelve a pedir
                    return
                }
                nuevo = .listo(texto)
            } catch Sincronizador.Fallo.noDisponible(let mensaje) {
                nuevo = .error(mensaje, reintentable: false)  // tope o servidor sin clave: reintentar no sirve
            } catch {
                nuevo = .error(error.localizedDescription, reintentable: true)
            }
            // Se aplica aunque el resumen esté oculto: al volver a la pestaña se ve (nunca un «pensando» eterno). Si
            // la sesión ya es otra, `.id(inicio)` hizo esta vista nueva y esto no la toca.
            estado = nuevo
            guard visible else { return }
            // El resultado llega segundos después y quizá fuera de pantalla: VoiceOver lo anuncia.
            if case let .listo(texto) = nuevo { AccessibilityNotification.Announcement("Tutor: \(texto)").post() }
            if case let .error(mensaje, _) = nuevo { AccessibilityNotification.Announcement(mensaje).post() }
        }
    }
}

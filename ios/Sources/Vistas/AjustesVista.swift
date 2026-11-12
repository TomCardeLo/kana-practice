import SwiftUI

/// Ajustes de la app: sonido y vibración (modo de fallo 58).
struct AjustesVista: View {
    @AppStorage(Efectos.claveSonido) private var sonido = true
    @AppStorage(Efectos.claveVibracion) private var vibracion = true
    @Environment(\.dismiss) private var cerrar
    @Environment(Sincronizador.self) private var sincronizador
    @State private var verConexion = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sonidos", isOn: $sonido).accessibilityIdentifier("ajuste-sonido")
                    Toggle("Vibración", isOn: $vibracion).accessibilityIdentifier("ajuste-vibracion")
                } footer: {
                    Text("Los sonidos respetan el modo silencio del iPhone y no cortan tu música.")
                }
                Section("Deepy") {
                    if sincronizador.conectado {
                        Button("Desconectar este equipo", role: .destructive) { sincronizador.desconectar() }
                            .accessibilityIdentifier("btn-desconectar")
                    } else {
                        Button("Conectar con Deepy") { verConexion = true }.accessibilityIdentifier("btn-ir-conectar")
                    }
                }
                Section("Meta diaria") {
                    LabeledContent("Respuestas al día", value: "\(Rachas.metaDiaria)")
                }
            }
            .navigationTitle("Ajustes")
            .sheet(isPresented: $verConexion) { ConexionVista() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
        }
    }
}

import SwiftUI

/// Ajustes de la app: sonido y vibración (modo de fallo 58).
struct AjustesVista: View {
    @AppStorage(Efectos.claveSonido) private var sonido = true
    @AppStorage(Efectos.claveVibracion) private var vibracion = true
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sonidos", isOn: $sonido).accessibilityIdentifier("ajuste-sonido")
                    Toggle("Vibración", isOn: $vibracion).accessibilityIdentifier("ajuste-vibracion")
                } footer: {
                    Text("Los sonidos respetan el modo silencio del iPhone y no cortan tu música.")
                }
                Section("Meta diaria") {
                    LabeledContent("Respuestas al día", value: "\(Rachas.metaDiaria)")
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
        }
    }
}

import SwiftUI

/// Conectar con Deepy (misma contraseña que la app de Deepy) para sincronizar el progreso entre equipos.
struct ConexionVista: View {
    @Environment(Sincronizador.self) private var sincronizador
    @Environment(\.dismiss) private var cerrar
    @State private var password = ""
    @State private var error: String?
    @State private var enviando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Contraseña de Deepy", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(conectar)
                        .accessibilityIdentifier("conexion-password")
                    if let error {
                        Text(error).foregroundStyle(Color.rojo).accessibilityIdentifier("conexion-error")
                    }
                } footer: {
                    Text("Tu progreso se guarda en Deepy para que el iPhone y el iPad sumen la misma racha. Puedes practicar sin conexión: lo pendiente se sube después.")
                }
                Button(action: conectar) {
                    if enviando { ProgressView() } else { Text("Conectar") }
                }
                .disabled(password.isEmpty || enviando)
                .accessibilityIdentifier("btn-conectar")
            }
            .navigationTitle("Conectar con Deepy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Más tarde") { cerrar() }.accessibilityIdentifier("btn-mas-tarde")
                }
            }
        }
    }

    private func conectar() {
        guard !password.isEmpty, !enviando else { return }
        enviando = true
        error = nil
        Task {
            do {
                try await sincronizador.conectar(password: password)
                cerrar()
            } catch {
                self.error = error.localizedDescription
            }
            enviando = false
        }
    }
}

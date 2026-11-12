import SwiftData
import SwiftUI

/// «Hoy»: kana que tocan según FSRS más los nuevos del día. Solo existe en la pantalla de configuración, así
/// que no se recalcula mientras se juega (modo de fallo 85).
struct RepasoHoy: View {
    @Query private var intentos: [Intento]
    let empezar: ([Tarjeta]) -> Void

    var body: some View {
        // Las unidades de una lectura que no se llegaron a escribir no son un repaso fallido.
        let plan = Repaso.plan(intentos.filter { !($0.ejercicio == "lectura" && $0.respuesta == nil) }.compactMap(\.comoRespuesta))
        Seccion(numero: "·", titulo: "Hoy") {
            Text("\(plan.pendientes.count) por repasar · \(plan.nuevas.count) nuevas")
                .font(.headline.monospacedDigit())
                .accessibilityIdentifier("hoy-plan")
            if plan.sesion.isEmpty {
                Text("Nada pendiente por hoy. Vuelve mañana, o juega una ronda libre.")
                    .foregroundStyle(Color.tintaSuave)
                    .accessibilityIdentifier("hoy-nada")
            } else {
                Text("Repaso espaciado: cada kana vuelve justo antes de que lo olvides. Sin vidas.")
                    .font(.subheadline).foregroundStyle(Color.tintaSuave)
                Button { empezar(plan.sesion) } label: {
                    Text("Repasar ahora (\(plan.sesion.count))").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.verde)
                .accessibilityIdentifier("btn-repasar")
            }
        }
    }
}

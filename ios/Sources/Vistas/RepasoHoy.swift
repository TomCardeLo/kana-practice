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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Repaso de hoy").font(.title3.weight(.black))
                Spacer()
                if !plan.sesion.isEmpty {
                    Text("≈ \(max(1, plan.sesion.count * 12 / 60)) min").font(.subheadline).foregroundStyle(Color.tintaSuave)
                }
            }
            HStack(spacing: 8) {
                Ficha(texto: "\(plan.pendientes.count) por repasar")
                Ficha(texto: "\(plan.nuevas.count) nuevas", fondo: .verdeFondo, tinta: .verdeTinta)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(plan.pendientes.count) por repasar · \(plan.nuevas.count) nuevas")
            .accessibilityIdentifier("hoy-plan")
            if plan.sesion.isEmpty {
                Text("Nada pendiente por hoy. Vuelve mañana, o juega una ronda libre.")
                    .foregroundStyle(Color.tintaSuave)
                    .accessibilityIdentifier("hoy-nada")
            } else {
                Button { empezar(plan.sesion) } label: {
                    Label("Repasar ahora (\(plan.sesion.count))", systemImage: "arrow.right").labelStyle(TextoYIcono())
                }
                .buttonStyle(EstiloPrincipal())
                .accessibilityIdentifier("btn-repasar")
            }
        }
        .bloque()
    }
}

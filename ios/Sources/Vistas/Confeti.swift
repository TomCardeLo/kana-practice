import SwiftUI

/// Confeti al batir un récord o cumplir la meta. Con «Reducir movimiento» no se muestra, y nunca bloquea
/// los toques (modo de fallo 70).
struct Confeti: View {
    /// Cambia el valor para lanzar otra ráfaga.
    let disparo: Int
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var inicio: Date?

    private static let duracion = 2.6
    private static let colores: [Color] = [.verde, .rojo, Color(claro: 0xE8B931, oscuro: 0xF5D061), .tinta, Color(claro: 0x6ECFB3, oscuro: 0x6ECFB3)]

    private struct Pieza {
        let x: Double, retraso: Double, velocidad: Double, giro: Double, vaiven: Double, color: Color, ancho: Double
    }

    /// En @State: si no, cada redibujado del padre las sortea de nuevo y saltan mientras caen.
    @State private var piezas: [Pieza] = (0 ..< 70).map { _ in
        Pieza(x: .random(in: 0 ... 1), retraso: .random(in: 0 ... 0.5), velocidad: .random(in: 0.55 ... 1.0),
              giro: .random(in: 2 ... 9), vaiven: .random(in: 8 ... 30), color: colores.randomElement()!,
              ancho: .random(in: 6 ... 11))
    }

    var body: some View {
        // El reloj de animación solo existe mientras cae: en reposo no queda nada animándose (ahorra batería y deja a
        // XCTest ver la app quieta).
        ZStack {
            if let inicio { lluvia(desde: inicio) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: disparo) {
            guard !reducirMovimiento else { return }
            inicio = .now
            Task {
                try? await Task.sleep(for: .seconds(Self.duracion))
                inicio = nil
            }
        }
    }

    private func lluvia(desde inicio: Date) -> some View {
        TimelineView(.animation) { contexto in
            Canvas { lienzo, tamano in
                let t = contexto.date.timeIntervalSince(inicio)
                for p in piezas {
                    let tp = t - p.retraso
                    guard tp > 0 else { continue }
                    let y = -20 + tp * p.velocidad * tamano.height * 0.75
                    let x = p.x * tamano.width + sin(tp * p.giro) * p.vaiven
                    let opacidad = max(0, 1 - tp / (Self.duracion - p.retraso))
                    var copia = lienzo
                    copia.opacity = opacidad
                    copia.translateBy(x: x, y: y)
                    copia.rotate(by: .radians(tp * p.giro))
                    copia.fill(Path(CGRect(x: -p.ancho / 2, y: -p.ancho / 4, width: p.ancho, height: p.ancho / 2)), with: .color(p.color))
                }
            }
        }
    }
}

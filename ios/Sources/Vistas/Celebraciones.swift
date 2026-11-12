import SwiftData
import SwiftUI

extension Intento {
    var comoRespuesta: Respuesta? {
        Silabario(rawValue: silabario).map {
            Respuesta(fecha: fecha, item: item, silabario: $0, correcto: correcto, ejercicio: ejercicio, latenciaMs: latenciaMs)
        }
    }
}

/// Aviso y confeti al cumplir la meta del día o dominar una fila. Vive sobre todas las pestañas: la meta puede
/// cumplirse en Tarjetas, en Leer o al bajar respuestas del otro equipo.
struct Celebraciones: View {
    @Query(sort: \Intento.fecha, order: .reverse) private var intentos: [Intento]
    @State private var aviso: String?
    @State private var disparo = 0
    @State private var ocultar: Task<Void, Never>?

    static let claveMeta = "celebracion.meta"
    static let claveHitos = "celebracion.hitos"
    /// Respuestas propias más nuevas que esto son «de ahora» (modo de fallo 71).
    private static let enVivo: TimeInterval = 120

    var body: some View {
        ZStack(alignment: .top) {
            Confeti(disparo: disparo)
            if let aviso {
                Text(aviso)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.papel)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color.verde, in: Capsule())
                    .shadow(radius: 8, y: 4)
                    .padding(.horizontal, 20)
                    .onTapGesture { self.aviso = nil }
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("aviso-celebracion")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: aviso)
        .onChange(of: intentos.count, initial: true) { revisar() }
    }

    // ponytail: recorre todos los intentos en cada respuesta guardada (~ms con miles); si se nota en la latencia
    // con decenas de miles, calcular primero solo la cuenta de hoy con fetchCount.
    /// Solo se anuncia lo que lograron las respuestas recientes de este equipo: se compara con el cálculo sin
    /// ellas. Lo que llegó al bajar historial (reinstalar, el otro equipo) se marca como visto en silencio,
    /// aunque baje justo después de una ronda (modo de fallo 71).
    private func revisar() {
        let defaults = UserDefaults.standard
        let ahora = Date.now
        let antes = intentos.filter { !($0.dispositivo == Progreso.dispositivo && ahora.timeIntervalSince($0.fecha) < Self.enVivo) }
        let hayRecientes = antes.count < intentos.count
        var textos: [String] = []
        var sonido: Efectos.Sonido?

        let racha = Rachas.calcular(intentos.map(\.fecha), ahora: ahora)
        let metaYaEstaba = !hayRecientes || Rachas.calcular(antes.map(\.fecha), ahora: ahora).metaCumplida
        let dia = Calendar.current.dateComponents([.year, .month, .day], from: ahora)  // día local (modo de fallo 61)
        let hoy = "\(dia.year ?? 0)-\(dia.month ?? 0)-\(dia.day ?? 0)"
        if racha.metaCumplida, defaults.string(forKey: Self.claveMeta) != hoy {
            defaults.set(hoy, forKey: Self.claveMeta)  // una vez al día (modo de fallo 64)
            if !metaYaEstaba {
                textos.append(Mensajes.meta(racha.racha))
                sonido = .meta
            }
        }

        let dominadas = Hitos.dominadas(intentos.compactMap(\.comoRespuesta))
        let anunciados = Set(defaults.stringArray(forKey: Self.claveHitos) ?? [])
        let nuevos = dominadas.filter { !anunciados.contains($0.clave) }
        if !nuevos.isEmpty {
            defaults.set(Array(anunciados.union(nuevos.map(\.clave))), forKey: Self.claveHitos)  // modo de fallo 68
            let yaEstaban = hayRecientes ? Hitos.dominadas(antes.compactMap(\.comoRespuesta)) : dominadas
            let logrados = nuevos.subtracting(yaEstaban).sorted()
            if let primero = logrados.first {
                textos.append(Mensajes.hito(primero) + (logrados.count > 1 ? " Y \(logrados.count - 1) más." : ""))
                sonido = sonido ?? .hito
            }
        }

        guard let sonido else { return }
        Efectos.compartidos.reproducir(sonido)
        aviso = textos.joined(separator: "\n")
        disparo += 1
        ocultar?.cancel()
        ocultar = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { aviso = nil }
        }
    }
}

/// Racha y meta del día. Se calcula con todas las respuestas guardadas, también las bajadas (modo de fallo 75).
struct ResumenRacha: View {
    @Query private var intentos: [Intento]
    @Environment(\.dynamicTypeSize) private var tamano

    var body: some View {
        let estado = Rachas.calcular(intentos.map(\.fecha))
        // Dos bloques: el anillo de la meta y la racha en verde (dirección «Matcha»).
        // Con texto de accesibilidad, uno sobre otro: lado a lado no caben.
        let disposicion = tamano.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        disposicion {
            AnilloMeta(hoy: estado.hoy, meta: Rachas.metaDiaria)
            BloqueRacha(racha: estado.racha, mejor: estado.mejor)
        }
    }
}

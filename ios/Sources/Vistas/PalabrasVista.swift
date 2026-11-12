import SwiftData
import SwiftUI

extension Vocabulario {
    /// Listas del bundle (project.yml las copia de datos/). Sin ellas la app no puede funcionar: falla a la vista.
    static let todasLasPalabras = cargar("vocabulario-n5", palabras)
    static let todosLosKanji = cargar("kanji-n5", kanji)

    static func todas(_ tipo: Pregunta.Tipo) -> [Pregunta] { tipo == .vocabulario ? todasLasPalabras : todosLosKanji }

    private static func cargar(_ nombre: String, _ leer: (Data) throws -> [Pregunta]) -> [Pregunta] {
        guard let url = Bundle.main.url(forResource: nombre, withExtension: "json") else { fatalError("Falta \(nombre).json en el bundle") }
        do { return try leer(Data(contentsOf: url)) } catch { fatalError("\(nombre).json ilegible: \(error)") }
    }
}

/// Vocabulario y kanji N5 con repaso espaciado: se ve la palabra o el kanji y se elige su significado entre 4.
struct PalabrasVista: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.scenePhase) private var fase
    /// Copia en @State de la fase: la tarea de la pausa lee el valor de ahora, no el de cuando se tocó.
    @State private var escenaActiva = true
    @State private var tipo = Pregunta.Tipo.vocabulario
    @State private var ronda: RondaPreguntas?
    @State private var inicioSesion = Date.now
    @State private var cronometro = Cronometro()
    @State private var elegida: String?
    @State private var enPausa = false
    @State private var pausa: Task<Void, Never>?
    @State private var mensajeFin = ""
    @State private var errorGuardado: String?

    private static let pausaError: Duration = .milliseconds(2000)  // más que en kana: hay que leer el significado
    private static let toqueMinimoMs = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let ronda, ronda.terminada { resumen(ronda) }
                    else if let ronda { juego(ronda) }
                    else { PlanPalabras(tipo: $tipo, empezar: empezar) }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(Color.papel)
            .navigationTitle("Palabras")
        }
        .onChange(of: fase) { _, nueva in
            escenaActiva = nueva == .active
            guard ronda?.terminada == false, !enPausa else { return }
            if escenaActiva { cronometro.reanudar() } else { cronometro.pausar() }
        }
        .alert("No se pudo guardar el progreso", isPresented: .constant(errorGuardado != nil)) {
            Button("Entendido") { errorGuardado = nil }
        } message: { Text(errorGuardado ?? "") }
    }

    // MARK: Juego

    private func juego(_ ronda: RondaPreguntas) -> some View {
        let p = ronda.actual
        return VStack(spacing: 20) {
            HStack {
                Text("\(ronda.indice + 1)/\(ronda.preguntas.count)").font(.etiqueta).accessibilityIdentifier("progreso")
                if ronda.combo >= 3 {
                    Text("×\(ronda.combo)").font(.etiqueta.weight(.bold)).foregroundStyle(Color.verde)
                        .accessibilityLabel("Combo de \(ronda.combo)").accessibilityIdentifier("combo")
                }
                Spacer()
                Text(p.tipo == .vocabulario ? "VOCABULARIO" : "KANJI").font(.etiqueta)
            }
            .foregroundStyle(Color.tintaSuave)

            VStack(spacing: 6) {
                if let lectura = p.lectura {
                    Text(lectura).font(.kana(22, relativeTo: .title3)).foregroundStyle(Color.tintaSuave)
                        .accessibilityIdentifier("pregunta-lectura")
                }
                Text(p.texto)
                    .font(.kana(p.tipo == .kanji ? 120 : 56))
                    .minimumScaleFactor(0.4).lineLimit(1)
                    .accessibilityIdentifier("pregunta-texto")
                if enPausa, let detalle = p.detalle {
                    Text(detalle).font(.kana(17, relativeTo: .body)).foregroundStyle(Color.tintaSuave)
                        .accessibilityIdentifier("pregunta-detalle")
                }
            }
            .foregroundStyle(Color.tinta)
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding(.horizontal, 16)
            .background(Color.papel2, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(enPausa ? Color.rojo : Color.linea, lineWidth: enPausa ? 2 : 1))

            VStack(spacing: 10) {
                ForEach(Array(ronda.opciones.enumerated()), id: \.offset) { i, opcion in
                    botonOpcion(opcion, numero: i + 1, correcta: p.significado)
                }
            }

            HStack {
                Button("Salir", role: .cancel, action: salir).accessibilityIdentifier("btn-salir")
                Spacer()
                Button("No la sé") { fallar(nil) }.disabled(enPausa).accessibilityIdentifier("btn-nolase")
            }
            .buttonStyle(.bordered)
            .tint(.tintaSuave)
        }
        .onAppear { if !enPausa { cronometro.reanudar() } }
        .onDisappear { cronometro.pausar() }
    }

    private func botonOpcion(_ opcion: String, numero: Int, correcta: String) -> some View {
        let marcada = enPausa && (opcion == correcta || opcion == elegida)
        let color: Color = enPausa && opcion == correcta ? .verde : enPausa && opcion == elegida ? .rojo : .tinta
        return Button { elegir(opcion) } label: {
            Text(opcion)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 16)
                .foregroundStyle(color)
                .background(marcada ? color.opacity(0.12) : Color.papel2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(marcada ? color : Color.linea, lineWidth: 1.5))
        }
        .buttonStyle(EstiloOpcion())
        .disabled(enPausa)
        .keyboardShortcut(KeyEquivalent(Character("\(numero)")), modifiers: [])
        .accessibilityLabel(opcion)
        .accessibilityValue(enPausa ? (opcion == correcta ? "correcta" : opcion == elegida ? "tu elección" : "") : "")
        .accessibilityIdentifier("opcion-\(numero)")
    }

    private struct EstiloOpcion: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }

    // MARK: Resumen

    private func resumen(_ ronda: RondaPreguntas) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("¡Repaso terminado!").font(.largeTitle.bold()).accessibilityIdentifier("resumen-titulo")
            HStack(spacing: 12) {
                cifra("Aciertos", "\(ronda.aciertos)/\(ronda.preguntas.count)", id: "resumen-aciertos")
                cifra("Media", String(format: "%.1f s", Double(ronda.mediaAciertosMs) / 1000), id: "resumen-media")
            }
            Text(mensajeFin).font(.title3).accessibilityIdentifier("resumen-mensaje")
            TutorComentario(inicio: inicioSesion).id(inicioSesion)
            Seccion(numero: "·", titulo: "Errores") {
                if ronda.errores.isEmpty {
                    Text("Sin errores").foregroundStyle(Color.verde)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ronda.errores, id: \.clave) { p in
                            Text("\(p.texto)\(p.lectura.map { " (\($0))" } ?? "") → \(p.significado)")
                                .font(.body).foregroundStyle(Color.rojo)
                                .accessibilityIdentifier("resumen-errores")
                        }
                    }
                }
            }
            Button("Volver") { self.ronda = nil }
                .buttonStyle(.borderedProminent).tint(.verde)
                .accessibilityIdentifier("btn-volver")
        }
    }

    private func cifra(_ titulo: String, _ valor: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo.uppercased()).font(.etiqueta).foregroundStyle(Color.tintaSuave)
            Text(valor).font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjetaFondo()
    }

    // MARK: Acciones

    private func empezar(_ preguntas: [Pregunta]) {
        pausa?.cancel()
        ronda = RondaPreguntas(preguntas.shuffled(), todas: Vocabulario.todas(tipo))
        inicioSesion = .now
        elegida = nil
        enPausa = false
        cronometro.iniciar()
    }

    private func salir() {
        pausa?.cancel()
        ronda = nil
        enPausa = false
    }

    private func registrar(_ p: Pregunta, ok: Bool, ms: Int, respuesta: String?) {
        do {
            try Progreso.registrar([Intento(pregunta: p, correcto: ok, respuesta: respuesta, latenciaMs: ms,
                                            dispositivo: Progreso.dispositivo)], en: contexto)
        } catch {
            errorGuardado = error.localizedDescription
        }
    }

    private func elegir(_ opcion: String) {
        guard let r = ronda, !r.terminada, !enPausa, cronometro.ms() >= Self.toqueMinimoMs else { return }
        if opcion == r.actual.significado { acertar(opcion) } else { fallar(opcion) }
    }

    private func acertar(_ opcion: String) {
        guard var r = ronda else { return }
        let ms = cronometro.ms()
        registrar(r.actual, ok: true, ms: ms, respuesta: opcion)
        r.acertar(ms: ms)
        // Sin animación al pasar al resumen: la última pregunta no queda flotando encima.
        if r.terminada { ronda = r } else { withAnimation(.spring(duration: 0.3)) { ronda = r } }
        cronometro.iniciar()
        if r.terminada { terminar(r) } else { Efectos.compartidos.reproducir(.acierto(combo: r.combo - 1)) }
    }

    /// Opción equivocada, o «No la sé» (`opcion` nil): se marca la correcta un momento y se sigue.
    private func fallar(_ opcion: String?) {
        guard var r = ronda, !enPausa else { return }
        let ms = cronometro.ms()
        cronometro.pausar()
        elegida = opcion
        enPausa = true
        registrar(r.actual, ok: false, ms: ms, respuesta: opcion)
        r.fallar(ms: ms)
        ronda = r
        Efectos.compartidos.reproducir(.error)
        AccessibilityNotification.Announcement("\(r.actual.texto) significa \(r.actual.significado)").post()
        pausa = Task {
            try? await Task.sleep(for: Self.pausaError)
            guard !Task.isCancelled, var actual = ronda else { return }
            actual.siguiente()
            ronda = actual
            enPausa = false
            elegida = nil
            if actual.terminada { return terminar(actual) }
            cronometro.iniciar()
            if !escenaActiva { cronometro.pausar() }
        }
    }

    private func terminar(_ r: RondaPreguntas) {
        mensajeFin = Mensajes.tarjetas(.init(completa: true, aciertos: r.aciertos, total: r.preguntas.count, recordNuevo: false,
                                             mediaMs: r.mediaAciertosMs, recordAnteriorMs: nil, mejorCombo: r.mejorCombo))
        Efectos.compartidos.reproducir(.rondaCompleta)
    }
}

/// Lo que toca hoy en vocabulario o kanji. Vista aparte con su propia consulta: no se recalcula durante el juego.
private struct PlanPalabras: View {
    @Binding var tipo: Pregunta.Tipo
    let empezar: ([Pregunta]) -> Void
    @Query(filter: #Predicate<Intento> { $0.ejercicio == "vocabulario" || $0.ejercicio == "kanji" }) private var intentos: [Intento]

    var body: some View {
        let todas = Vocabulario.todas(tipo)
        let porClave = Dictionary(todas.map { ($0.clave, $0) }) { a, _ in a }
        let pasos = intentos.filter { $0.ejercicio == tipo.rawValue }
            .map { Repaso.Paso(clave: $0.item, fecha: $0.fecha, correcto: $0.correcto, latenciaMs: $0.latenciaMs) }
        let (pendientes, nuevas) = Repaso.planificar(pasos, orden: todas.map(\.clave), nuevasPorDia: Vocabulario.nuevasPorDia[tipo] ?? 0,
                                                     bienMs: Vocabulario.bienMs)
        let sesion = (pendientes + nuevas).compactMap { porClave[$0] }
        let vistas = Set(pasos.map(\.clave)).intersection(porClave.keys).count

        VStack(alignment: .leading, spacing: 24) {
            ResumenRacha()
            Segmentado(opciones: [(Pregunta.Tipo.vocabulario, "Vocabulario"), (.kanji, "Kanji")], seleccion: $tipo,
                       identificador: "palabras-tipo")
            Seccion(numero: "·", titulo: "Hoy") {
                Text("\(pendientes.count) por repasar · \(nuevas.count) nuevas")
                    .font(.headline.monospacedDigit()).accessibilityIdentifier("palabras-plan")
                Text("\(vistas) de \(todas.count) \(tipo == .vocabulario ? "palabras" : "kanji") del N5 vistas")
                    .font(.subheadline).foregroundStyle(Color.tintaSuave).accessibilityIdentifier("palabras-vistas")
                if sesion.isEmpty {
                    Text("Nada pendiente por hoy. Vuelve mañana.").foregroundStyle(Color.tintaSuave)
                        .accessibilityIdentifier("palabras-nada")
                } else {
                    Text(tipo == .vocabulario ? "Ves la palabra y su lectura; eliges su significado entre 4."
                                              : "Ves el kanji; eliges su significado entre 4. Al fallar, ves sus lecturas.")
                        .font(.subheadline).foregroundStyle(Color.tintaSuave)
                    Button { empezar(sesion) } label: {
                        Text("Repasar ahora (\(sesion.count))").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(.verde)
                    .accessibilityIdentifier("btn-repasar-palabras")
                }
            }
        }
    }
}

import SwiftData
import SwiftUI

/// Minijuego de tarjetas (port de tarjetas.html): sale un kana, se escribe su lectura en romaji.
struct TarjetasVista: View {
    @Environment(\.modelContext) private var contexto
    @Environment(Sincronizador.self) private var sincronizador
    @Environment(\.scenePhase) private var fase
    @State private var config = RondaTarjetas.Config()
    @State private var ronda: RondaTarjetas?
    @State private var cronometro = Cronometro()
    /// La opción tocada en la tarjeta actual (para marcarla tras un error, modo de fallo 92).
    @State private var elegida: String?
    @State private var lecturaError: String?
    @State private var recordNuevo = false
    @State private var escenaActiva = true
    @State private var pausa: Task<Void, Never>?
    @State private var errorGuardado: String?
    /// Se sortea una vez al terminar, no en cada redibujado (modo de fallo 74).
    @State private var mensajeFin = ""
    @State private var confeti = 0
    @State private var inicioSesion = Date.now

    /// Pausa tras un error antes de pasar a la siguiente tarjeta (como la web).
    private static let pausaError: Duration = .milliseconds(1200)
    /// Un toque antes de esto, desde que salió la tarjeta, es el segundo de un doble toque.
    private static let toqueMinimoMs = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    // Con la última vida, la lectura correcta se muestra antes del resumen (modo de fallo 35).
                    if let ronda, let resultado = ronda.resultado, lecturaError == nil {
                        resumen(ronda, resultado)
                    } else if let ronda {
                        juego(ronda)
                    } else {
                        configuracion
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .scrollDismissesKeyboard(.never)
            .background(Color.papel)
            .overlay { Confeti(disparo: confeti) }
            .navigationTitle("Tarjetas")
            // Oculta solo mientras se juega (también en la pausa de la última vida); en el resumen vuelve.
            .toolbarVisibility(ronda != nil && (ronda?.resultado == nil || lecturaError != nil) ? .hidden : .automatic,
                               for: .navigationBar)
        }
        .onChange(of: fase) { _, nueva in
            escenaActiva = nueva == .active
            guard enJuego else { return }
            if escenaActiva { cronometro.reanudar() } else { cronometro.pausar() }
        }
        .alert("No se pudo guardar el progreso", isPresented: .constant(errorGuardado != nil)) {
            Button("Entendido") { errorGuardado = nil }
        } message: {
            Text(errorGuardado ?? "")
        }
    }

    // MARK: Configuración

    private var configuracion: some View {
        VStack(alignment: .leading, spacing: 16) {
            ResumenRacha()
            RepasoHoy(empezar: empezarRepaso)
            RondaLibre(config: $config, empezar: empezar)
        }
    }

    // MARK: Juego

    private func juego(_ ronda: RondaTarjetas) -> some View {
        let enPausa = lecturaError != nil
        return VStack(spacing: 18) {
            BarraJuego(indice: ronda.indice, total: ronda.tarjetas.count, combo: ronda.combo, salir: salir)

            VStack(spacing: 6) {
                HStack {
                    Text(ronda.repaso ? "Repaso · \(ronda.actual.silabario.nombre.lowercased())" : ronda.actual.silabario.nombre.lowercased())
                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.tintaSuave)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 0.1)) { contexto in
                        Text(segundos(cronometro.ms(contexto.date))).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Color.tintaSuave)
                    }
                    .accessibilityIdentifier("cronometro")
                }
                Spacer(minLength: 8)
                Text(ronda.actual.kana)
                    .font(.kana(150))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color.tinta)
                    .accessibilityIdentifier("tarjeta-kana")
                ZStack {
                    Text("¿Cómo se lee?").font(.body.weight(.medium)).foregroundStyle(Color.tintaSuave)
                        .opacity(enPausa ? 0 : 1)
                        .accessibilityHidden(true)
                    Text(lecturaError ?? " ")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.rojo)
                        .accessibilityIdentifier("tarjeta-feedback")
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .bloque(relleno: 18, radio: 30)
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.rojo, lineWidth: 2).opacity(enPausa ? 1 : 0))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(ronda.opciones.enumerated()), id: \.element) { i, opcion in
                    BotonOpcion(texto: opcion, numero: i + 1,
                                marca: !enPausa ? .ninguna : opcion == ronda.actual.romaji ? .correcta : opcion == elegida ? .elegida : .ninguna,
                                enPausa: enPausa, monoespaciada: true) { elegir(opcion) }
                }
            }
            // Identidad por tarjeta: una opción que se repite en la siguiente no se desliza a su casilla nueva.
            .id(ronda.indice)

            HStack {
                if ronda.repaso {
                    Text("Repaso · sin vidas").font(.subheadline.weight(.bold)).foregroundStyle(Color.tintaSuave)
                        .accessibilityIdentifier("modo-repaso")
                } else {
                    HStack(spacing: 4) {
                        ForEach(0 ..< RondaTarjetas.vidasIniciales, id: \.self) { i in
                            Image(systemName: i < ronda.vidas ? "heart.fill" : "heart")
                        }
                    }
                    .foregroundStyle(Color.rojo)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Vidas: \(ronda.vidas) de 3")
                    .accessibilityIdentifier("vidas")
                }
                Spacer()
                Button("No la sé") { fallar(nil) }
                    .buttonStyle(EstiloSecundario())
                    .disabled(enPausa)
                    .accessibilityIdentifier("btn-nolase")
            }
            .padding(.horizontal, 4)
        }
        .onAppear { if enJuego { cronometro.reanudar() } }
        // Otra pestaña a mitad de ronda: el tiempo fuera no cuenta como latencia.
        .onDisappear { cronometro.pausar() }
    }

    // MARK: Resumen

    private func resumen(_ ronda: RondaTarjetas, _ resultado: RondaTarjetas.Resultado) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(ronda.repaso ? "¡Repaso terminado!" : resultado == .completa ? "¡Ronda completada!" : "Sin vidas")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("resumen-titulo")
            HStack(spacing: 12) {
                cifra("Aciertos", "\(ronda.aciertos)/\(ronda.tarjetas.count)", id: "resumen-aciertos")
                cifra("Tiempo", segundos(ronda.tiempoTotalMs), id: "resumen-tiempo")
                cifra("Media", segundos(ronda.mediaAciertosMs), id: "resumen-media")
            }
            Text(mensajeFin)
                .font(.title3)
                .accessibilityIdentifier("resumen-mensaje")
            if !ronda.repaso {
                Text(textoRecord(ronda, resultado))
                    .foregroundStyle(recordNuevo ? Color.verde : Color.tintaSuave)
                    .accessibilityIdentifier("resumen-record")
            }
            TutorComentario(inicio: inicioSesion).id(inicioSesion)
            Seccion(numero: "·", titulo: "Más lentas") {
                FlujoLayout {
                    ForEach(Array(ronda.masLentas.enumerated()), id: \.offset) { _, r in
                        chip("\(r.tarjeta.kana) · \(segundos(r.ms))", color: .tinta)
                    }
                }
            }
            Seccion(numero: "·", titulo: "Errores") {
                if ronda.errores.isEmpty {
                    Text("Sin errores").foregroundStyle(Color.verde)
                } else {
                    FlujoLayout {
                        ForEach(Array(ronda.errores.enumerated()), id: \.offset) { _, t in
                            chip("\(t.kana) → \(t.romaji)", color: .rojo)
                        }
                    }
                    .accessibilityIdentifier("resumen-errores")
                }
            }
            HStack {
                if ronda.repaso {
                    // Al volver, «Hoy» se recalcula con lo recién respondido (modo de fallo 83).
                    Button("Volver") { self.ronda = nil }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("btn-volver")
                } else {
                    Button("Cambiar configuración") { self.ronda = nil }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Otra ronda", action: empezar)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("btn-otra")
                }
            }
            .tint(.verde)
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

    private func chip(_ texto: String, color: Color) -> some View {
        Text(texto)
            .font(.kana(17, relativeTo: .body))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.papel2, in: Capsule())
    }

    private func textoRecord(_ ronda: RondaTarjetas, _ resultado: RondaTarjetas.Resultado) -> String {
        if recordNuevo { return "¡Nuevo récord! \(segundos(ronda.mediaAciertosMs)) por tarjeta" }
        if let anterior = Progreso.record(ronda.config.claveRecord) {
            return "Récord: \(segundos(anterior)) por tarjeta"
        }
        return resultado == .completa ? "" : "Completa la ronda para registrar un récord."
    }

    // MARK: Acciones

    /// Hay una tarjeta esperando respuesta (ni pausa tras un error ni ronda terminada).
    private var enJuego: Bool { ronda != nil && ronda?.resultado == nil && lecturaError == nil }

    private func salir() {
        pausa?.cancel()
        ronda = nil
        lecturaError = nil
    }

    private func empezar() { arrancar(RondaTarjetas(config: ronda?.config ?? config)) }

    private func empezarRepaso(_ tarjetas: [Tarjeta]) { arrancar(RondaTarjetas(repaso: tarjetas.shuffled())) }

    private func arrancar(_ nueva: RondaTarjetas) {
        pausa?.cancel()
        ronda = nueva
        inicioSesion = .now
        recordNuevo = false
        lecturaError = nil
        elegida = nil
        cronometro.iniciar()
    }

    private func registrar(_ tarjeta: Tarjeta, ok: Bool, ms: Int, respuesta: String?) {
        do {
            try Progreso.registrar([Intento(ejercicio: "tarjeta", item: tarjeta.kana, silabario: tarjeta.silabario,
                                            correcto: ok, respuesta: respuesta,
                                            latenciaMs: ms, dispositivo: Progreso.dispositivo)], en: contexto)
        } catch {
            errorGuardado = error.localizedDescription
        }
    }

    /// Toque en una opción. Uno muy seguido del anterior (doble toque) se ignora (modo de fallo 91).
    private func elegir(_ opcion: String) {
        guard let r = ronda, r.resultado == nil, lecturaError == nil, cronometro.ms() >= Self.toqueMinimoMs else { return }
        if opcion == r.actual.romaji { acertar(opcion) } else { fallar(opcion) }
    }

    private func acertar(_ opcion: String) {
        guard var r = ronda else { return }
        let ms = cronometro.ms()
        registrar(r.actual, ok: true, ms: ms, respuesta: opcion)
        r.acertar(ms: ms)
        withAnimation(.spring(duration: 0.3)) { ronda = r }
        if r.resultado == nil { Efectos.compartidos.reproducir(.acierto(combo: r.combo - 1)) }
        cronometro.iniciar()
        if r.resultado == .completa { terminar(r) }
    }

    /// Opción equivocada, o «No la sé» (`opcion` nil).
    private func fallar(_ opcion: String?) {
        guard var r = ronda, lecturaError == nil else { return }
        let ms = cronometro.ms()
        cronometro.pausar()
        elegida = opcion
        registrar(r.actual, ok: false, ms: ms, respuesta: opcion)
        r.fallar(ms: ms)
        ronda = r
        Efectos.compartidos.reproducir(r.vidas == 0 ? .sinVidas : .error)
        lecturaError = "\(r.actual.kana) se lee \(r.actual.romaji)"
        AccessibilityNotification.Announcement(lecturaError!).post()
        pausa = Task {
            try? await Task.sleep(for: Self.pausaError)
            // Salir o empezar otra ronda durante la pausa la cancela: no debe tocar la ronda nueva.
            guard !Task.isCancelled, var actual = ronda else { return }
            actual.siguiente()
            ronda = actual
            lecturaError = nil
            elegida = nil
            if actual.resultado != nil { return terminar(actual) }
            cronometro.iniciar()
            // La pausa pudo terminar con la app ya en segundo plano (modo de fallo 56).
            if !escenaActiva { cronometro.pausar() }
        }
    }

    private func terminar(_ r: RondaTarjetas) {
        let completa = r.resultado == .completa
        // El récord anterior se lee antes de guardar el nuevo (modo de fallo 74).
        let anterior = r.repaso ? nil : Progreso.record(r.config.claveRecord)
        if completa, !r.repaso { recordNuevo = Progreso.guardarRecord(r.config.claveRecord, r.mediaAciertosMs) }
        mensajeFin = Mensajes.tarjetas(.init(completa: completa, aciertos: r.aciertos, total: r.tarjetas.count,
                                             recordNuevo: recordNuevo, mediaMs: r.mediaAciertosMs,
                                             recordAnteriorMs: anterior, mejorCombo: r.mejorCombo))
        if completa {
            Efectos.compartidos.reproducir(recordNuevo ? .record : .rondaCompleta)
            if recordNuevo || r.aciertos == r.tarjetas.count { confeti += 1 }
        }
    }
}

/// Ronda libre: silabario en bloques (あ, ア, あア), mazo, tamaño y «Empezar». Vista propia: elegir opciones no
/// redibuja el resto de la pantalla.
private struct RondaLibre: View {
    @Binding var config: RondaTarjetas.Config
    let empezar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RONDA LIBRE").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Color.tintaSuave)
                .padding(.top, 10).padding(.leading, 4)
            HStack(spacing: 10) {
                ForEach(RondaTarjetas.OpcionSilabario.allCases) { s in
                    BloqueSilabario(muestra: s == .hiragana ? "あ" : s == .katakana ? "ア" : "あア", nombre: s.nombre,
                                    elegido: config.silabario == s) { config.silabario = s }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Segmentado(opciones: [(Kana.Mazo.basicos, "Básicos"), (.todos, "Todos")],
                           seleccion: $config.mazo, identificador: "config-mazo")
                let total = RondaTarjetas.mazo(config.silabario, config.mazo).count
                Segmentado(opciones: RondaTarjetas.Tamano.allCases.map { ($0, $0 == .completo ? "Todas (\(total))" : $0.rawValue) },
                           seleccion: $config.tamano, identificador: "config-tamano")
                Text("Eliges la lectura entre 4. Tienes 3 vidas.").font(.subheadline).foregroundStyle(Color.tintaSuave)
                Button("Empezar", action: empezar)
                    .buttonStyle(EstiloPrincipal())
                    .accessibilityIdentifier("btn-empezar")
            }
            .bloque()
        }
    }
}

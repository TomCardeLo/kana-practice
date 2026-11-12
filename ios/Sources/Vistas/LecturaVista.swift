import SwiftData
import SwiftUI

/// Banco de palabras de la web (`src/words.js`, incluido tal cual en la app para que no se desincronice).
enum Palabras {
    struct Entrada { let texto: String; let filas: Set<String> }

    static let banco: [Entrada] = {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("Falta words.js en el bundle (ver project.yml)") }
        let regex = try! NSRegularExpression(pattern: "'([^']+)'")
        return regex.matches(in: js, range: NSRange(js.startIndex..., in: js)).compactMap { m in
            let texto = String(js[Range(m.range(at: 1), in: js)!])
            guard let silabas = Translit.silabas(texto).first, !silabas.isEmpty else { return nil }
            return Entrada(texto: texto, filas: Set(silabas.map(Kana.fila(de:))))
        }
    }()
}

/// Práctica de lectura (port de index.html): se transcribe a romaji un kana generado desde español.
struct LecturaVista: View {
    private enum Modo: String { case azar, texto }

    private struct Practica {
        var palabras: [[Unidad]]
        var espanol: [String]?
        var fuente: String?
    }

    @Environment(\.modelContext) private var contexto
    @Environment(\.horizontalSizeClass) private var anchura
    @State private var modo = Modo.azar
    @State private var silabario = Silabario.hiragana
    @State private var filasActivas = Set(Kana.filas.map(\.id))
    @State private var textoPropio = ""
    @State private var practica: Practica?
    @State private var respuesta = ""
    @State private var correccion: Correccion?
    @State private var registrada = false
    @State private var solucionVisible = false
    @State private var mensaje: String?
    @State private var verFiltro = false
    @FocusState private var tecladoAbierto: Bool

    private static let palabrasPorRonda = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    controles
                    if anchura == .regular {
                        HStack(alignment: .top, spacing: 28) {
                            salidaKana.frame(maxWidth: .infinity)
                            panelRespuesta.frame(maxWidth: .infinity)
                        }
                    } else {
                        salidaKana
                        panelRespuesta
                    }
                }
                .padding(20)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color.papel)
            .navigationTitle("Leer")
            .onChange(of: silabario) { reconstruir() }
            .onChange(of: filasActivas) { if correccion != nil { corregir(recalculo: true) } }
            .onChange(of: modo) { _, nuevo in
                // Como la web: cambiar de modo descarta la práctica y su corrección.
                descartar()
                if nuevo == .azar { nuevaRonda() }
            }
            // Los campos son de varias líneas (Return añade un salto): sin esto el teclado no se cierra y
            // tapa las pestañas en el iPhone.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { tecladoAbierto = false }.accessibilityIdentifier("btn-teclado-listo")
                }
            }
            .onAppear { if practica == nil, modo == .azar { nuevaRonda() } }
        }
    }

    // MARK: Controles

    private var controles: some View {
        VStack(alignment: .leading, spacing: 20) {
            Seccion(numero: "01", titulo: "Modo") {
                Segmentado(opciones: [(Modo.azar, "Palabras al azar"), (.texto, "Texto propio")],
                           seleccion: $modo, identificador: "lectura-modo")
                if modo == .azar {
                    Button("Nueva ronda", action: nuevaRonda)
                        .buttonStyle(.borderedProminent).tint(.verde)
                        .accessibilityIdentifier("btn-nueva-ronda")
                } else {
                    TextField("Escribe o pega un texto en español", text: $textoPropio, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .padding(12)
                        .background(Color.papel2, in: RoundedRectangle(cornerRadius: 12))
                        .focused($tecladoAbierto)
                        .accessibilityIdentifier("lectura-texto")
                    Button("Generar", action: generarTexto)
                        .buttonStyle(.borderedProminent).tint(.verde)
                        .accessibilityIdentifier("btn-generar")
                }
            }
            Seccion(numero: "02", titulo: "Silabario") {
                Segmentado(opciones: Silabario.allCases.map { ($0, $0.nombre) }, seleccion: $silabario,
                           identificador: "lectura-silabario")
                DisclosureGroup(isExpanded: $verFiltro) {
                    FlujoLayout(espacio: 6, espacioFila: 6) {
                        ForEach(Kana.filas) { fila in chipFila(fila) }
                    }
                    .padding(.top, 8)
                } label: {
                    // El identificador va en la etiqueta: puesto en el DisclosureGroup tapaba el de cada chip.
                    Text("Filas: \(filasActivas.count) de \(Kana.filas.count)")
                        .font(.subheadline).foregroundStyle(Color.tintaSuave)
                        .accessibilityIdentifier("lectura-filtro")
                }
            }
            if let mensaje {
                Text(mensaje).foregroundStyle(Color.rojo).accessibilityIdentifier("lectura-mensaje")
            }
        }
    }

    private func chipFila(_ fila: Fila) -> some View {
        let activa = filasActivas.contains(fila.id)
        return Button {
            if activa { filasActivas.remove(fila.id) } else { filasActivas.insert(fila.id) }
        } label: {
            VStack(spacing: 0) {
                Text(Kana.ejemplo(fila: fila.id, silabario)).font(.kana(18, relativeTo: .body))
                Text(fila.label).font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(activa ? Color.papel : Color.tintaSuave)
            .background(activa ? Color.verde : Color.papel2, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activa ? .isSelected : [])
        .accessibilityIdentifier("fila-\(fila.id)")
    }

    // MARK: Kana

    private var salidaKana: some View {
        Seccion(numero: "03", titulo: "Transcribe") {
            if let practica {
                let actual = indiceActual
                let indices = indicesActivos(practica)
                let plano = correccion.map { Array($0.words.joined()) }
                FlujoLayout(espacio: 18, espacioFila: 16) {
                    ForEach(Array(practica.palabras.enumerated()), id: \.offset) { i, palabra in
                        VStack(alignment: .leading, spacing: 4) {
                            // Las palabras largas también se parten en varias líneas (modo de fallo 55).
                            FlujoLayout(espacio: 2, espacioFila: 6) {
                                ForEach(Array(palabra.enumerated()), id: \.offset) { j, unidad in
                                    let indice = indices[i][j]
                                    celda(unidad, resultado: indice.flatMap { plano?[safe: $0] },
                                          activa: indice != nil, actual: indice != nil && indice == actual)
                                }
                            }
                            if correccion != nil || solucionVisible, let es = practica.espanol?[safe: i] {
                                Text(es).font(.caption).foregroundStyle(Color.tintaSuave)
                                    .accessibilityIdentifier("lectura-espanol")
                            }
                        }
                    }
                }
                .tarjetaFondo()
            } else {
                Text("Genera una práctica para empezar.").foregroundStyle(Color.tintaSuave)
            }
        }
    }

    /// Posición de cada unidad entre las activas (nil si su fila está filtrada).
    private func indicesActivos(_ p: Practica) -> [[Int?]] {
        var cursor = 0
        return p.palabras.map { palabra in
            palabra.map { unidad in
                guard filasActivas.contains(unidad.row) else { return nil }
                defer { cursor += 1 }
                return cursor
            }
        }
    }

    /// Índice (entre las unidades activas) de la que el usuario está escribiendo ahora.
    private var indiceActual: Int? {
        guard correccion == nil, !solucionVisible, !respuesta.isEmpty else { return nil }
        return Check.unidadesEscritas(respuesta)
    }

    private func celda(_ unidad: Unidad, resultado: UnidadCorregida?, activa: Bool, actual: Bool) -> some View {
        let estado = !activa ? "dimmed" : resultado.map { $0.ok ? "ok" : "error" } ?? "pending"
        let fondo: Color = estado == "ok" ? .verdeFondo : estado == "error" ? .rojoFondo : .clear
        return VStack(spacing: 2) {
            Text(unidad.kana)
                .font(.kana(anchura == .regular ? 40 : 32))
                .foregroundStyle(activa ? Color.tinta : Color.linea)
            if activa, solucionVisible || resultado != nil {
                Text(unidad.romaji).font(.caption.monospaced()).foregroundStyle(Color.tintaSuave)
            }
            if let resultado, !resultado.ok {
                Text(resultado.typed.map { "escribiste: \($0)" } ?? "falta")
                    .font(.caption2).foregroundStyle(Color.rojo)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(fondo, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) {
            if actual { Rectangle().fill(Color.verde).frame(height: 3) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("celda-\(estado)")
    }

    // MARK: Respuesta

    private var panelRespuesta: some View {
        Seccion(numero: "04", titulo: "Tu respuesta") {
            TextField("Escribe la lectura en romaji", text: $respuesta, axis: .vertical)
                .campoRomaji()
                .font(.system(.title3, design: .monospaced))
                .lineLimit(3 ... 10)
                .padding(12)
                .background(Color.papel2, in: RoundedRectangle(cornerRadius: 12))
                .focused($tecladoAbierto)
                .accessibilityIdentifier("lectura-respuesta")
            HStack {
                Button("Corregir") { corregir() }
                    .buttonStyle(.borderedProminent).tint(.verde)
                    .accessibilityIdentifier("btn-corregir")
                Button("Mostrar solución") { solucionVisible = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("btn-solucion")
            }
            if let correccion {
                Text(marcador(correccion))
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("lectura-marcador")
            }
        }
    }

    private func marcador(_ c: Correccion) -> String {
        let sobrantes = c.extra > 0 ? " · \(c.extra) sobrantes" : ""
        let nota = solucionVisible && !registrada ? " (no cuenta en estadísticas)" : ""
        return "\(c.correct) / \(c.total) correctos\(sobrantes)\(nota)"
    }

    // MARK: Acciones

    private func nuevaRonda() {
        guard !filasActivas.isEmpty else { return avisar("Selecciona al menos una fila del silabario.") }
        let candidatas = Palabras.banco.filter { $0.filas.isSubset(of: filasActivas) }
        guard !candidatas.isEmpty else { return avisar("Ninguna palabra usa solo las filas elegidas.") }
        let elegidas = candidatas.shuffled().prefix(Self.palabrasPorRonda).map(\.texto)
        empezar(Practica(palabras: unidades(elegidas.joined(separator: " ")), espanol: elegidas))
    }

    private func generarTexto() {
        guard !filasActivas.isEmpty else { return avisar("Selecciona al menos una fila del silabario.") }
        let palabras = unidades(textoPropio)
        guard !palabras.isEmpty else { return avisar("Escribe un texto en español para generar la práctica.") }
        guard palabras.joined().contains(where: { filasActivas.contains($0.row) }) else {
            return avisar("Ningún kana del texto está en las filas elegidas.")
        }
        empezar(Practica(palabras: palabras, fuente: textoPropio))
    }

    private func unidades(_ texto: String) -> [[Unidad]] {
        Kana.unidades(Translit.silabas(texto), silabario)
    }

    private func avisar(_ texto: String) { mensaje = texto }

    private func empezar(_ nueva: Practica) {
        descartar()
        practica = nueva
    }

    private func descartar() {
        mensaje = nil
        practica = nil
        respuesta = ""
        correccion = nil
        registrada = false
        solucionVisible = false
    }

    /// Cambio de silabario: mismo texto, kana nuevo; se conserva la respuesta y se recorrige si hacía falta.
    private func reconstruir() {
        guard let p = practica else { return }
        let fuente = p.espanol?.joined(separator: " ") ?? p.fuente ?? ""
        practica = Practica(palabras: unidades(fuente), espanol: p.espanol, fuente: p.fuente)
        if correccion != nil { corregir(recalculo: true) }
    }

    /// Registra intentos solo la primera vez y nunca tras ver la solución (modos de fallo 49 y 50).
    /// `recalculo`: cambio de filtro o de silabario después de corregir; si la respuesta quedó vacía,
    /// se deja la corrección anterior sin avisar (como `runCheck` en la web).
    private func corregir(recalculo: Bool = false) {
        guard let practica else { return avisar("Primero genera una práctica.") }
        let esperadas = practica.palabras.map { $0.filter { filasActivas.contains($0.row) } }
        guard let resultado = Check.corregir(esperadas, respuesta) else {
            if !recalculo { avisar("Escribe tu transcripción antes de corregir.") }
            return
        }
        mensaje = nil
        correccion = resultado
        if !registrada, !solucionVisible {
            registrada = true
            do {
                try Progreso.registrar(resultado.words.joined().map {
                    Intento(ejercicio: "lectura", item: $0.kana, silabario: silabario, correcto: $0.ok,
                            respuesta: $0.typed, latenciaMs: nil, dispositivo: Progreso.dispositivo)
                }, en: contexto)
            } catch {
                avisar("No se pudo guardar el progreso: \(error.localizedDescription)")
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

import PencilKit
import SwiftData
import SwiftUI

/// Escribir a mano: sale un kana en romaji, se escribe en la cuadrícula (dedo o Apple Pencil) y se revisa trazo a trazo
/// contra su plantilla de KanjiVG: número, orden, dirección y forma de cada trazo (modos de fallo 113–123).
/// Cada revisión es un intento «escritura»: cuenta para la racha y la meta, no para el repaso ni los hitos (119).
struct EscribirVista: View {
    @Environment(\.modelContext) private var contexto
    @State private var silabario = Silabario.hiragana
    @State private var cola: [Tarjeta] = []
    @State private var actual: Tarjeta?
    @State private var dibujo = PKDrawing()
    @State private var veredicto: Trazos.Veredicto?
    @State private var inicio = Date.now
    @State private var errorGuardado: String?

    /// Sin plantillas no se puede revisar nada: se dice en pantalla, no se finge (sin fallbacks silenciosos).
    private static let plantillas: Result<[String: [Trazos.Trazo]], Error> = Result {
        guard let url = Bundle.main.url(forResource: "trazos-kana", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Trazos.cargar(Data(contentsOf: url))
    }

    var body: some View {
        NavigationStack {
            // Sin ScrollView: un desplazamiento le robaría el trazo al lienzo (modo de fallo 121).
            VStack(spacing: 16) {
                Segmentado(opciones: Silabario.allCases.map { ($0, $0.nombre) }, seleccion: $silabario,
                           identificador: "escribir-silabario")
                switch Self.plantillas {
                case let .failure(error):
                    Text("No se pudieron cargar las plantillas de trazos: \(error.localizedDescription)")
                        .foregroundStyle(Color.rojo).accessibilityIdentifier("escribir-error")
                    Spacer()
                case let .success(plantillas):
                    if let actual, let plantilla = plantillas[actual.kana] {
                        ejercicio(actual, plantilla)
                    } else if let actual {
                        Text("Falta la plantilla de \(actual.kana).").foregroundStyle(Color.rojo)  // 118
                        Button("Siguiente") { siguiente() }.buttonStyle(EstiloPrincipal())
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color.papel)
            .navigationTitle("Escribir")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { if actual == nil { arrancar() } }
        // Solo si cambió de verdad respecto del kana en pantalla: al fijar el primero (E2E) no se sortea otro.
        .onChange(of: silabario) { _, nuevo in
            guard actual?.silabario != nuevo else { return }
            cola = []
            siguiente()
        }
        .alert("No se pudo guardar el progreso", isPresented: .constant(errorGuardado != nil)) {
            Button("Entendido") { errorGuardado = nil }
        } message: {
            Text(errorGuardado ?? "")
        }
    }

    private func ejercicio(_ tarjeta: Tarjeta, _ plantilla: [Trazos.Trazo]) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("Escribe").font(.subheadline.weight(.bold)).foregroundStyle(Color.tintaSuave)
                Text(tarjeta.romaji).font(.system(size: 44, weight: .black, design: .monospaced))
                Text(tarjeta.silabario.nombre.lowercased()).font(.subheadline.weight(.bold)).foregroundStyle(Color.tintaSuave)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("escribir-consigna")

            ZStack {
                Cuadricula()
                if let veredicto {
                    Modelo(plantilla: plantilla, fallo: veredicto.trazoFallido)
                }
                LienzoKana(dibujo: $dibujo, activo: veredicto == nil)
            }
            .aspectRatio(1, contentMode: .fit)
            .bloque(relleno: 0)

            // Espacio fijo para el resultado: si la cuadrícula se achicara al revisar, la tinta (en puntos absolutos)
            // quedaría corrida respecto del modelo.
            Group {
                if let veredicto { resultado(veredicto, tarjeta) } else { Color.clear }
            }
            .frame(height: Self.altoResultado)
            botones(plantilla)
        }
    }

    private static let altoResultado: CGFloat = 72

    private func resultado(_ v: Trazos.Veredicto, _ tarjeta: Tarjeta) -> some View {
        HStack(spacing: 12) {
            Text(tarjeta.kana).font(.kana(40))
            Text(v.mensaje(tarjeta.kana)).font(.headline).lineLimit(2).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: v == .bien ? "checkmark" : "xmark").font(.headline.weight(.heavy)).accessibilityHidden(true)
        }
        .foregroundStyle(v == .bien ? Color.verdeTinta : Color.rojo)
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(v == .bien ? Color.verdeFondo : Color.rojoFondo, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(v == .bien ? "correcto" : "incorrecto")
        .accessibilityIdentifier("escribir-resultado")
    }

    @ViewBuilder
    private func botones(_ plantilla: [Trazos.Trazo]) -> some View {
        if let veredicto {
            HStack(spacing: 12) {
                if veredicto != .bien {
                    Button("Reintentar") { limpiar() }.buttonStyle(EstiloSecundario())
                        .accessibilityIdentifier("btn-reintentar")
                }
                Button("Siguiente") { siguiente() }.buttonStyle(EstiloPrincipal())
                    .accessibilityIdentifier("btn-siguiente")
            }
        } else {
            HStack(spacing: 12) {
                // Solo icono: con texto, «Deshacer» se partía en dos líneas en el iPhone.
                Button("Deshacer", systemImage: "arrow.uturn.backward") { dibujo.strokes.removeLast() }
                    .labelStyle(.iconOnly).buttonStyle(EstiloSecundario()).accessibilityIdentifier("btn-deshacer")
                Button("Borrar", systemImage: "trash") { dibujo = PKDrawing() }
                    .labelStyle(.iconOnly).buttonStyle(EstiloSecundario()).accessibilityIdentifier("btn-borrar")
                // Sin nada dibujado no hay nada que revisar ni que registrar (modo de fallo 117).
                Button("Comprobar") { comprobar(plantilla) }.buttonStyle(EstiloPrincipal())
                    .accessibilityIdentifier("btn-comprobar")
            }
            .disabled(dibujo.strokes.isEmpty)
        }
    }

    // MARK: Lógica

    private func arrancar() {
        // E2E: `-uitest-escribir エ` fija el primer kana.
        let argumentos = ProcessInfo.processInfo.arguments
        if let i = argumentos.firstIndex(of: "-uitest-escribir"), i + 1 < argumentos.count,
           let fijo = Silabario.allCases.flatMap(Self.mazo).first(where: { $0.kana == argumentos[i + 1] }) {
            silabario = fijo.silabario
            mostrar(fijo)
        } else {
            siguiente()
        }
    }

    /// Kana sueltos (básicos y con dakuten): las combinaciones como きゃ no se escriben aquí.
    private static func mazo(_ s: Silabario) -> [Tarjeta] { Kana.mazo(s, .todos).filter { $0.kana.count == 1 } }

    private func siguiente() {
        if cola.isEmpty { cola = Self.mazo(silabario).shuffled() }
        mostrar(cola.removeLast())
    }

    private func mostrar(_ tarjeta: Tarjeta) {
        actual = tarjeta
        limpiar()
    }

    private func limpiar() {
        dibujo = PKDrawing()
        veredicto = nil
        inicio = .now
    }

    private func comprobar(_ plantilla: [Trazos.Trazo]) {
        guard let actual, veredicto == nil, !dibujo.strokes.isEmpty else { return }
        let trazos = dibujo.strokes.map { s in
            s.path.interpolatedPoints(by: .distance(2)).map {
                let p = $0.location.applying(s.transform)
                return Trazos.Punto(Double(p.x), Double(p.y))
            }
        }
        let v = Trazos.revisar(trazos, contra: plantilla)
        withAnimation(.easeOut(duration: 0.2)) { veredicto = v }
        Efectos.compartidos.reproducir(v == .bien ? .acierto(combo: 0) : .error)
        do {
            try Progreso.registrar([Intento(ejercicio: "escritura", item: actual.kana, silabario: actual.silabario,
                                            correcto: v == .bien, respuesta: v.codigo,
                                            latenciaMs: Int(Date.now.timeIntervalSince(inicio) * 1000),
                                            dispositivo: Progreso.dispositivo)], en: contexto)
        } catch {
            errorGuardado = error.localizedDescription
        }
    }
}

extension Trazos.Veredicto {
    var trazoFallido: Int? {
        switch self {
        case .bien, .cantidad: nil
        case let .orden(n), let .alReves(n), let .forma(n): n
        }
    }

    func mensaje(_ kana: String) -> String {
        switch self {
        case .bien: "¡Bien escrito!"
        case let .cantidad(esperados, dibujados):
            "\(kana) lleva \(esperados) \(esperados == 1 ? "trazo" : "trazos"); dibujaste \(dibujados)."
        case let .orden(n): "El trazo \(n) va en otro orden."
        case let .alReves(n): "El trazo \(n) va en la otra dirección."
        case let .forma(n): "El trazo \(n) no tiene la forma correcta."
        }
    }

    /// Lo que se guarda como respuesta del intento (el tutor de Deepy ve qué falló).
    var codigo: String? {
        switch self {
        case .bien: nil
        case let .cantidad(esperados, dibujados): "\(dibujados) de \(esperados) trazos"
        case let .orden(n): "trazo \(n): orden"
        case let .alReves(n): "trazo \(n): dirección"
        case let .forma(n): "trazo \(n): forma"
        }
    }
}

/// Cuadrícula de práctica: cruz punteada al centro, como el papel de 練習.
private struct Cuadricula: View {
    var body: some View {
        Canvas { ctx, size in
            var cruz = Path()
            cruz.move(to: CGPoint(x: size.width / 2, y: 0)); cruz.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            cruz.move(to: CGPoint(x: 0, y: size.height / 2)); cruz.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(cruz, with: .color(.linea), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        }
        .accessibilityHidden(true)
    }
}

/// El kana correcto sobre la cuadrícula tras revisar: trazos numerados en orden y el que falló en rojo.
private struct Modelo: View {
    let plantilla: [Trazos.Trazo]
    let fallo: Int?
    /// Lado del recuadro de KanjiVG.
    private static let lado = 109.0

    var body: some View {
        GeometryReader { geo in
            let f = geo.size.width / Self.lado
            ZStack(alignment: .topLeading) {
                ForEach(plantilla.indices, id: \.self) { i in
                    let puntos = plantilla[i].map { CGPoint(x: $0.x * f, y: $0.y * f) }
                    Path { $0.addLines(puntos) }
                        .stroke(i + 1 == fallo ? Color.rojo.opacity(0.7) : Color.verde.opacity(0.3),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    if let p = puntos.first {
                        Text("\(i + 1)").font(.caption.weight(.black)).foregroundStyle(Color.papel)
                            .frame(width: 22, height: 22)
                            .background(i + 1 == fallo ? Color.rojo : Color.verde, in: Circle())
                            .position(p)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Lienzo de PencilKit: dedo o Apple Pencil (modo de fallo 121), sin desplazamiento ni regla.
private struct LienzoKana: UIViewRepresentable {
    @Binding var dibujo: PKDrawing
    let activo: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let lienzo = PKCanvasView()
        lienzo.drawingPolicy = .anyInput
        // Color de tinta en claro: PencilKit lo invierte solo en modo oscuro.
        lienzo.tool = PKInkingTool(.pen, color: UIColor(red: 0x0E / 255, green: 0x1C / 255, blue: 0x32 / 255, alpha: 1),
                                   width: 12)
        lienzo.backgroundColor = .clear
        lienzo.isOpaque = false
        lienzo.isScrollEnabled = false
        lienzo.delegate = context.coordinator
        lienzo.accessibilityIdentifier = "escribir-lienzo"
        return lienzo
    }

    func updateUIView(_ lienzo: PKCanvasView, context _: Context) {
        if lienzo.drawing != dibujo { lienzo.drawing = dibujo }
        lienzo.isUserInteractionEnabled = activo
    }

    func makeCoordinator() -> Coordinador { Coordinador(dibujo: $dibujo) }

    final class Coordinador: NSObject, PKCanvasViewDelegate {
        let dibujo: Binding<PKDrawing>
        init(dibujo: Binding<PKDrawing>) { self.dibujo = dibujo }
        func canvasViewDrawingDidChange(_ lienzo: PKCanvasView) {
            if dibujo.wrappedValue != lienzo.drawing { dibujo.wrappedValue = lienzo.drawing }
        }
    }
}

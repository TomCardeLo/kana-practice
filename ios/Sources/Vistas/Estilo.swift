import SwiftUI

/// Tokens de la web (style.css, sistema de 2DATO) con su variante oscura.
extension Color {
    init(claro: UInt32, oscuro: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(oscuro) : ui(claro) })
    }

    static let papel = Color(claro: 0xFAFAF7, oscuro: 0x0B1626)
    static let papel2 = Color(claro: 0xF3F1EA, oscuro: 0x14233A)
    static let tinta = Color(claro: 0x0E1C32, oscuro: 0xF3F1EA)
    static let tintaSuave = Color(claro: 0x5E6B7A, oscuro: 0xA3ABB5)
    static let linea = Color(claro: 0xE2E5E9, oscuro: 0x2A3A55)
    static let verde = Color(claro: 0x057A56, oscuro: 0x44BF9A)
    static let verdeFondo = Color(claro: 0xDDF2EA, oscuro: 0x0F3A30)
    /// Texto sobre verdeFondo (4,5:1 en los dos temas).
    static let verdeTinta = Color(claro: 0x04563D, oscuro: 0x8FE0C2)
    /// Superficie elevada de los bloques (dirección «Matcha»).
    static let superficie = Color(claro: 0xFFFFFF, oscuro: 0x14233A)
    /// Fondo de fichas, pistas de progreso y anillos.
    static let chip = Color(claro: 0xEEF1F4, oscuro: 0x22324D)
    static let sombra = Color(claro: 0x0E1C32, oscuro: 0x000000).opacity(0.10)
    static let rojo = Color(claro: 0xB42318, oscuro: 0xF97066)
    static let rojoFondo = Color(claro: 0xFBE4E1, oscuro: 0x4A1A16)
}

extension Font {
    /// Mincho para el kana: trazo de pincel, se distingue mejor シ/ツ y ソ/ン que en gótica.
    static func kana(_ tamano: CGFloat, relativeTo estilo: Font.TextStyle = .largeTitle) -> Font {
        .custom("HiraMinProN-W6", size: tamano, relativeTo: estilo)
    }
    static let etiqueta = Font.system(.caption, design: .monospaced).weight(.semibold)
}

/// Encabezado de sección («MODO», «ERRORES»).
struct Seccion<Contenido: View>: View {
    let numero: String
    let titulo: String
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Dirección «Matcha»: título de sección en mayúsculas, sin número (el número queda solo como parámetro).
            Text(titulo.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Color.tintaSuave).tracking(1.4)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)  // VoiceOver salta de sección en sección
            contenido
        }
    }
}

/// Coloca subvistas en filas que se parten al llegar al borde (palabras de kana, chips de filas).
struct FlujoLayout: Layout {
    var espacio: CGFloat = 8
    var espacioFila: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let filas = acomodar(ancho: proposal.width ?? .infinity, subviews)
        let alto = filas.map(\.alto).reduce(0, +) + espacioFila * CGFloat(max(filas.count - 1, 0))
        return CGSize(width: proposal.width ?? filas.map(\.ancho).max() ?? 0, height: alto)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for fila in acomodar(ancho: bounds.width, subviews) {
            var x = bounds.minX
            for i in fila.indices {
                var tamano = subviews[i].sizeThatFits(.unspecified)
                // Una subvista más ancha que el contenedor se ajusta a él en vez de salirse.
                tamano.width = min(tamano.width, bounds.width)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(tamano))
                x += tamano.width + espacio
            }
            y += fila.alto + espacioFila
        }
    }

    private struct Fila { var indices: [Int] = []; var ancho: CGFloat = 0; var alto: CGFloat = 0 }

    private func acomodar(ancho: CGFloat, _ subviews: Subviews) -> [Fila] {
        var filas: [Fila] = [Fila()]
        for (i, subvista) in subviews.enumerated() {
            let tamano = subvista.sizeThatFits(.unspecified)
            let necesario = filas[filas.count - 1].indices.isEmpty ? tamano.width : filas[filas.count - 1].ancho + espacio + tamano.width
            if necesario > ancho, !filas[filas.count - 1].indices.isEmpty {
                filas.append(Fila())
            }
            let ultima = filas.count - 1
            filas[ultima].ancho = filas[ultima].indices.isEmpty ? tamano.width : filas[ultima].ancho + espacio + tamano.width
            filas[ultima].alto = max(filas[ultima].alto, tamano.height)
            filas[ultima].indices.append(i)
        }
        return filas
    }
}

/// Selector segmentado con el estilo de la app.
struct Segmentado<Valor: Hashable>: View {
    let opciones: [(Valor, String)]
    @Binding var seleccion: Valor
    var identificador = ""

    var body: some View {
        Picker("", selection: $seleccion) {
            ForEach(opciones, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(identificador)
    }
}

extension View {
    /// Campo para escribir romaji: sin autocorrección ni mayúscula inicial (modo de fallo 54).
    func campoRomaji() -> some View {
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
    }

    func tarjetaFondo() -> some View { bloque(relleno: 20) }

    /// Bloque blanco elevado: radio 22, sombra suave (en oscuro, un filo en vez de sombra).
    func bloque(relleno: CGFloat = 20, radio: CGFloat = 22) -> some View {
        padding(relleno)
            // La sombra solo en el fondo: aplicada a todo el bloque, también la proyectaban el kana y los textos.
            .background {
                RoundedRectangle(cornerRadius: radio, style: .continuous).fill(Color.superficie)
                    .shadow(color: Color.sombra, radius: 18, y: 10)
            }
            .overlay(RoundedRectangle(cornerRadius: radio, style: .continuous).strokeBorder(Color.linea.opacity(0.6), lineWidth: 0.5))
    }
}

func segundos(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }

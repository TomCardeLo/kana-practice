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
    static let linea = Color(claro: 0xD5D9DE, oscuro: 0x2A3A55)
    static let verde = Color(claro: 0x057A56, oscuro: 0x44BF9A)
    static let verdeFondo = Color(claro: 0xD5F2E9, oscuro: 0x0F3A30)
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

/// Encabezado numerado de sección, como en la web ("01 · Modo").
struct Seccion<Contenido: View>: View {
    let numero: String
    let titulo: String
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(numero).font(.etiqueta).foregroundStyle(Color.verde)
                Text(titulo.uppercased()).font(.etiqueta).foregroundStyle(Color.tintaSuave).tracking(1.2)
            }
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

    func tarjetaFondo() -> some View {
        padding(20)
            .background(Color.papel2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.linea))
    }
}

func segundos(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }

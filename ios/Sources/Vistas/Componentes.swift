import SwiftUI

// Componentes de la dirección «Matcha» (lienzo «Kana rediseño», opción C): superficies blancas elevadas, tinta azul
// marino, verde como único acento. Cada pieza es su propia vista con entradas mínimas (skill swiftui-specialist:
// una vista por sección, invalidación acotada).

/// Botón principal: tinta llena, texto claro, 56 pt.
struct EstiloPrincipal: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Color.papel)
            .background(Color.tinta, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Botón secundario en ficha («No la sé»): toda la ficha responde al toque, al menos 44 pt.
struct EstiloSecundario: ButtonStyle {
    @Environment(\.isEnabled) private var activo

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.tinta)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(activo ? (configuration.isPressed ? 0.7 : 1) : 0.5)
    }
}

/// Etiqueta pequeña sobre fondo de color («6 por repasar», «Nueva»).
struct Ficha: View {
    let texto: String
    var fondo: Color = .chip
    var tinta: Color = .tinta

    var body: some View {
        Text(texto)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tinta)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(fondo, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Una opción de respuesta (Tarjetas y Palabras). Tras un error la correcta va en verde y la elegida en rojo, con
/// icono y valor de accesibilidad además del color (modos de fallo 91–93).
struct BotonOpcion: View {
    enum Marca { case ninguna, correcta, elegida }

    let texto: String
    let numero: Int
    let marca: Marca
    let enPausa: Bool
    var monoespaciada = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 10) {
                Text(texto)
                    .font(monoespaciada ? .system(.title, design: .monospaced).weight(.semibold) : .title3.weight(marca == .ninguna ? .semibold : .heavy))
                    .multilineTextAlignment(monoespaciada ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: monoespaciada ? .center : .leading)
                if marca != .ninguna {
                    Image(systemName: marca == .correcta ? "checkmark" : "xmark").font(.headline.weight(.heavy))
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: monoespaciada ? 72 : 58)
            .foregroundStyle(marca == .correcta ? Color.verdeTinta : marca == .elegida ? Color.rojo : Color.tinta)
            .background(marca == .correcta ? Color.verdeFondo : marca == .elegida ? Color.rojoFondo : Color.superficie,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(marca == .correcta ? Color.verde : marca == .elegida ? Color.rojo : Color.linea,
                              lineWidth: marca == .ninguna ? 1.5 : 2))
        }
        .buttonStyle(EstiloOpcion())
        .disabled(enPausa)
        .keyboardShortcut(KeyEquivalent(Character("\(numero)")), modifiers: [])
        .accessibilityLabel(texto)
        .accessibilityValue(marca == .correcta ? "correcta" : marca == .elegida ? "tu elección" : "")
        .accessibilityIdentifier("opcion-\(numero)")
    }

    /// Sin el atenuado de los botones desactivados: en la pausa los colores se ven plenos.
    private struct EstiloOpcion: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Cabecera de una ronda: salir, barra de avance gruesa, «7/16» y el combo desde 3 (modo de fallo 73).
struct BarraJuego: View {
    let indice: Int
    let total: Int
    let combo: Int
    let salir: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: salir) {
                Image(systemName: "xmark").font(.headline).foregroundStyle(Color.tinta)
                    .frame(width: 44, height: 44)
                    .background(Color.superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.sombra, radius: 1, y: 1)
            }
            .accessibilityLabel("Salir")
            .accessibilityIdentifier("btn-salir")
            ProgressView(value: Double(indice), total: Double(max(total, 1)))
                .progressViewStyle(BarraGruesa())
            Text("\(indice + 1)/\(total)")
                .font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Color.tintaSuave)
                .accessibilityIdentifier("progreso")
            if combo >= 3 {
                Text("×\(combo)")
                    .font(.subheadline.weight(.black)).foregroundStyle(Color.verde)
                    .accessibilityLabel("Combo de \(combo)")
                    .accessibilityIdentifier("combo")
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

private struct BarraGruesa: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.chip)
                Capsule().fill(Color.verde).frame(width: geo.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 10)
    }
}

/// Anillo de la meta del día (32 de 50).
struct AnilloMeta: View {
    let hoy: Int
    let meta: Int
    /// Crece con el tamaño de texto: los números de dentro no se montan sobre el trazo.
    @ScaledMetric(relativeTo: .title) private var diametro: CGFloat = 96

    var body: some View {
        let fraccion = min(Double(hoy) / Double(max(meta, 1)), 1)
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.chip, lineWidth: 10)
                Circle().trim(from: 0, to: fraccion)
                    .stroke(Color.verde, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(min(hoy, meta))").font(.title.weight(.black)).monospacedDigit()
                    Text("de \(meta)").font(.caption.weight(.medium)).foregroundStyle(Color.tintaSuave)
                }
            }
            .frame(width: diametro, height: diametro)
            Text(hoy >= meta ? "Meta cumplida" : "Meta del día").font(.subheadline.weight(.bold))
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .bloque(relleno: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hoy \(min(hoy, meta))/\(meta)")
        .accessibilityValue(hoy >= meta ? "Meta cumplida" : "Faltan \(meta - hoy)")
        .accessibilityIdentifier("racha-hoy")
    }
}

/// Racha en verde con 続 («continuar») de marca de agua.
struct BloqueRacha: View {
    let racha: Int
    let mejor: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Racha").font(.subheadline.weight(.bold)).opacity(0.9)
            Spacer(minLength: 0)
            Text("\(racha)").font(.system(size: 52, weight: .black)).monospacedDigit().minimumScaleFactor(0.6)
            Text(racha == 1 ? "día · mejor \(mejor)" : "días · mejor \(mejor)").font(.subheadline.weight(.medium)).opacity(0.9)
        }
        // Papel sobre verde (no blanco fijo): contraste suficiente en los dos temas.
        .foregroundStyle(Color.papel)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(16)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.verde)
                Text("続").font(.kana(140)).foregroundStyle(Color.papel.opacity(0.14)).offset(x: 14, y: 34)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(racha == 1 ? "1 día de racha" : "\(racha) días de racha")
        .accessibilityValue("Mejor racha: \(mejor) días")
        .accessibilityIdentifier("racha-dias")
    }
}

/// Bloque para elegir un silabario en la ronda libre (あ, ア, あア).
struct BloqueSilabario: View {
    let muestra: String
    let nombre: String
    let elegido: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(spacing: 4) {
                Text(muestra).font(.kana(28, relativeTo: .title2)).foregroundStyle(Color.tinta)
                Text(nombre).font(.caption.weight(.bold)).foregroundStyle(elegido ? Color.tinta : Color.tintaSuave)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(Color.superficie, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(elegido ? Color.tinta : Color.linea, lineWidth: elegido ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nombre)
        .accessibilityAddTraits(elegido ? .isSelected : [])
        .accessibilityIdentifier("config-silabario-\(nombre)")
    }
}

/// Texto y luego el icono («Repasar ahora →»).
struct TextoYIcono: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) { configuration.title; configuration.icon }
    }
}

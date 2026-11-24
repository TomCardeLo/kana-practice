import SwiftUI

/// Ajustes de la app: sonido y vibración (modo de fallo 58).
struct AjustesVista: View {
    @AppStorage(Efectos.claveSonido) private var sonido = true
    @AppStorage(Efectos.claveVibracion) private var vibracion = true
    @Environment(\.dismiss) private var cerrar
    @Environment(Sincronizador.self) private var sincronizador
    @State private var verConexion = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sonidos", isOn: $sonido).accessibilityIdentifier("ajuste-sonido")
                    Toggle("Vibración", isOn: $vibracion).accessibilityIdentifier("ajuste-vibracion")
                } footer: {
                    Text("Los sonidos respetan el modo silencio del iPhone y no cortan tu música.")
                }
                Section("Deepy") {
                    if sincronizador.conectado {
                        Button("Desconectar este equipo", role: .destructive) { sincronizador.desconectar() }
                            .accessibilityIdentifier("btn-desconectar")
                    } else {
                        Button("Conectar con Deepy") { verConexion = true }.accessibilityIdentifier("btn-ir-conectar")
                    }
                }
                Section("Meta diaria") {
                    LabeledContent("Respuestas al día", value: "\(Rachas.metaDiaria)")
                }
                SeccionRecordatorio()
                // Atribución que exigen las licencias de JMdict y KANJIDIC2 (CC BY-SA 4.0, modo de fallo 103) y KanjiVG (CC BY-SA 3.0, 122).
                Section("Créditos") {
                    Text("Vocabulario y kanji: JMdict y KANJIDIC2, del Electronic Dictionary Research and Development Group (edrdg.org), con licencia CC BY-SA 4.0. Lista JLPT N5 de Jonathan Waller (tanos.co.uk). Los significados en español que faltaban o se corrigieron los preparó Claude. Trazos de los kana: KanjiVG, de Ulrich Apel (kanjivg.tagaini.net), con licencia CC BY-SA 3.0.")
                        .font(.footnote).foregroundStyle(Color.tintaSuave)
                        .accessibilityIdentifier("creditos")
                }
            }
            .navigationTitle("Ajustes")
            .sheet(isPresented: $verConexion) { ConexionVista() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
        }
    }
}

/// Recordatorio diario: interruptor, hora y lo que quedó programado (para ver que funciona, sin esperar al aviso).
private struct SeccionRecordatorio: View {
    @AppStorage(Recordatorio.claveActivo) private var activo = false
    @AppStorage(Recordatorio.claveMinutos) private var minutos = Recordatorio.minutosPorDefecto
    private let recordatorio = Recordatorio.compartido

    var body: some View {
        Section {
            Toggle("Avisarme si no llego a la meta", isOn: Binding(get: { activo }, set: { nuevo in
                Task { await recordatorio.encender(nuevo) }
            }))
            .accessibilityIdentifier("ajuste-recordatorio")
            if activo {
                DatePicker("Hora", selection: Binding(get: { hora }, set: { nueva in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: nueva)
                    Task { await recordatorio.cambiarHora(minutos: (c.hour ?? 20) * 60 + (c.minute ?? 0)) }
                }), displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("ajuste-recordatorio-hora")
            }
            Text(textoProximo).font(.subheadline).foregroundStyle(Color.tintaSuave)
                .accessibilityIdentifier("recordatorio-proximo")
            if activo {
                Text("\(recordatorio.programados) avisos en los próximos 7 días").font(.footnote).foregroundStyle(Color.tintaSuave)
                    .accessibilityIdentifier("recordatorio-cuenta")
            }
            if let aviso = recordatorio.aviso {
                Text(aviso).font(.footnote).foregroundStyle(Color.rojo).accessibilityIdentifier("recordatorio-aviso")
            }
        } header: {
            Text("Recordatorio diario")
        } footer: {
            Text("Si a esa hora no has hecho \(Rachas.metaDiaria) respuestas, te avisa cuánto te falta. Si ya cumpliste, ese día no suena.")
        }
    }

    private var hora: Date {
        // Hora de reloj (no minutos transcurridos): el día del cambio de horario se muestra bien (modo de fallo 110).
        Calendar.current.date(bySettingHour: minutos / 60, minute: minutos % 60, second: 0, of: .now) ?? .now
    }

    private var textoProximo: String {
        guard let p = recordatorio.proximo else { return "Sin avisos programados." }
        let calendario = Calendar.current
        let dia = calendario.isDateInToday(p.fecha) ? "hoy" : calendario.isDateInTomorrow(p.fecha) ? "mañana"
            : p.fecha.formatted(.dateTime.weekday(.wide))
        return "Próximo aviso: \(dia), \(p.fecha.formatted(date: .omitted, time: .shortened)) — \(p.texto)"
    }
}

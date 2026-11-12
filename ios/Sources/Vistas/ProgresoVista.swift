import SwiftData
import SwiftUI

/// Estadísticas por kana a partir de los intentos guardados (equivale a «Mis estadísticas» de la web).
struct ProgresoVista: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Intento.fecha, order: .reverse) private var intentos: [Intento]
    @State private var silabario = Silabario.hiragana
    @State private var confirmarBorrado = false
    @State private var errorBorrado: String?

    private struct Fila: Identifiable {
        let kana: String
        let ok: Int
        let fallos: Int
        var id: String { kana }
        var total: Int { ok + fallos }
        var tasaError: Double { total > 0 ? Double(fallos) / Double(total) : 0 }
    }

    // ponytail: agrega todos los intentos en memoria en cada render; con decenas de miles de intentos,
    // pasar a una Query filtrada por silabario y fetchCount (o al resumen que calculará el servidor).
    /// Los silabarios nunca se mezclan (modo de fallo 51); orden por % de error descendente.
    private var ranking: [Fila] {
        let propios = intentos.filter { $0.silabario == silabario.rawValue }
        return Dictionary(grouping: propios, by: \.item)
            .map { kana, lista in Fila(kana: kana, ok: lista.filter(\.correcto).count, fallos: lista.filter { !$0.correcto }.count) }
            .sorted { ($0.tasaError, $0.total, $1.kana) > ($1.tasaError, $1.total, $0.kana) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    resumen
                    Segmentado(opciones: Silabario.allCases.map { ($0, $0.nombre) }, seleccion: $silabario,
                               identificador: "progreso-silabario")
                    let filas = ranking
                    if filas.isEmpty {
                        Text("Todavía no hay estadísticas para este silabario. Juega una ronda o corrige una lectura para empezar.")
                            .foregroundStyle(Color.tintaSuave)
                            .accessibilityIdentifier("progreso-vacio")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                            ForEach(filas) { celda($0) }
                        }
                    }
                    Button("Borrar todo el progreso", role: .destructive) { confirmarBorrado = true }
                        .buttonStyle(.bordered)
                        .disabled(intentos.isEmpty)
                        .accessibilityIdentifier("btn-borrar")
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Color.papel)
            .navigationTitle("Progreso")
            .confirmationDialog("¿Borrar todo el progreso de este dispositivo?", isPresented: $confirmarBorrado,
                                titleVisibility: .visible) {
                Button("Borrar", role: .destructive, action: borrar)
            }
            .alert("No se pudo borrar el progreso", isPresented: .constant(errorBorrado != nil)) {
                Button("Entendido") { errorBorrado = nil }
            } message: {
                Text(errorBorrado ?? "")
            }
        }
    }

    private var resumen: some View {
        let hoy = intentos.filter { Calendar.current.isDateInToday($0.fecha) }
        let aciertos = intentos.filter(\.correcto).count
        return HStack(spacing: 12) {
            cifra("Respuestas", "\(intentos.count)", id: "progreso-total")
            cifra("Acierto", intentos.isEmpty ? "—" : "\(aciertos * 100 / intentos.count) %", id: "progreso-acierto")
            cifra("Hoy", "\(hoy.count)", id: "progreso-hoy")
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

    private func celda(_ fila: Fila) -> some View {
        let porcentaje = Int((fila.tasaError * 100).rounded())
        return VStack(spacing: 4) {
            Text(fila.kana).font(.kana(30))
            Text("\(porcentaje)% error").font(.caption.monospacedDigit())
                .foregroundStyle(porcentaje > 0 ? Color.rojo : Color.verde)
            Text("\(fila.total)×").font(.caption2.monospacedDigit()).foregroundStyle(Color.tintaSuave)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(porcentaje > 0 ? Color.rojoFondo.opacity(min(1, 0.25 + fila.tasaError)) : Color.papel2,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progreso-celda")
    }

    // ponytail: borra también lo no sincronizado; en la fase 2 decidir si el borrado se sincroniza.
    private func borrar() {
        do {
            try contexto.delete(model: Intento.self)
            try contexto.save()
        } catch {
            Progreso.log.error("No se pudo borrar el progreso: \(error, privacy: .public)")
            errorBorrado = error.localizedDescription
        }
    }
}

import SwiftData
import SwiftUI

/// Estadísticas por kana a partir de los intentos guardados (equivale a «Mis estadísticas» de la web).
struct ProgresoVista: View {
    @Environment(Sincronizador.self) private var sincronizador
    @Query(sort: \Intento.fecha, order: .reverse) private var intentos: [Intento]
    @State private var silabario = Silabario.hiragana
    @State private var verAjustes = false

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
        let propios = intentos.filter { $0.silabario == silabario.rawValue && $0.ejercicio != "escritura" }  // 119
        return Dictionary(grouping: propios, by: \.item)
            .map { kana, lista in Fila(kana: kana, ok: lista.filter(\.correcto).count, fallos: lista.filter { !$0.correcto }.count) }
            .sorted { ($0.tasaError, $0.total, $1.kana) > ($1.tasaError, $1.total, $0.kana) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ResumenRacha()
                    resumen
                    Segmentado(opciones: Silabario.allCases.map { ($0, $0.nombre) }, seleccion: $silabario,
                               identificador: "progreso-silabario")
                    dominadas
                    let filas = ranking
                    if filas.isEmpty {
                        Text("Todavía no hay estadísticas para este silabario. Juega una ronda o corrige una lectura para empezar.")
                            .foregroundStyle(Color.tintaSuave)
                            .accessibilityIdentifier("progreso-vacio")
                    } else {
                        Seccion(numero: "·", titulo: "Por kana · más fallados primero") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                                ForEach(filas) { celda($0) }
                            }
                        }
                    }
                    estadoSincronizacion
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Color.papel)
            .navigationTitle("Progreso")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ajustes", systemImage: "gearshape") { verAjustes = true }
                        .accessibilityIdentifier("btn-ajustes")
                }
            }
            .sheet(isPresented: $verAjustes) { AjustesVista() }
            .onAppear { sincronizador.contarPendientes() }
        }
    }

    /// Solo kana: vocabulario y kanji tienen su propia pantalla (modo de fallo 100).
    private var resumen: some View {
        let intentos = intentos.filter { $0.comoRespuesta != nil }
        let hoy = intentos.filter { Calendar.current.isDateInToday($0.fecha) }
        let aciertos = intentos.filter(\.correcto).count
        return HStack(spacing: 12) {
            cifra("Respuestas", "\(intentos.count)", id: "progreso-total")
            cifra("Acierto", intentos.isEmpty ? "—" : "\(aciertos * 100 / intentos.count) %", id: "progreso-acierto")
            cifra("Hoy", "\(hoy.count)", id: "progreso-hoy")
        }
    }

    /// Filas dominadas del silabario elegido (los hitos no mezclan silabarios, modo de fallo 68).
    private var dominadas: some View {
        let filas = Hitos.dominadas(intentos.compactMap(\.comoRespuesta)).filter { $0.silabario == silabario }.sorted()
        return Seccion(numero: "·", titulo: "Filas dominadas") {
            if filas.isEmpty {
                Text("Aún ninguna. Una fila se domina con 90 % de acierto en sus últimas respuestas y menos de 3 s por tarjeta.")
                    .font(.subheadline).foregroundStyle(Color.tintaSuave)
                    .accessibilityIdentifier("progreso-sin-dominadas")
            } else {
                FlujoLayout {
                    ForEach(filas, id: \.clave) { h in
                        Text(h.ejemplo).font(.kana(22))
                            .foregroundStyle(Color.papel)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.verde, in: Capsule())
                            .accessibilityIdentifier("progreso-dominada")
                    }
                }
            }
        }
    }

    private func cifra(_ titulo: String, _ valor: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo.uppercased()).font(.etiqueta).foregroundStyle(Color.tintaSuave).lineLimit(1).minimumScaleFactor(0.7)
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
        .background(porcentaje > 0 ? Color.rojoFondo.opacity(min(1, 0.25 + fila.tasaError)) : Color.superficie,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.linea, lineWidth: porcentaje > 0 ? 0 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progreso-celda")
    }

    /// Estado de la sincronización con Deepy: nunca falla en silencio (modo de fallo Y4).
    private var estadoSincronizacion: some View {
        HStack(spacing: 10) {
            Image(systemName: icono).foregroundStyle(colorEstado)
            VStack(alignment: .leading, spacing: 2) {
                Text(textoEstado).font(.subheadline).accessibilityIdentifier("sync-estado")
                if sincronizador.apartados > 0 {
                    Text("\(sincronizador.apartados) respuestas no se pudieron subir y quedaron solo en este equipo.")
                        .font(.caption).foregroundStyle(Color.rojo).accessibilityIdentifier("sync-apartados")
                }
                if sincronizador.pendientes > 0 {
                    Text("\(sincronizador.pendientes) respuestas por subir").font(.caption).foregroundStyle(Color.tintaSuave)
                        .accessibilityIdentifier("sync-pendientes")
                }
            }
            Spacer()
            if sincronizador.conectado {
                Button("Sincronizar") { Task { await sincronizador.sincronizar() } }
                    .disabled(sincronizador.estado == .sincronizando)
                    .accessibilityIdentifier("btn-sincronizar")
            }
        }
        .tarjetaFondo()
    }

    private var textoEstado: String {
        switch sincronizador.estado {
        case .sinConexion: "Sin conectar con Deepy: el progreso solo está en este equipo."
        case .inactivo: "Conectado con Deepy."
        case .sincronizando: "Sincronizando…"
        case let .listo(fecha): "Sincronizado \(fecha.formatted(.relative(presentation: .named)))."
        case let .error(mensaje): mensaje
        }
    }

    private var icono: String {
        switch sincronizador.estado {
        case .sinConexion: "icloud.slash"
        case .error: "exclamationmark.icloud"
        case .sincronizando: "arrow.triangle.2.circlepath.icloud"
        default: "checkmark.icloud"
        }
    }

    private var colorEstado: Color {
        switch sincronizador.estado {
        case .error: .rojo
        case .sinConexion: .tintaSuave
        default: .verde
        }
    }
}

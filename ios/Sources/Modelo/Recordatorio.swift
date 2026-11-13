import Foundation
import OSLog
import UserNotifications

/// Recordatorio diario local de la racha (sin servidor). Se reprograma entero cada vez que cambia el progreso, el
/// ajuste o se vuelve a la app, así el «te faltan» nunca es viejo (modos de fallo 106–112 en tests/e2e/failure-modes.md).
@MainActor
@Observable
final class Recordatorio {
    static let compartido = Recordatorio()
    static let claveActivo = "recordatorio.activo"
    static let claveMinutos = "recordatorio.minutos"  // hora de reloj local, en minutos desde la medianoche
    static let minutosPorDefecto = 20 * 60
    private static let prefijo = "racha-"
    private static let dias = 7  // modo de fallo 112
    private static let log = Logger(subsystem: "com.tommycardelo.kana", category: "recordatorio")

    /// Lo que se ve en Ajustes, leído de lo que de verdad quedó programado.
    private(set) var proximo: (fecha: Date, texto: String)?
    private(set) var programados = 0
    /// Sin permiso (también si se quitó después en iOS) o un error al programar: se dice (modo de fallo 109).
    private(set) var aviso: String?

    private let centro = UNUserNotificationCenter.current()
    /// Estado de la racha y el día local al que corresponde: el de ayer no sirve para hoy.
    private var ultimoEstado: (estado: Rachas.Estado, dia: Date)?
    /// Las reprogramaciones van en fila: dos a la vez dejaban avisos que no tocaban (modos 106 y 111).
    private var cola: Task<Void, Never>?

    var activo: Bool { UserDefaults.standard.bool(forKey: Self.claveActivo) }
    var minutos: Int { UserDefaults.standard.object(forKey: Self.claveMinutos) as? Int ?? Self.minutosPorDefecto }

    /// Se guarda al instante (el interruptor no parpadea); si iOS niega el permiso, vuelve a apagado y dice por qué.
    func encender(_ encender: Bool) async {
        UserDefaults.standard.set(encender, forKey: Self.claveActivo)
        if encender {
            let concedido = (try? await centro.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            // Si mientras se esperaba se volvió a tocar el interruptor, manda lo último.
            if !concedido, activo {
                UserDefaults.standard.set(false, forKey: Self.claveActivo)
            }
        }
        await reprogramar()
    }

    func cambiarHora(minutos: Int) async {
        UserDefaults.standard.set(minutos, forKey: Self.claveMinutos)
        await reprogramar()
    }

    /// Con el estado de ahora (respuestas propias o bajadas del otro equipo, modo de fallo 107).
    func actualizar(_ estado: Rachas.Estado, ahora: Date = .now) async {
        ultimoEstado = (estado, Calendar.current.startOfDay(for: ahora))
        await reprogramar()
    }

    /// Al volver a la app (otro día, o permiso cambiado en iOS).
    func refrescar() async { await reprogramar() }

    private func reprogramar() async {
        let previa = cola
        let tarea = Task {
            await previa?.value
            await reprogramarAhora()
            await leerProgramados()
        }
        cola = tarea
        await tarea.value
    }

    private func reprogramarAhora(ahora: Date = .now, calendario: Calendar = .current) async {
        aviso = nil
        // Primero se quita todo lo nuestro: nunca quedan avisos viejos (108) y apagar lo borra (111).
        let nuestros = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefijo) }
        centro.removePendingNotificationRequests(withIdentifiers: nuestros)
        guard activo else { return }
        let ajustes = await centro.notificationSettings()
        guard ajustes.authorizationStatus == .authorized || ajustes.authorizationStatus == .provisional else {
            aviso = "Kana no tiene permiso de notificaciones: el recordatorio no sonará. Actívalo en Ajustes de iOS → Notificaciones → Kana."
            return
        }

        let hoy = calendario.startOfDay(for: ahora)
        let estado = ultimoEstado.flatMap { $0.dia == hoy ? $0.estado : nil }  // el de ayer no vale (106)
        if estado?.metaCumplida == true {
            // Meta cumplida: si el aviso de hoy ya había salido, se quita del Centro de notificaciones.
            centro.removeDeliveredNotifications(withIdentifiers: [Self.identificador(hoy, calendario)])
        }
        for desplazamiento in 0 ..< Self.dias {
            // Hora de reloj local (no tiempo transcurrido): bien también los días de cambio de horario (110).
            guard let dia = calendario.date(byAdding: .day, value: desplazamiento, to: hoy),
                  let cuando = calendario.date(bySettingHour: minutos / 60, minute: minutos % 60, second: 0, of: dia),
                  cuando > ahora else { continue }
            let texto: String
            if desplazamiento == 0, let estado {
                guard !estado.metaCumplida else { continue }  // modo de fallo 106
                texto = Self.textoHoy(estado)
            } else {
                texto = "Haz tu repaso de hoy: \(Rachas.metaDiaria) respuestas mantienen la racha."
            }
            let contenido = UNMutableNotificationContent()
            contenido.title = "Kana"
            contenido.body = texto
            contenido.sound = .default
            let partes = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: cuando)
            let peticion = UNNotificationRequest(identifier: Self.identificador(dia, calendario), content: contenido,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: partes, repeats: false))
            do {
                try await centro.add(peticion)
            } catch {
                Self.log.error("No se programó el recordatorio: \(error.localizedDescription, privacy: .public)")
                aviso = "No se pudo programar el recordatorio: \(error.localizedDescription)"
            }
        }
    }

    /// Lo que se muestra sale de lo programado de verdad, no de lo que se intentó.
    private func leerProgramados() async {
        let nuestros = await centro.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.prefijo) }
        programados = nuestros.count
        proximo = nuestros.compactMap { p -> (Date, String)? in
            guard let fecha = (p.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return nil }
            return (fecha, p.content.body)
        }.min { $0.0 < $1.0 }.map { (fecha: $0.0, texto: $0.1) }
    }

    private static func identificador(_ dia: Date, _ calendario: Calendar) -> String {
        let c = calendario.dateComponents([.year, .month, .day], from: dia)
        return prefijo + "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func textoHoy(_ e: Rachas.Estado) -> String {
        let faltan = e.faltan == 1 ? "Te falta 1 respuesta" : "Te faltan \(e.faltan) respuestas"
        return e.racha > 0 ? "\(faltan) para mantener tu racha de \(e.racha) \(e.racha == 1 ? "día" : "días")."
                           : "\(faltan) para empezar una racha."
    }
}

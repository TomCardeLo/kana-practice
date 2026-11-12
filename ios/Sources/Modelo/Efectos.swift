import AVFoundation
import OSLog
import UIKit

/// Sonidos suaves (sintetizados, sin archivos ni licencias) y vibración. Ajustes: `Efectos.claveSonido`
/// y `Efectos.claveVibracion` en UserDefaults (activados por defecto).
@MainActor
final class Efectos {
    static let compartidos = Efectos()
    static let claveSonido = "ajustes.sonido"
    static let claveVibracion = "ajustes.vibracion"

    enum Sonido: Hashable {
        case acierto(combo: Int)
        case error
        case sinVidas
        case rondaCompleta
        case record
        case meta
        case hito
    }

    private static let log = Logger(subsystem: "com.tommycardelo.kana", category: "efectos")
    private static let muestreo = 44_100.0
    private static let voces = 4
    /// Escala pentatónica: el combo sube de tono sin desafinar.
    private static let pentatonica: [Double] = [1.0, 9.0 / 8, 5.0 / 4, 3.0 / 2, 5.0 / 3, 2.0, 9.0 / 4, 5.0 / 2, 3.0]

    private let motor = AVAudioEngine()
    private let formato = AVAudioFormat(standardFormatWithSampleRate: muestreo, channels: 1)!
    private var reproductores: [AVAudioPlayerNode] = []
    private var siguiente = 0
    private var buffers: [Sonido: AVAudioPCMBuffer] = [:]

    private init() {
        UserDefaults.standard.register(defaults: [Self.claveSonido: true, Self.claveVibracion: true])
        // `.ambient`: respeta el interruptor de silencio y no corta la música (modo de fallo 57).
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            Self.log.error("Sesión de audio: \(error, privacy: .public)")
        }
        for _ in 0 ..< Self.voces {
            let nodo = AVAudioPlayerNode()
            motor.attach(nodo)
            motor.connect(nodo, to: motor.mainMixerNode, format: formato)
            reproductores.append(nodo)
        }
        motor.mainMixerNode.outputVolume = 0.5
        motor.prepare()
    }

    /// Arranca el motor al abrir la app para que el primer sonido no llegue tarde (modo de fallo 59).
    func preparar() {
        arrancar()
        _ = buffer(.acierto(combo: 0))
    }

    func reproducir(_ sonido: Sonido) {
        vibrar(sonido)
        guard UserDefaults.standard.bool(forKey: Self.claveSonido) else { return }  // modo de fallo 58
        // Tras una llamada o Siri el motor queda parado: se rearranca al vuelo (modo de fallo 60).
        guard arrancar() else { return }
        let nodo = reproductores[siguiente]
        siguiente = (siguiente + 1) % reproductores.count  // varias voces: los sonidos seguidos no se cortan
        nodo.stop()
        nodo.scheduleBuffer(buffer(sonido))
        nodo.play()
    }

    @discardableResult
    private func arrancar() -> Bool {
        if motor.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try motor.start()
            return true
        } catch {
            Self.log.error("No arrancó el audio: \(error, privacy: .public)")
            return false
        }
    }

    private func vibrar(_ sonido: Sonido) {
        guard UserDefaults.standard.bool(forKey: Self.claveVibracion) else { return }
        switch sonido {
        case .acierto: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .sinVidas: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .rondaCompleta, .record, .meta, .hito: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Síntesis

    private func buffer(_ sonido: Sonido) -> AVAudioPCMBuffer {
        let clave: Sonido = if case let .acierto(combo) = sonido { .acierto(combo: min(combo, Self.pentatonica.count - 1)) } else { sonido }
        if let hecho = buffers[clave] { return hecho }
        let nuevo = sintetizar(notas(clave))
        buffers[clave] = nuevo
        return nuevo
    }

    /// (frecuencia en Hz, inicio en s, duración en s, volumen)
    private typealias Nota = (Double, Double, Double, Double)

    private func notas(_ sonido: Sonido) -> [Nota] {
        let do5 = 523.25, mi5 = 659.25, sol5 = 783.99, do6 = 1046.5
        switch sonido {
        case let .acierto(combo):
            let f = 880 * Self.pentatonica[combo]
            return [(f, 0, 0.18, 0.55), (f * 3 / 2, 0.06, 0.22, 0.4)]
        case .error:
            return [(233.08, 0, 0.16, 0.6), (196.0, 0.09, 0.22, 0.5)]
        case .sinVidas:
            return [(392.0, 0, 0.3, 0.45), (329.63, 0.16, 0.3, 0.45), (261.63, 0.32, 0.6, 0.5)]
        case .rondaCompleta:
            return [(do5, 0, 0.35, 0.45), (mi5, 0.09, 0.35, 0.45), (sol5, 0.18, 0.35, 0.45), (do6, 0.27, 0.7, 0.5)]
        case .record, .meta:
            return [(do5, 0, 0.3, 0.4), (mi5, 0.07, 0.3, 0.4), (sol5, 0.14, 0.3, 0.4), (do6, 0.21, 0.4, 0.45),
                    (1318.5, 0.28, 0.4, 0.35), (1568.0, 0.35, 0.9, 0.35)]
        case .hito:
            return [(do5, 0, 1.2, 0.35), (mi5, 0, 1.2, 0.3), (sol5, 0, 1.2, 0.3), (do6, 0.12, 1.3, 0.35)]
        }
    }

    /// Timbre de campanita de madera/cristal: fundamental + parcial inarmónico (×2,76, como una marimba)
    /// que se apaga antes; ataque de 4 ms y caída exponencial.
    private func sintetizar(_ notas: [Nota]) -> AVAudioPCMBuffer {
        let largo = (notas.map { $0.1 + $0.2 }.max() ?? 0.2) + 0.05
        let cuadros = AVAudioFrameCount(largo * Self.muestreo)
        let pcm = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: cuadros)!
        pcm.frameLength = cuadros
        let datos = pcm.floatChannelData![0]
        for i in 0 ..< Int(cuadros) { datos[i] = 0 }
        for (frecuencia, inicio, duracion, volumen) in notas {
            let desde = Int(inicio * Self.muestreo)
            let total = Int(duracion * Self.muestreo)
            for j in 0 ..< total where desde + j < Int(cuadros) {
                let t = Double(j) / Self.muestreo
                let ataque = min(1, t / 0.004)
                let caida = exp(-t * 5.5 / duracion)
                let muestra = sin(2 * .pi * frecuencia * t) + 0.35 * sin(2 * .pi * frecuencia * 2.76 * t) * exp(-t * 14 / duracion)
                datos[desde + j] += Float(muestra * ataque * caida * volumen * 0.5)
            }
        }
        return pcm
    }
}

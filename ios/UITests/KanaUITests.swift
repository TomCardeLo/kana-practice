import XCTest

/// Pruebas E2E de la app iOS. Cubren los modos de fallo de interfaz y progreso de
/// `tests/e2e/failure-modes.md` (16–20, 25–41, 48–52, 54–55). La conversión de romaji ya la cubre
/// `ios/scripts/paridad.sh`; aquí se prueban los flujos de usuario.
/// Ejecución completa con evidencia: `ios/scripts/e2e.sh`.
final class KanaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - Sincronización con Deepy (modos de fallo Y1–Y6 de Sources/Modelo/Sincronizacion.swift)
    // Requieren el Deepy local de ios/scripts/servidor_deepy.mjs (lo levanta e2e.sh). El iPhone sube y el
    // iPad baja, como dos equipos reales: e2e.sh corre el iPhone antes que el iPad contra el mismo servidor.

    private static let servidor = "http://127.0.0.1:3108"
    private var esIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func relanzarConServidor(_ url: String = servidor) {
        app.terminate()
        app.launchArguments = ["-uitest", "-uitest-conexion"]
        app.launchEnvironment["KANA_BASE_URL"] = url
        app.launch()
    }

    private func escribirPassword(_ password: String) {
        let campo = el("conexion-password")
        XCTAssertTrue(campo.waitForExistence(timeout: 10), "No apareció la hoja para conectar con Deepy")
        campo.tap()
        campo.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + password)
        toca("btn-conectar")
    }

    private func esperarConectado() {
        esperar(el("conexion-password"), NSPredicate(format: "exists == false"), timeout: 20)
    }

    /// Y4 y conexión: sin servidor y con contraseña mala se avisa; con la buena conecta y sube una ronda (Y1).
    func testSincronizacionSubeDesdeElIPhone() throws {
        try XCTSkipIf(esIPad, "El iPhone sube; el iPad baja en testSincronizacionBajaEnElIPad")
        relanzarConServidor("http://127.0.0.1:9")  // nadie escucha ahí
        escribirPassword("password-de-prueba")
        XCTAssertTrue(el("conexion-error").waitForExistence(timeout: 40))
        XCTAssertTrue(el("conexion-error").label.hasPrefix("Sin conexión"), el("conexion-error").label)

        relanzarConServidor()
        escribirPassword("no-es-la-buena")
        esperarLabel("conexion-error", "Contraseña incorrecta.", timeout: 15)
        captura("conexion-contrasena-mala")
        escribirPassword("password-de-prueba")
        esperarConectado()

        irA("Tarjetas")
        configurarTarjetas(tamano: "5")
        toca("btn-empezar")
        jugarRonda(de: 5)
        esperarLabel("resumen-titulo", "¡Ronda completada!")

        irA("Progreso")
        esperar(el("sync-estado"), NSPredicate(format: "label BEGINSWITH 'Sincronizado'"), timeout: 20)
        XCTAssertFalse(el("sync-pendientes").exists, "Quedaron respuestas sin subir")
        XCTAssertEqual(el("progreso-total").label, "5")
        captura("sincronizacion-iphone")
    }

    /// Y2: el iPad baja lo que subió el iPhone, y volver a sincronizar no lo duplica.
    func testSincronizacionBajaEnElIPad() throws {
        try XCTSkipUnless(esIPad, "El iPad baja lo que subió el iPhone en testSincronizacionSubeDesdeElIPhone")
        relanzarConServidor()
        escribirPassword("password-de-prueba")
        esperarConectado()
        irA("Progreso")
        esperarLabel("progreso-total", "5", timeout: 20)
        XCTAssertEqual(el("progreso-hoy").label, "5")
        toca("btn-sincronizar")
        esperar(el("sync-estado"), NSPredicate(format: "label BEGINSWITH 'Sincronizado'"), timeout: 20)
        XCTAssertEqual(el("progreso-total").label, "5", "Volver a sincronizar duplicó intentos (Y2)")
        captura("sincronizacion-ipad")
    }

    // MARK: - Tarjetas

    /// 29, 37, 41: ronda perfecta de 5 con récord; otra ronda más lenta no lo pisa.
    func testTarjetasRondaPerfectaYRecordNoSeSobrescribe() {
        configurarTarjetas(tamano: "5")
        toca("btn-empezar")
        let kanas = jugarRonda(de: 5)
        XCTAssertEqual(Set(kanas).count, 5, "Una tarjeta se repitió en la ronda: \(kanas)")
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        XCTAssertEqual(el("resumen-aciertos").label, "5/5")
        XCTAssertTrue(el("resumen-record").label.hasPrefix("¡Nuevo récord!"), el("resumen-record").label)
        XCTAssertTrue(app.staticTexts["Sin errores"].exists)
        let media1 = el("resumen-media").label
        captura("tarjetas-ronda-perfecta")

        toca("btn-otra")
        // Otra ronda empieza de cero (41).
        esperarLabel("progreso", "1/5")
        XCTAssertEqual(el("vidas").label, "Vidas: 3 de 3")
        // Cada tarjeta se responde después de que el cronómetro supere la media anterior.
        let umbral = segundos(media1) + 0.3
        jugarRonda(de: 5) { _ in
            self.esperar(self.el("cronometro"), NSPredicate { objeto, _ in
                guard let e = objeto as? XCUIElement, e.exists else { return false }
                return Self.segundos(e.label) > umbral
            }, timeout: 15)
        }
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        let media2 = el("resumen-media").label
        XCTAssertGreaterThan(segundos(media2), segundos(media1), "La segunda ronda no fue más lenta")
        XCTAssertEqual(el("resumen-record").label, "Récord: \(media1) por tarjeta")
        captura("tarjetas-ronda-lenta-sin-record")
    }

    /// 33, 34, 35, 39: Enter vacío, sílaba a medias, error con Enter, «No la sé» y fin sin vidas.
    func testTarjetasErroresHastaQuedarseSinVidas() {
        configurarTarjetas(tamano: "10")
        toca("btn-empezar")
        let campo = el("tarjeta-input")
        esperarLabel("progreso", "1/10")

        // Enter con el campo vacío no resta vida (39).
        campo.typeText("\n")
        XCTAssertEqual(el("vidas").label, "Vidas: 3 de 3")
        XCTAssertEqual(el("progreso").label, "1/10")
        XCTAssertEqual(el("tarjeta-feedback").label, " ")

        // Una sílaba a medio escribir no avanza ni resta (33).
        campo.typeText("k")
        XCTAssertEqual(campo.value as? String, "k")
        XCTAssertEqual(el("progreso").label, "1/10")
        XCTAssertEqual(el("vidas").label, "Vidas: 3 de 3")
        campo.typeText(XCUIKeyboardKey.delete.rawValue)

        // Respuesta mala con Enter: muestra la lectura correcta y resta una vida (34, 35).
        var errores = [fallarConEnter(campo, vidasRestantes: 2)]
        esperarLabel("progreso", "2/10")
        esperarLabel("tarjeta-feedback", " ")
        XCTAssertTrue(vacio(campo), "La respuesta mala pasó a la tarjeta siguiente: \(String(describing: campo.value))")

        // «No la sé» resta una vida y lo escrito durante la pausa se descarta al instante (34, 35).
        let kana2 = el("tarjeta-kana").label
        toca("btn-nolase")
        campo.typeText("z")
        let valor = campo.value
        // Si la lectura ya no está, la pausa terminó antes de comprobarla y la prueba no demuestra nada.
        XCTAssertEqual(el("tarjeta-feedback").label, "\(kana2) se lee \(romaji(kana2))",
                       "La pausa terminó antes de comprobarla")
        XCTAssertTrue(vacio(campo, valor), "Lo escrito durante la pausa no se descartó: \(String(describing: valor))")
        XCTAssertEqual(el("vidas").label, "Vidas: 1 de 3")
        XCTAssertFalse(el("btn-nolase").isEnabled)
        errores.append(kana2)
        esperarLabel("progreso", "3/10")
        XCTAssertTrue(vacio(campo), "Lo escrito en la pausa pasó a la tarjeta siguiente")
        XCTAssertEqual(el("vidas").label, "Vidas: 1 de 3")

        // Tercer error: el foco vuelve solo al campo; la lectura se ve antes del resumen.
        errores.append(fallarConEnter(campo, vidasRestantes: 0))
        esperarLabel("resumen-titulo", "Sin vidas", timeout: 5)
        XCTAssertEqual(el("resumen-aciertos").label, "0/10")
        XCTAssertEqual(el("resumen-record").label, "Completa la ronda para registrar un récord.")
        let chips = app.staticTexts.matching(identifier: "resumen-errores").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(chips, errores.map { "\($0) → \(romaji($0))" })
        captura("tarjetas-sin-vidas")
    }

    /// 35: tras un error con Enter el campo conserva el foco durante la pausa (el teclado no baja y sube).
    func testTarjetasErrorConEnterConservaElTeclado() {
        toca("btn-empezar")
        esperarLabel("progreso", "1/10")
        let campo = el("tarjeta-input")
        let kana = el("tarjeta-kana").label
        campo.typeText("x\n")
        let foco = campo.value(forKey: "hasKeyboardFocus") as? Bool ?? false
        let teclados = app.keyboards.count
        XCTAssertEqual(el("tarjeta-feedback").label, "\(kana) se lee \(romaji(kana))",
                       "La pausa terminó antes de comprobarla")
        captura("tarjetas-pausa-tras-enter")
        XCTAssertTrue(foco && teclados > 0,
                      "Tras Enter con error el campo pierde el foco (teclados: \(teclados)): el teclado baja y sube")
    }

    /// 29, 30, 32: el mazo básico completo de hiragana sale entero, sin repetir, con variantes kunrei.
    func testTarjetasHiraganaCompletaConVariantes() {
        configurarTarjetas(tamano: "Todas (46)")
        toca("btn-empezar")
        let kanas = jugarRonda(de: 46, variantes: true)
        XCTAssertEqual(kanas.sorted(), Self.hiragana.map(\.0).sorted(), "El mazo no coincide con los 46 básicos")
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        XCTAssertEqual(el("resumen-aciertos").label, "46/46")
        captura("tarjetas-mazo-completo")
    }

    /// 30, 31: tamaños de los mazos y «Ambos» + «Todos» con 204 tarjetas.
    func testTarjetasTamanoDeLosMazos() {
        let tamano = app.segmentedControls["config-tamano"]
        XCTAssertTrue(tamano.buttons["Todas (46)"].waitForExistence(timeout: 5))
        configurarTarjetas(mazo: "Todos")
        XCTAssertTrue(tamano.buttons["Todas (102)"].exists)
        configurarTarjetas(silabario: "Ambos")
        XCTAssertTrue(tamano.buttons["Todas (204)"].exists)
        configurarTarjetas(tamano: "Todas (204)")
        captura("tarjetas-ambos-todos")
        toca("btn-empezar")
        esperarLabel("progreso", "1/204")
        toca("btn-salir")
        XCTAssertTrue(el("btn-empezar").waitForExistence(timeout: 5))
    }

    // MARK: - Leer

    /// 17, 48, 49, 54: texto propio, corrección con un error y después perfecta, sin duplicar intentos.
    func testLeerTextoPropioCorrigeYNoDuplicaIntentos() {
        generarTextoPropio("casa luna")
        XCTAssertEqual(celdas("celda-pending"), ["か", "さ", "る", "な"])

        let respuesta = el("lectura-respuesta")
        respuesta.tap()
        respuesta.typeText("kaza runa")
        XCTAssertEqual(respuesta.value as? String, "kaza runa", "El teclado alteró la respuesta (54)")
        toca("btn-corregir")
        esperarLabel("lectura-marcador", "3 / 4 correctos")
        XCTAssertEqual(cuenta("celda-ok"), 3)
        XCTAssertEqual(cuenta("celda-error"), 1, "Un error desalineó el resto de la palabra (17)")
        captura("leer-un-error")

        // Corregir otra vez, ahora bien: se actualiza el marcador pero no se registra de nuevo.
        respuesta.tap()
        respuesta.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "kasa runa")
        XCTAssertEqual(respuesta.value as? String, "kasa runa")
        toca("btn-corregir")
        esperarLabel("lectura-marcador", "4 / 4 correctos")
        XCTAssertEqual(cuenta("celda-ok"), 4)
        XCTAssertEqual(cuenta("celda-error"), 0)

        // Cambiar el filtro recorrige sin registrar (49). Se quita la fila MA, que no sale en el texto.
        el("lectura-filtro").tap()
        toca("fila-ma")
        esperarLabel("lectura-filtro", "Filas: 25 de 26")
        XCTAssertEqual(el("lectura-marcador").label, "4 / 4 correctos")
        XCTAssertEqual(cuenta("celda-dimmed"), 0)
        captura("leer-recorregido-con-filtro")

        irA("Progreso")
        // Solo cuenta la primera corrección: 4 intentos, 3 aciertos.
        esperarLabel("progreso-total", "4")
        XCTAssertEqual(el("progreso-acierto").label, "75 %")
        captura("progreso-tras-leer")
    }

    /// 20, 50: corregir vacío avisa; «Mostrar solución» y después corregir no suma al progreso.
    func testLeerSolucionNoCuentaEnProgreso() {
        generarTextoPropio("casa luna")
        toca("btn-corregir")
        esperarLabel("lectura-mensaje", "Escribe tu transcripción antes de corregir.")
        XCTAssertFalse(el("lectura-marcador").exists)

        toca("btn-solucion")
        let respuesta = el("lectura-respuesta")
        respuesta.tap()
        respuesta.typeText("kasa runa")
        toca("btn-corregir")
        esperarLabel("lectura-marcador", "4 / 4 correctos (no cuenta en estadísticas)")
        captura("leer-solucion")

        irA("Progreso")
        XCTAssertTrue(el("progreso-vacio").waitForExistence(timeout: 5))
        XCTAssertEqual(el("progreso-total").label, "0")
    }

    /// 25, 26, 27, 28: filtro con solo la fila A, ronda al azar con ese filtro y filtro vacío.
    func testLeerFiltroDeFilas() {
        irA("Leer")
        el("lectura-filtro").tap()
        let filas = ["ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa", "ga", "za", "da", "ba", "pa",
                     "kya", "sha", "cha", "nya", "hya", "mya", "rya", "gya", "ja", "bya", "pya"]
        filas.forEach { toca("fila-\($0)") }
        esperarLabel("lectura-filtro", "Filas: 1 de 26")

        // Texto propio: ら queda atenuada y no cuenta (27).
        generarTextoPropio("ala")
        XCTAssertEqual(celdas("celda-pending"), ["あ"])
        XCTAssertEqual(celdas("celda-dimmed"), ["ら"])
        let respuesta = el("lectura-respuesta")
        respuesta.tap()
        respuesta.typeText("a")
        toca("btn-corregir")
        esperarLabel("lectura-marcador", "1 / 1 correctos")
        captura("leer-solo-fila-a")

        // Al azar con solo la fila A: o avisa o no hay kana fuera del filtro (25, 26).
        app.segmentedControls["lectura-modo"].buttons["Palabras al azar"].tap()
        toca("btn-nueva-ronda")
        if el("lectura-mensaje").exists {
            XCTAssertEqual(el("lectura-mensaje").label, "Ninguna palabra usa solo las filas elegidas.")
        } else {
            XCTAssertEqual(cuenta("celda-dimmed"), 0)
            XCTAssertTrue(celdas("celda-pending").allSatisfy { "あいうえお".contains($0) })
        }

        // Sin filas: aviso (28).
        toca("fila-a")
        esperarLabel("lectura-filtro", "Filas: 0 de 26")
        toca("btn-nueva-ronda")
        esperarLabel("lectura-mensaje", "Selecciona al menos una fila del silabario.")
        captura("leer-sin-filas")

        irA("Progreso")
        esperarLabel("progreso-total", "1")
    }

    /// Cambiar de modo descarta la práctica: no debe quedar el marcador de la corrección anterior.
    func testLeerCambiarDeModoDescartaLaCorreccion() {
        irA("Leer")
        XCTAssertTrue(app.staticTexts.matching(identifier: "celda-pending").firstMatch.waitForExistence(timeout: 5))
        let respuesta = el("lectura-respuesta")
        respuesta.tap()
        respuesta.typeText("a")
        toca("btn-corregir")
        XCTAssertTrue(el("lectura-marcador").waitForExistence(timeout: 5))
        // «Texto propio» no genera práctica: no debe quedar nada de la corrección anterior.
        app.segmentedControls["lectura-modo"].buttons["Texto propio"].tap()
        XCTAssertEqual(cuenta("celda-ok") + cuenta("celda-error"), 0, "Siguen las celdas de la práctica descartada")
        captura("leer-tras-cambiar-modo")
        XCTAssertFalse(el("lectura-marcador").exists, "Cambiar de modo dejó el marcador de la práctica descartada")
    }

    // MARK: - Progreso

    /// 48, 51, 24: progreso vacío, ronda de 5, separación por silabario y borrado.
    func testProgresoTarjetasYSilabario() {
        irA("Progreso")
        XCTAssertTrue(el("progreso-vacio").waitForExistence(timeout: 5))
        XCTAssertEqual(el("progreso-total").label, "0")
        // El progreso se sincroniza con Deepy: no hay botón para borrarlo desde la app.
        XCTAssertFalse(el("btn-borrar").exists, "No debe existir «Borrar todo el progreso»")
        XCTAssertTrue(el("sync-estado").label.hasPrefix("Sin conectar"), el("sync-estado").label)

        irA("Tarjetas")
        configurarTarjetas(tamano: "5")
        toca("btn-empezar")
        jugarRonda(de: 5)
        esperarLabel("resumen-titulo", "¡Ronda completada!")

        irA("Progreso")
        esperarLabel("progreso-total", "5")
        XCTAssertEqual(el("progreso-acierto").label, "100 %")
        XCTAssertEqual(el("progreso-hoy").label, "5")
        XCTAssertEqual(cuenta("progreso-celda"), 5)
        captura("progreso-hiragana")

        app.segmentedControls["progreso-silabario"].buttons["Katakana"].tap()
        XCTAssertTrue(el("progreso-vacio").waitForExistence(timeout: 5), "Se mezclaron los silabarios (51)")
        app.segmentedControls["progreso-silabario"].buttons["Hiragana"].tap()
        XCTAssertEqual(cuenta("progreso-celda"), 5)


    }

    /// 41, 48, 52: lo respondido se guarda en el acto al salir a mitad de ronda, y salir cancela la pausa.
    func testProgresoGuardaAlSalirAMitadDeRonda() {
        toca("btn-empezar")
        jugarRonda(de: 10, hasta: 2)
        esperarLabel("progreso", "3/10")
        let kana = el("tarjeta-kana").label
        toca("btn-nolase")
        esperarLabel("tarjeta-feedback", "\(kana) se lee \(romaji(kana))")
        // «Salir» durante la pausa la cancela: no debe avanzar la ronda nueva.
        toca("btn-salir")
        toca("btn-empezar")
        esperarLabel("progreso", "1/10")
        esperar(el("cronometro"), NSPredicate { objeto, _ in
            Self.segundos((objeto as? XCUIElement)?.label ?? "") > 1.6
        }, timeout: 10)
        XCTAssertEqual(el("progreso").label, "1/10", "La pausa de la ronda anterior avanzó la nueva")
        XCTAssertEqual(el("vidas").label, "Vidas: 3 de 3")
        XCTAssertEqual(el("tarjeta-feedback").label, " ")
        toca("btn-salir")

        irA("Progreso")
        esperarLabel("progreso-total", "3")
        XCTAssertEqual(el("progreso-acierto").label, "66 %")
    }

    // MARK: - iPad

    /// 55: en horizontal, Leer muestra kana y respuesta a la vez; una ronda de tarjetas cabe entera.
    func testIPadHorizontalLeerYTarjetas() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Solo en iPad")
        XCUIDevice.shared.orientation = .landscapeLeft

        generarTextoPropio("casa luna")
        let respuesta = el("lectura-respuesta")
        respuesta.tap()
        respuesta.typeText("kasa")
        let primera = app.staticTexts.matching(identifier: "celda-pending").firstMatch
        XCTAssertTrue(respuesta.isHittable, "La respuesta no es visible en horizontal")
        XCTAssertTrue(primera.isHittable, "El kana no es visible mientras se escribe")
        XCTAssertLessThan(abs(respuesta.frame.minY - primera.frame.minY), 200,
                          "Kana y respuesta no están lado a lado")
        let teclado = XCTAttachment(string: "Teclados en pantalla: \(app.keyboards.count)")
        teclado.name = "ipad-teclado"
        teclado.lifetime = .keepAlways
        add(teclado)
        captura("ipad-leer-horizontal")
        respuesta.typeText(" runa")
        toca("btn-corregir")
        esperarLabel("lectura-marcador", "4 / 4 correctos")

        irA("Tarjetas")
        configurarTarjetas(tamano: "5")
        toca("btn-empezar")
        captura("ipad-tarjeta-horizontal")
        // Se espera a que acabe la animación del teclado antes de exigir que kana y campo se vean a la vez.
        esperar(el("tarjeta-input"), NSPredicate(format: "hittable == true"))
        XCTAssertTrue(el("tarjeta-kana").isHittable, "El kana no es visible en horizontal con el teclado abierto")
        jugarRonda(de: 5)
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        XCTAssertEqual(el("resumen-aciertos").label, "5/5")
        captura("ipad-resumen-horizontal")
    }

    // MARK: - Oráculo kana → romaji (independiente de la app)

    private static let hiragana: [(String, String)] = """
    あ a い i う u え e お o か ka き ki く ku け ke こ ko さ sa し shi す su せ se そ so \
    た ta ち chi つ tsu て te と to な na に ni ぬ nu ね ne の no は ha ひ hi ふ fu へ he ほ ho \
    ま ma み mi む mu め me も mo や ya ゆ yu よ yo ら ra り ri る ru れ re ろ ro わ wa を wo ん n
    """.split(separator: " ").chunked2()

    /// Variantes kunrei que la app debe aceptar (32).
    private static let variantes = ["し": "si", "ち": "ti", "つ": "tu", "ふ": "hu"]

    private func romaji(_ kana: String) -> String {
        guard let r = Self.hiragana.first(where: { $0.0 == kana })?.1 else {
            XCTFail("Kana fuera del oráculo: \(kana)")
            return ""
        }
        return r
    }

    // MARK: - Ayudas

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func toca(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id)
        // waitForExistence sondea cada segundo aunque el elemento ya esté: primero se mira directo.
        XCTAssertTrue(e.exists || e.waitForExistence(timeout: 5), "No aparece \(id)", file: file, line: line)
        e.tap()
    }

    private func cuenta(_ id: String) -> Int {
        app.descendants(matching: .any).matching(identifier: id).count
    }

    /// Kana de las celdas con ese estado (el label combinado empieza por el kana).
    private func celdas(_ id: String) -> [String] {
        app.staticTexts.matching(identifier: id).allElementsBoundByIndex.map {
            String($0.label.split(separator: ",").first ?? "")
        }
    }

    private func vacio(_ campo: XCUIElement, _ leido: Any? = nil) -> Bool {
        let valor = (leido ?? campo.value) as? String ?? ""
        return valor.isEmpty || valor == campo.placeholderValue
    }

    private func esperar(_ elemento: XCUIElement, _ predicado: NSPredicate, timeout: TimeInterval = 5,
                         file: StaticString = #filePath, line: UInt = #line) {
        let espera = XCTNSPredicateExpectation(predicate: predicado, object: elemento)
        let resultado = XCTWaiter().wait(for: [espera], timeout: timeout)
        XCTAssertEqual(resultado, .completed, "Tiempo agotado esperando \(predicado) en \(elemento)",
                       file: file, line: line)
    }

    private func esperarLabel(_ id: String, _ valor: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id)
        // Comprobación inmediata: la espera con predicado sondea cada segundo y la pausa de error dura 1,2 s.
        if e.exists, e.label == valor { return }
        esperar(e, NSPredicate(format: "exists == true AND label == %@", valor), timeout: timeout,
                file: file, line: line)
    }

    private func irA(_ pestana: String, file: StaticString = #filePath, line: UInt = #line) {
        // iPhone: barra de pestañas. iPad en horizontal: barra lateral (celdas) por `.sidebarAdaptable`.
        let candidatos = [app.tabBars.buttons[pestana], app.cells[pestana], app.buttons[pestana].firstMatch]
        let boton = candidatos.first(where: \.exists) ?? candidatos[2]
        if !boton.isHittable { ocultarTeclado() }
        XCTAssertTrue(boton.isHittable, "La pestaña \(pestana) no se puede tocar: el teclado la tapa y no hay forma de cerrarlo",
                      file: file, line: line)
        boton.tap()
    }

    /// Si el teclado tapa la barra de pestañas, se intenta cerrar deslizando la página, como haría el usuario.
    private func ocultarTeclado() {
        guard app.keyboards.count > 0 else { return }
        app.scrollViews.firstMatch.swipeDown()
        if app.keyboards.count > 0 { app.scrollViews.firstMatch.swipeUp() }
    }

    private func configurarTarjetas(silabario: String? = nil, mazo: String? = nil, tamano: String? = nil) {
        for (id, opcion) in [("config-silabario", silabario), ("config-mazo", mazo), ("config-tamano", tamano)] {
            guard let opcion else { continue }
            let boton = app.segmentedControls[id].buttons[opcion]
            XCTAssertTrue(boton.waitForExistence(timeout: 5), "No existe la opción \(opcion) en \(id)")
            boton.tap()
            XCTAssertTrue(boton.isSelected)
        }
    }

    /// Responde bien las tarjetas `1...hasta` de una ronda de `total`. Devuelve los kana mostrados.
    @discardableResult
    private func jugarRonda(de total: Int, hasta: Int? = nil, variantes: Bool = false,
                            antesDeResponder: ((Int) -> Void)? = nil) -> [String] {
        let campo = el("tarjeta-input")
        return (1 ... (hasta ?? total)).map { i in
            esperarLabel("progreso", "\(i)/\(total)")
            let kana = el("tarjeta-kana").label
            antesDeResponder?(i)
            let lectura = variantes ? Self.variantes[kana] ?? romaji(kana) : romaji(kana)
            campo.typeText(lectura)
            return kana
        }
    }

    /// Escribe una respuesta mala y Enter; comprueba la lectura mostrada durante la pausa y la vida restada.
    private func fallarConEnter(_ campo: XCUIElement, vidasRestantes: Int,
                                file: StaticString = #filePath, line: UInt = #line) -> String {
        let kana = el("tarjeta-kana").label
        campo.typeText("x\n")
        esperarLabel("tarjeta-feedback", "\(kana) se lee \(romaji(kana))", file: file, line: line)
        XCTAssertEqual(el("vidas").label, "Vidas: \(vidasRestantes) de 3", file: file, line: line)
        return kana
    }

    private func generarTextoPropio(_ texto: String) {
        irA("Leer")
        app.segmentedControls["lectura-modo"].buttons["Texto propio"].tap()
        let campo = el("lectura-texto")
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.tap()
        campo.typeText(texto)
        XCTAssertEqual((campo.value as? String)?.lowercased(), texto)
        toca("btn-generar")
    }

    private func captura(_ nombre: String) {
        let adjunto = XCTAttachment(screenshot: app.screenshot())
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }

    private static func segundos(_ texto: String) -> Double {
        Double(texto.replacingOccurrences(of: " s", with: "")) ?? -1
    }

    private func segundos(_ texto: String) -> Double { Self.segundos(texto) }
}

private extension Array where Element == Substring {
    /// ["あ", "a", "い", "i"] → [("あ", "a"), ("い", "i")]
    func chunked2() -> [(String, String)] {
        stride(from: 0, to: count - 1, by: 2).map { (String(self[$0]), String(self[$0 + 1])) }
    }
}

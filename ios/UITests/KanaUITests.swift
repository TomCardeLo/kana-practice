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

    private func relanzarConServidor(_ url: String = servidor, extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-uitest", "-uitest-conexion"] + extra
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
        // 5 de la ronda + el intento válido que este iPhone subió en la prueba de Y7 y ahora recupera.
        XCTAssertEqual(el("progreso-total").label, "6")
        captura("sincronizacion-iphone")
    }

    /// Y7: un intento que el servidor rechaza (fecha de 2025) se aparta con aviso y no bloquea al resto.
    /// Corre en el iPhone después de la subida: si bloqueara, la ronda nueva quedaría pendiente.
    func testSincronizacionApartaUnIntentoRechazado() throws {
        try XCTSkipIf(esIPad, "Solo en el iPhone, para no alterar lo que baja el iPad")
        relanzarConServidor(extra: ["-uitest-intento-rechazado"])
        escribirPassword("password-de-prueba")
        esperarConectado()
        irA("Progreso")
        XCTAssertTrue(el("sync-apartados").waitForExistence(timeout: 20), "El intento rechazado no se apartó con aviso")
        esperar(el("sync-estado"), NSPredicate(format: "label BEGINSWITH 'Sincronizado'"), timeout: 20)
        XCTAssertFalse(el("sync-pendientes").exists, "Un intento rechazado bloqueó la cola (Y7)")
        XCTAssertEqual(el("progreso-total").label, "2", "Los dos intentos siguen en este equipo")
        captura("sincronizacion-apartado")
    }

    /// Reinstalar (almacén vacío, mismo identificador de equipo) recupera también el historial propio: la ronda
    /// de 5 y el intento válido de la prueba de Y7, que subió este mismo iPhone. Corre después de la subida.
    func testSincronizacionTrasReinstalarRecuperaLoPropio() throws {
        try XCTSkipIf(esIPad, "El iPhone recupera lo que él mismo subió")
        relanzarConServidor()
        escribirPassword("password-de-prueba")
        esperarConectado()
        irA("Progreso")
        esperarLabel("progreso-total", "6", timeout: 20)
        captura("sincronizacion-reinstalar")
    }

    /// Y2: el iPad baja lo que subió el iPhone (la ronda de 5 y el intento válido de la prueba de Y7, no el
    /// rechazado), y volver a sincronizar no lo duplica.
    func testSincronizacionBajaEnElIPad() throws {
        try XCTSkipUnless(esIPad, "El iPad baja lo que subió el iPhone en testSincronizacionSubeDesdeElIPhone")
        relanzarConServidor()
        escribirPassword("password-de-prueba")
        esperarConectado()
        irA("Progreso")
        esperarLabel("progreso-total", "6", timeout: 20)
        XCTAssertEqual(el("progreso-hoy").label, "6")
        toca("btn-sincronizar")
        esperar(el("sync-estado"), NSPredicate(format: "label BEGINSWITH 'Sincronizado'"), timeout: 20)
        XCTAssertEqual(el("progreso-total").label, "6", "Volver a sincronizar duplicó intentos (Y2)")
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

    /// 64, 66, 67, 72–75: con 3 días de racha y 45 respuestas hoy, una ronda de 5 cumple la meta a mitad de
    /// la última tarjeta; el aviso sale una sola vez, el combo aparece desde 3 y un error lo borra.
    func testRachaMetaDelDiaYCombo() {
        app.terminate()
        app.launchArguments = ["-uitest", "-uitest-racha"]
        app.launch()
        esperarLabel("racha-dias", "3 días de racha")
        XCTAssertEqual(el("racha-hoy").label, "Hoy 45/50")
        XCTAssertFalse(el("aviso-celebracion").exists, "Lo sembrado no es de ahora: no se anuncia (71)")

        configurarTarjetas(tamano: "5")
        toca("btn-empezar")
        jugarRonda(de: 5) { i in
            if i <= 3 { XCTAssertFalse(self.el("combo").exists, "Combo antes de 3 aciertos (73)") }
            if i == 4 { self.esperarLabel("combo", "Combo de 3") }
        }
        XCTAssertTrue(el("aviso-celebracion").waitForExistence(timeout: 5), "No se anunció la meta al llegar a 50 (64)")
        XCTAssertEqual(el("aviso-celebracion").label, "Meta del día cumplida. Racha de 4 días.")
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        let mensaje = el("resumen-mensaje").label
        XCTAssertTrue(mensaje.lowercased().contains("récord"), "Primera ronda completa = récord nuevo: \(mensaje) (67)")
        captura("racha-meta-cumplida")
        sleep(1)
        XCTAssertEqual(el("resumen-mensaje").label, mensaje, "El mensaje cambió al redibujar (74)")

        // Otra ronda el mismo día: el aviso no se repite; un error borra el combo.
        esperar(el("aviso-celebracion"), NSPredicate(format: "exists == false"), timeout: 8)
        toca("btn-otra")
        jugarRonda(de: 5, hasta: 3)
        esperarLabel("progreso", "4/5")
        esperarLabel("combo", "Combo de 3")
        _ = fallarOpcion(vidasRestantes: 2)
        XCTAssertFalse(el("combo").exists, "El combo siguió tras un error (66, 73)")
        esperarLabel("progreso", "5/5")
        responder()
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        XCTAssertFalse(el("resumen-mensaje").label.contains("Ronda perfecta"), "Llamó perfecta a una ronda con un error (67)")
        XCTAssertFalse(el("aviso-celebracion").waitForExistence(timeout: 2), "La meta se anunció dos veces el mismo día (64)")

        app.buttons["Cambiar configuración"].tap()
        esperarLabel("racha-dias", "4 días de racha")
        XCTAssertEqual(el("racha-hoy").label, "Hoy 50/50")
        irA("Progreso")
        esperarLabel("racha-dias", "4 días de racha")
        XCTAssertTrue(el("progreso-sin-dominadas").exists)
        captura("racha-progreso")
    }

    /// Tutor (fase 3b): al terminar una ronda se sube la sesión y Deepy (con Claude simulado) la comenta. Un fallo
    /// de Claude se ve con «Reintentar». Solo en el iPad: corre después de las pruebas de sincronización de los dos
    /// equipos, que cuentan las respuestas del servidor.
    func testTutorComentaLaRondaYSeReintenta() throws {
        try XCTSkipIf(!esIPad, "Corre en el iPad, después de las pruebas de sincronización")
        relanzarConServidor()
        escribirPassword("password-de-prueba")
        esperarConectado()
        // La siguiente llamada a Claude responde 529 (sobrecarga).
        var peticion = URLRequest(url: URL(string: "http://127.0.0.1:3109/__fallar")!)
        peticion.httpMethod = "POST"
        let listo = expectation(description: "falso")
        URLSession.shared.dataTask(with: peticion) { _, _, _ in listo.fulfill() }.resume()
        wait(for: [listo], timeout: 5)

        irA("Tarjetas")
        configurarTarjetas(tamano: "5")
        toca("btn-empezar")
        jugarRonda(de: 5)
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        XCTAssertTrue(el("tutor-error").waitForExistence(timeout: 20), "El fallo del tutor no se mostró")
        XCTAssertTrue(el("tutor-error").label.contains("HTTP 529"), el("tutor-error").label)
        captura("tutor-error")
        toca("btn-tutor-reintentar")
        esperarLabel("tutor-comentario", "Comentario del tutor de prueba: vas bien con la fila de la a.", timeout: 20)
        captura("tutor-comentario")
    }

    /// 96–100, 102: Palabras propone los vencidos y los nuevos de vocabulario (10) y de kanji (5), cada uno con su tope;
    /// las 4 opciones nunca repiten significado; al fallar se marca la correcta y, en kanji, se ven sus lecturas;
    /// todo cuenta para la meta del día pero no entra en las estadísticas de kana.
    func testPalabrasVocabularioYKanji() {
        app.terminate()
        app.launchArguments = ["-uitest", "-uitest-palabras"]
        app.launch()
        irA("Palabras")
        esperarLabel("palabras-plan", "2 por repasar · 10 nuevas")
        captura("palabras-plan")
        toca("btn-repasar-palabras")
        let vistas = jugarPreguntas(12, fallar: [1])
        // Los 2 vencidos y exactamente las 10 primeras nuevas del orden fijo (mismo en cualquier equipo, 97).
        XCTAssertEqual(Set(vistas), Self.primerasNuevas(sin: ["会う|あう", "青|あお"]).union(["会う", "青"]))
        esperarLabel("resumen-titulo", "¡Repaso terminado!", timeout: 6)
        XCTAssertEqual(el("resumen-aciertos").label, "11/12")
        captura("palabras-resumen")
        toca("btn-volver")
        esperarLabel("palabras-plan", "0 por repasar · 0 nuevas")

        app.segmentedControls["palabras-tipo"].buttons["Kanji"].tap()
        esperarLabel("palabras-plan", "1 por repasar · 5 nuevas")
        toca("btn-repasar-palabras")
        let kanji = jugarPreguntas(6, fallar: [2]) { i in
            if i == 2 {
                XCTAssertTrue(self.el("pregunta-detalle").label.contains("音") || self.el("pregunta-detalle").label.contains("訓"),
                              "Al fallar un kanji no se ven sus lecturas")
                self.captura("kanji-error")
            }
        }
        XCTAssertTrue(kanji.contains("一"))
        esperarLabel("resumen-titulo", "¡Repaso terminado!", timeout: 6)
        XCTAssertEqual(el("resumen-aciertos").label, "5/6")
        toca("btn-volver")
        esperarLabel("palabras-plan", "0 por repasar · 0 nuevas")

        irA("Progreso")
        esperarLabel("racha-hoy", "Hoy 18/50")  // cuentan para la meta (100)
        XCTAssertTrue(el("progreso-vacio").exists, "Vocabulario o kanji se colaron en las estadísticas de kana (100)")
        XCTAssertEqual(el("progreso-total").label, "0", "Las respuestas de vocabulario cuentan en el total de kana (100)")
    }

    /// 81–83: «Hoy» propone los vencidos y 10 nuevos en orden de tabla; fallar no corta la sesión ni quita vidas,
    /// no hay récord, y al volver no queda nada pendiente (lo fallado vuelve mañana).
    func testRepasoHoySinVidasYPlanActualizado() {
        app.terminate()
        app.launchArguments = ["-uitest", "-uitest-repaso"]
        app.launch()
        esperarLabel("hoy-plan", "4 por repasar · 10 nuevas")
        toca("btn-repasar")
        var vistos: [String] = []
        for i in 1 ... 14 {
            esperarLabel("progreso", "\(i)/14", timeout: 6)
            let kana = el("tarjeta-kana").label
            vistos.append(kana)
            if i <= 3 { toca("btn-nolase") } else { responder() }
            XCTAssertFalse(el("vidas").exists, "El repaso no tiene vidas (82)")
        }
        XCTAssertEqual(Set(vistos), ["い", "か", "さ", "そ", "う", "え", "お", "き", "く", "け", "こ", "し", "す", "せ"])
        esperarLabel("resumen-titulo", "¡Repaso terminado!", timeout: 6)
        XCTAssertEqual(el("resumen-aciertos").label, "11/14")
        XCTAssertFalse(el("resumen-record").exists, "El repaso no guarda récord (82)")
        XCTAssertFalse(el("btn-otra").exists)
        captura("repaso-terminado")
        toca("btn-volver")
        esperarLabel("hoy-plan", "0 por repasar · 0 nuevas")
        XCTAssertTrue(el("hoy-nada").exists)
        captura("repaso-nada-pendiente")
    }

    /// 71: la meta que el otro equipo ya cumplió hoy baja justo después de una ronda aquí: no se anuncia
    /// como si la hubieran cumplido estas 5 respuestas.
    func testRachaNoAnunciaLoQueBajaDelOtroEquipo() {
        app.terminate()
        app.launchArguments = ["-uitest", "-uitest-baja-tarde"]
        app.launch()
        configurarTarjetas(tamano: "5")
        toca("btn-empezar")
        jugarRonda(de: 5)
        esperarLabel("resumen-titulo", "¡Ronda completada!")
        app.buttons["Cambiar configuración"].tap()
        esperarLabel("racha-hoy", "Hoy 50/50", timeout: 20)
        XCTAssertFalse(el("aviso-celebracion").exists, "Se anunció como propia la meta que bajó del otro equipo (71)")
        captura("racha-baja-del-otro-equipo")
    }

    /// 33, 34, 35, 39: Enter vacío, sílaba a medias, error con Enter, «No la sé» y fin sin vidas.
    func testTarjetasErroresHastaQuedarseSinVidas() {
        configurarTarjetas(tamano: "10")
        toca("btn-empezar")
        esperarLabel("progreso", "1/10")

        // Opción equivocada: muestra la lectura correcta y resta una vida (34); la correcta y la elegida se
        // distinguen sin color (92).
        let correcta1 = romaji(el("tarjeta-kana").label)
        var errores = [fallarOpcion(vidasRestantes: 2)]
        let marcadas = opciones().map { ($0.label, $0.value as? String ?? "") }
        XCTAssertEqual(marcadas.first { $0.1 == "correcta" }?.0, correcta1, "No se marca la correcta: \(marcadas)")
        XCTAssertEqual(marcadas.filter { $0.1 == "tu elección" }.count, 1, "No se marca la elegida: \(marcadas)")
        esperarLabel("progreso", "2/10")
        esperarLabel("tarjeta-feedback", " ")

        // «No la sé» resta una vida; durante la pausa las opciones no se pueden tocar (91).
        let kana2 = el("tarjeta-kana").label
        toca("btn-nolase")
        let activas = opciones().filter(\.isEnabled).count
        XCTAssertEqual(el("tarjeta-feedback").label, "\(kana2) se lee \(romaji(kana2))", "La pausa terminó antes de comprobarla")
        XCTAssertEqual(activas, 0, "Las opciones se pueden tocar durante la pausa (91)")
        XCTAssertEqual(el("vidas").label, "Vidas: 1 de 3")
        XCTAssertFalse(el("btn-nolase").isEnabled)
        errores.append(kana2)
        esperarLabel("progreso", "3/10")
        XCTAssertEqual(el("vidas").label, "Vidas: 1 de 3")

        // Tercer error: la lectura se ve antes del resumen.
        errores.append(fallarOpcion(vidasRestantes: 0))
        captura("tarjetas-error-opcion")
        esperarLabel("resumen-titulo", "Sin vidas", timeout: 5)
        XCTAssertEqual(el("resumen-aciertos").label, "0/10")
        XCTAssertEqual(el("resumen-record").label, "Completa la ronda para registrar un récord.")
        let chips = app.staticTexts.matching(identifier: "resumen-errores").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(chips, errores.map { "\($0) → \(romaji($0))" })
        captura("tarjetas-sin-vidas")
    }

    /// 91: un doble toque sobre la correcta cuenta una sola respuesta (el segundo toque caería en la tarjeta siguiente).
    func testTarjetasDobleToqueCuentaUnaVez() {
        configurarTarjetas(tamano: "10")
        toca("btn-empezar")
        esperarLabel("progreso", "1/10")
        let correcta = romaji(el("tarjeta-kana").label)
        opciones().first { $0.label == correcta }!.doubleTap()
        esperarLabel("progreso", "2/10")
        sleep(1)
        XCTAssertEqual(el("progreso").label, "2/10", "El segundo toque contó como respuesta de la tarjeta siguiente")
        XCTAssertEqual(el("vidas").label, "Vidas: 3 de 3")
    }

    /// 29, 30, 87–90: el mazo básico completo sale entero y sin repetir; cada tarjeta tiene 4 opciones distintas con
    /// una sola válida (nunca una variante como «si» para し), y la correcta no cae siempre en el mismo sitio.
    func testTarjetasOpcionesDelMazoCompleto() {
        configurarTarjetas(tamano: "Todas (46)")
        toca("btn-empezar")
        var posiciones: Set<Int> = []
        let kanas = jugarRonda(de: 46) { _ in
            let kana = self.el("tarjeta-kana").label
            let etiquetas = self.opciones().map(\.label)
            XCTAssertEqual(Set(etiquetas).count, 4, "Opciones repetidas o de menos para \(kana): \(etiquetas)")
            XCTAssertEqual(etiquetas.filter { $0 == self.romaji(kana) }.count, 1, "La correcta no está una vez: \(etiquetas)")
            if let variante = Self.variantes[kana] { XCTAssertFalse(etiquetas.contains(variante), "\(variante) también vale para \(kana)") }
            posiciones.insert(etiquetas.firstIndex(of: self.romaji(kana)) ?? -1)
        }
        XCTAssertEqual(kanas.sorted(), Self.hiragana.map(\.0).sorted(), "El mazo no coincide con los 46 básicos")
        XCTAssertGreaterThanOrEqual(posiciones.count, 3, "La correcta cae casi siempre en el mismo sitio (90)")
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
        esperar(el("opcion-4"), NSPredicate(format: "hittable == true"))
        XCTAssertTrue(el("tarjeta-kana").isHittable, "El kana no es visible en horizontal junto a las opciones")
        // Teclado físico: la tecla del número elige esa opción (93).
        let correcta = romaji(el("tarjeta-kana").label)
        let numero = opciones().firstIndex { $0.label == correcta }! + 1
        app.typeKey("\(numero)", modifierFlags: [])
        esperarLabel("progreso", "2/5")
        jugarRonda(de: 5, desde: 2)
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

    /// Variantes kunrei: nunca deben salir como opción falsa de su kana (88).
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

    /// Oráculo de Palabras, calculado de los mismos datos que usa la app (no de la pantalla).
    private struct Entrada { let id: String; let texto: String; let significado: String; let glosas: [String] }
    private static let entradas: (vocabulario: [Entrada], kanji: [Entrada]) = {
        struct P: Decodable { let id: String; let palabra: String; let lectura: String; let es: [String] }
        struct K: Decodable { let kanji: String; let es: [String] }
        let bundle = Bundle(for: KanaUITests.self)
        func datos(_ nombre: String) -> Data { try! Data(contentsOf: bundle.url(forResource: nombre, withExtension: "json")!) }
        func variantes(_ s: String) -> String { s.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "・") }
        func significado(_ es: [String]) -> String { es.prefix(2).joined(separator: ", ") }
        let v = try! JSONDecoder().decode([P].self, from: datos("vocabulario-n5")).map { p in
            let t = variantes(p.palabra), l = variantes(p.lectura)
            return Entrada(id: p.id, texto: "\(t)|\(l == t ? "" : l)", significado: significado(p.es), glosas: p.es)
        }
        let k = try! JSONDecoder().decode([K].self, from: datos("kanji-n5")).map {
            Entrada(id: $0.kanji, texto: "\($0.kanji)|", significado: significado($0.es), glosas: $0.es)
        }
        return (v, k)
    }()
    private static let porTexto = Dictionary((entradas.vocabulario + entradas.kanji).map { ($0.texto, $0) }) { a, _ in a }

    /// Las 10 primeras palabras nuevas según el orden fijo (FNV-1a de la clave), sin las ya vistas (97).
    private static func primerasNuevas(sin vistas: Set<String>) -> Set<String> {
        func fnv(_ s: String) -> UInt64 { s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 } }
        let orden = entradas.vocabulario.sorted { (fnv($0.id), $0.id) < (fnv($1.id), $1.id) }
        return Set(orden.filter { !vistas.contains($0.id) }.prefix(10).map { String($0.texto.split(separator: "|")[0]) })
    }

    /// Núcleo de un significado para comparar (independiente del de la app): sin paréntesis, tildes ni artículo.
    private static func nucleo(_ g: String) -> Set<String> {
        let sin = g.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Set(sin.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty && !["el", "la", "los", "las", "un", "una"].contains($0) })
    }

    private func preguntaActual(file: StaticString = #filePath, line: UInt = #line) -> Entrada? {
        let lectura = el("pregunta-lectura")
        let clave = "\(el("pregunta-texto").label)|\(lectura.exists ? lectura.label : "")"
        guard let e = Self.porTexto[clave] else { XCTFail("Pregunta fuera del oráculo: \(clave)", file: file, line: line); return nil }
        return e
    }

    /// Responde `total` preguntas; falla las de `fallar` (comprobando el marcado) y acierta las demás. Devuelve los textos.
    @discardableResult
    private func jugarPreguntas(_ total: Int, fallar: Set<Int> = [], tras: ((Int) -> Void)? = nil) -> [String] {
        (1 ... total).map { i in
            esperarLabel("progreso", "\(i)/\(total)", timeout: 6)
            let texto = el("pregunta-texto").label
            guard let entrada = preguntaActual() else { return texto }
            let correcta = entrada.significado
            let etiquetas = opciones().map(\.label)
            XCTAssertEqual(Set(etiquetas).count, 4, "Opciones repetidas para \(texto): \(etiquetas)")
            XCTAssertEqual(etiquetas.filter { $0 == correcta }.count, 1, "La correcta no está una vez para \(texto): \(etiquetas)")
            // Ninguna falsa repite, sin lo accesorio, un significado de la correcta (96, 105).
            let propias = entrada.glosas.map(Self.nucleo).filter { !$0.isEmpty }
            for falsa in etiquetas where falsa != correcta {
                let suyas = falsa.split(separator: ",").map { Self.nucleo(String($0)) }.filter { !$0.isEmpty }
                XCTAssertFalse(propias.contains { p in suyas.contains { $0 == p } },
                               "«\(falsa)» repite un significado de \(texto) (\(correcta))")
            }
            guard let boton = opciones().first(where: { ($0.label == correcta) != fallar.contains(i) }) else { return texto }
            boton.tap()
            if fallar.contains(i) {
                let marcadas = opciones().map { ($0.label, $0.value as? String ?? "") }
                XCTAssertEqual(marcadas.first { $0.1 == "correcta" }?.0, correcta, "No se marca la correcta: \(marcadas)")
            }
            tras?(i)
            return texto
        }
    }

    /// Las 4 opciones de la tarjeta actual, en orden.
    private func opciones() -> [XCUIElement] { (1 ... 4).map { el("opcion-\($0)") } }

    /// Toca la opción correcta (o una equivocada) de la tarjeta actual.
    private func responder(bien: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let correcta = romaji(el("tarjeta-kana").label)
        guard let boton = opciones().first(where: { ($0.label == correcta) == bien }) else {
            return XCTFail("No hay opción \(bien ? "correcta" : "equivocada") para \(correcta)", file: file, line: line)
        }
        boton.tap()
    }

    /// Responde bien las tarjetas `1...hasta` de una ronda de `total`. Devuelve los kana mostrados.
    @discardableResult
    private func jugarRonda(de total: Int, desde: Int = 1, hasta: Int? = nil, antesDeResponder: ((Int) -> Void)? = nil) -> [String] {
        (desde ... (hasta ?? total)).map { i in
            esperarLabel("progreso", "\(i)/\(total)")
            let kana = el("tarjeta-kana").label
            antesDeResponder?(i)
            responder()
            return kana
        }
    }

    /// Toca una opción equivocada; comprueba la lectura mostrada durante la pausa y la vida restada.
    private func fallarOpcion(vidasRestantes: Int, file: StaticString = #filePath, line: UInt = #line) -> String {
        let kana = el("tarjeta-kana").label
        responder(bien: false, file: file, line: line)
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

import XCTest

/// Roda no simulador: confirma que o modelo do sistema está disponível e que o motor responde pelo app.
/// Siri e Atalhos não são testados aqui: no simulador do iOS 27 o App Shortcut aparece nos Atalhos,
/// mas tocar nele não chama o perform(), e a Siri por texto (siriService) não abre. Prova só no aparelho.
final class DemoUITests: XCTestCase {
    func testAppAnswers() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Ask"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'answer'")).firstMatch
            .waitForExistence(timeout: 120))
    }
}

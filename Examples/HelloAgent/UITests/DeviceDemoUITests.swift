import XCTest

/// Só no aparelho: dirige os Atalhos e a Siri como um usuário faria, para gravar a demo.
/// (No simulador do iOS 27 o App Shortcut não executa; ver o README.)
final class DeviceDemoUITests: XCTestCase {
    func testShortcutsTile() throws {
        let atalhos = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        atalhos.launch()
        sleep(3)
        if atalhos.buttons["Continue"].exists { atalhos.buttons["Continue"].tap(); sleep(2) }
        for _ in 0..<3 where !atalhos.buttons["Hello Agent"].exists {
            if atalhos.buttons["BackButton"].exists { atalhos.buttons["BackButton"].tap(); sleep(2) } else { break }
        }
        atalhos.buttons["Hello Agent"].tap()
        sleep(3)
        atalhos.staticTexts["Ask the agent"].tap()
        sleep(35)
    }

    func testSiri() {
        XCUIDevice.shared.press(.home)
        sleep(2)
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: "Ask Hello Agent")
        sleep(40)
        for id in ["com.apple.springboard", "com.apple.siri"] {
            print("ARVORE-\(id)\n" + XCUIApplication(bundleIdentifier: id).debugDescription + "\nARVORE-FIM")
        }
    }
}

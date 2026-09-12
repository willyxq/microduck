import XCTest

/// Drives the L1 field-admin path on the simulator.
/// iOS Simulator has no BLE; App-sim must already be up on ws://127.0.0.1:17432.
final class ConnectSimTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testDiscoverShowsDuckSim() {
        XCTAssertTrue(app.buttons["duck-sim"].waitForExistence(timeout: 5), "discover must list duck-sim")
        saveShot("l1-discover")
    }

    func testPinThenHome() {
        XCTAssertTrue(app.buttons["duck-sim"].waitForExistence(timeout: 5))
        app.buttons["duck-sim"].tap()

        let pin = app.textFields["pin-input"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "PIN field")
        saveShot("l1-pin")
        pin.tap()
        pin.typeText("000000")
        app.buttons["pin-submit"].tap()

        let connected = app.staticTexts["现场连接"]
        XCTAssertTrue(connected.waitForExistence(timeout: 12), "home after PIN — is App-sim up?")
        XCTAssertTrue(app.staticTexts["duck-sim"].exists)
        XCTAssertTrue(app.buttons["nav-home"].exists)
        XCTAssertTrue(app.buttons["nav-interact"].exists)
        XCTAssertTrue(app.buttons["nav-models"].exists)
        XCTAssertTrue(app.buttons["nav-settings"].exists)
        XCTAssertFalse(app.staticTexts["手柄"].exists)
        saveShot("l1-home")

        app.buttons["nav-interact"].tap()
        XCTAssertTrue(app.buttons["stop"].waitForExistence(timeout: 3))
        saveShot("l1-interact")

        app.buttons["nav-models"].tap()
        XCTAssertTrue(app.staticTexts["行走 Walk"].waitForExistence(timeout: 3))
        saveShot("l1-models")

        app.buttons["nav-settings"].tap()
        XCTAssertTrue(app.buttons["wifi-scan"].waitForExistence(timeout: 3))
        saveShot("l1-settings")
        app.buttons["wifi-scan"].tap()
        XCTAssertTrue(app.buttons["wifi-Pollen"].waitForExistence(timeout: 8), "FakeNet scan")
        XCTAssertTrue(app.buttons["wifi-Cafe"].exists)
        saveShot("l1-wifi-scan")

        app.buttons["wifi-Pollen"].tap()
        let password = app.textFields["wifi-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 3))
        password.tap()
        password.typeText("wrong-key")
        app.buttons["wifi-join"].tap()
        let badKey = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "BadKey")
        ).firstMatch
        XCTAssertTrue(badKey.waitForExistence(timeout: 8), "wrong password must mention BadKey")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        saveShot("l1-wifi-badkey")
    }

    private func saveShot(_ name: String) {
        let dir = URL(fileURLWithPath: "/tmp/harness/ios-uitest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = app.screenshot().pngRepresentation
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
    }
}

import XCTest

final class SwiftFileRunnerUITests: XCTestCase {
    func testSampleCounterIncrementsWhenButtonIsTapped() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Tiny Native App"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Taps: 0"].exists)

        let addButton = app.buttons["Add one"]
        XCTAssertTrue(addButton.exists)
        addButton.tap()

        XCTAssertTrue(app.staticTexts["Taps: 1"].waitForExistence(timeout: 5))
    }
}

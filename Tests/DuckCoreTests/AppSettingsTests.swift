import XCTest
@testable import DuckCore

final class AppSettingsTests: XCTestCase {
    func testDefaultsArePrivacyConservative() {
        let defaults = makeDefaults()
        let store = DuckSettingsStore(defaults: defaults)

        XCTAssertFalse(store.isListening)
        XCTAssertEqual(store.position, .bottomRight)
        XCTAssertEqual(store.sensitivity, .medium)
        XCTAssertFalse(store.launchAtLogin)
    }

    func testSettingsPersistThroughUserDefaults() {
        let defaults = makeDefaults()
        var store = DuckSettingsStore(defaults: defaults)

        store.isListening = true
        store.position = .topLeft
        store.sensitivity = .high
        store.launchAtLogin = true

        store = DuckSettingsStore(defaults: defaults)

        XCTAssertTrue(store.isListening)
        XCTAssertEqual(store.position, .topLeft)
        XCTAssertEqual(store.sensitivity, .high)
        XCTAssertTrue(store.launchAtLogin)
    }

    func testInvalidStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("middle", forKey: DuckSettingsStore.Key.position)
        defaults.set("loud", forKey: DuckSettingsStore.Key.sensitivity)

        let store = DuckSettingsStore(defaults: defaults)

        XCTAssertEqual(store.position, .bottomRight)
        XCTAssertEqual(store.sensitivity, .medium)
    }

    private func makeDefaults(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UserDefaults {
        let suiteName = "dev.saber5656.duck.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults", file: file, line: line)
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

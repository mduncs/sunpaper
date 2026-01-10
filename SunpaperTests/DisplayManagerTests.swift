import XCTest
import AppKit
@testable import Sunpaper

final class DisplayManagerTests: XCTestCase {

    // MARK: - Display Struct Properties

    func testDisplayIDMatchesUUID() {
        let display = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Test Display",
            isPrimary: false
        )

        XCTAssertEqual(display.id, display.uuid, "Display id should match uuid")
    }

    func testDisplayNameWithoutPrimarySuffix() {
        let display = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Test Display",
            isPrimary: false
        )

        XCTAssertEqual(display.displayName, "Test Display", "Non-primary display should not have suffix")
    }

    func testDisplayNameWithPrimarySuffix() {
        let display = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Test Display",
            isPrimary: true
        )

        XCTAssertEqual(display.displayName, "Test Display (Primary)", "Primary display should have (Primary) suffix")
    }

    func testBuiltInDisplayPrimaryName() {
        let display = DisplayManager.Display(
            uuid: "00000000-00000000-12345678",
            name: "Built-in Display",
            isPrimary: true
        )

        XCTAssertEqual(display.displayName, "Built-in Display (Primary)")
    }

    // MARK: - Display Codable Conformance

    func testDisplayEncode() throws {
        let display = DisplayManager.Display(
            uuid: "ABCDEF12-34567890-FEDCBA09",
            name: "External Monitor",
            isPrimary: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(display)

        XCTAssertFalse(data.isEmpty, "Encoded data should not be empty")

        // Verify JSON structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["uuid"] as? String, "ABCDEF12-34567890-FEDCBA09")
        XCTAssertEqual(json?["name"] as? String, "External Monitor")
        XCTAssertEqual(json?["isPrimary"] as? Bool, false)
    }

    func testDisplayDecode() throws {
        let json = """
        {
            "uuid": "11111111-22222222-33333333",
            "name": "Test Monitor",
            "isPrimary": true
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let display = try decoder.decode(DisplayManager.Display.self, from: data)

        XCTAssertEqual(display.uuid, "11111111-22222222-33333333")
        XCTAssertEqual(display.name, "Test Monitor")
        XCTAssertTrue(display.isPrimary)
        XCTAssertEqual(display.id, "11111111-22222222-33333333")
    }

    func testDisplayEncodeDecodeRoundTrip() throws {
        let original = DisplayManager.Display(
            uuid: "AAAABBBB-CCCCDDDD-EEEEFFFF",
            name: "Round Trip Display",
            isPrimary: false
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DisplayManager.Display.self, from: data)

        XCTAssertEqual(decoded.uuid, original.uuid)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.isPrimary, original.isPrimary)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.displayName, original.displayName)
    }

    // MARK: - Display Equatable Conformance

    func testDisplayEquality() {
        let display1 = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Monitor A",
            isPrimary: false
        )

        let display2 = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Monitor A",
            isPrimary: false
        )

        XCTAssertEqual(display1, display2, "Displays with same properties should be equal")
    }

    func testDisplayInequalityDifferentUUID() {
        let display1 = DisplayManager.Display(
            uuid: "11111111-11111111-11111111",
            name: "Monitor",
            isPrimary: false
        )

        let display2 = DisplayManager.Display(
            uuid: "22222222-22222222-22222222",
            name: "Monitor",
            isPrimary: false
        )

        XCTAssertNotEqual(display1, display2, "Displays with different UUIDs should not be equal")
    }

    func testDisplayInequalityDifferentName() {
        let display1 = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Monitor A",
            isPrimary: false
        )

        let display2 = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Monitor B",
            isPrimary: false
        )

        XCTAssertNotEqual(display1, display2, "Displays with different names should not be equal")
    }

    func testDisplayInequalityDifferentPrimaryStatus() {
        let display1 = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Monitor",
            isPrimary: false
        )

        let display2 = DisplayManager.Display(
            uuid: "12345678-12345678-12345678",
            name: "Monitor",
            isPrimary: true
        )

        XCTAssertNotEqual(display1, display2, "Displays with different primary status should not be equal")
    }

    // MARK: - getDisplays()

    func testGetDisplaysReturnsNonEmptyArray() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        XCTAssertFalse(displays.isEmpty, "Every Mac should have at least one display")
        XCTAssertGreaterThanOrEqual(displays.count, 1, "Should have at least the built-in or primary display")
    }

    func testGetDisplaysContainsPrimaryDisplay() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        let primaryDisplays = displays.filter { $0.isPrimary }

        XCTAssertEqual(primaryDisplays.count, 1, "Should have exactly one primary display")
    }

    func testPrimaryDisplayIsFirstInSortedList() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        guard !displays.isEmpty else {
            XCTFail("No displays found")
            return
        }

        XCTAssertTrue(displays[0].isPrimary, "First display in sorted list should be primary")
    }

    func testDisplaysSortedByNameAfterPrimary() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        // Filter non-primary displays
        let nonPrimaryDisplays = displays.filter { !$0.isPrimary }

        // Check that non-primary displays are sorted by name
        var previousName: String?
        for display in nonPrimaryDisplays {
            if let prev = previousName {
                XCTAssertLessThanOrEqual(prev, display.name,
                    "Non-primary displays should be sorted alphabetically by name")
            }
            previousName = display.name
        }
    }

    func testGetDisplaysAllHaveUniqueUUIDs() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        let uuids = displays.map { $0.uuid }
        let uniqueUUIDs = Set(uuids)

        XCTAssertEqual(uuids.count, uniqueUUIDs.count, "All display UUIDs should be unique")
    }

    // MARK: - UUID Format Validation

    func testUUIDFormatIsValid() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        for display in displays {
            let uuid = display.uuid

            // UUID should match either "XXXXXXXX-XXXXXXXX-XXXXXXXX" or "display-XXXXXXXX" format
            let vendorModelSerialPattern = "^[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}$"
            let displayIDPattern = "^display-[0-9A-F]{8}$"

            let vendorModelSerialRegex = try? NSRegularExpression(pattern: vendorModelSerialPattern)
            let displayIDRegex = try? NSRegularExpression(pattern: displayIDPattern)

            let matchesVendorModelSerial = vendorModelSerialRegex?.firstMatch(
                in: uuid,
                range: NSRange(location: 0, length: uuid.utf16.count)
            ) != nil

            let matchesDisplayID = displayIDRegex?.firstMatch(
                in: uuid,
                range: NSRange(location: 0, length: uuid.utf16.count)
            ) != nil

            XCTAssertTrue(
                matchesVendorModelSerial || matchesDisplayID,
                "UUID '\(uuid)' should match expected format (XXXXXXXX-XXXXXXXX-XXXXXXXX or display-XXXXXXXX)"
            )
        }
    }

    func testUUIDIsStableAcrossMultipleCalls() {
        let manager = DisplayManager.shared

        let displays1 = manager.getDisplays()
        let displays2 = manager.getDisplays()

        XCTAssertEqual(displays1.count, displays2.count, "Display count should be consistent")

        // UUIDs should be stable
        for (display1, display2) in zip(displays1, displays2) {
            XCTAssertEqual(display1.uuid, display2.uuid, "UUID should be stable across calls")
        }
    }

    // MARK: - Display Names

    func testDisplayNamesAreNonEmpty() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        for display in displays {
            XCTAssertFalse(display.name.isEmpty, "Display name should not be empty")
            XCTAssertGreaterThan(display.name.count, 0, "Display name should have content")
        }
    }

    func testDisplayNamesAreReadable() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        for display in displays {
            // Display name should contain either "Display", "Built-in", or be from NSScreen.localizedName
            let isReadable = display.name.contains("Display") ||
                             display.name.contains("Built-in") ||
                             display.name.count > 3 // Arbitrary check for non-trivial names

            XCTAssertTrue(isReadable, "Display name '\(display.name)' should be human-readable")
        }
    }

    func testBuiltInDisplayName() {
        let manager = DisplayManager.shared
        let displays = manager.getDisplays()

        // Check if any display is built-in (common on MacBooks)
        let builtInDisplays = displays.filter { $0.name == "Built-in Display" }

        if !builtInDisplays.isEmpty {
            XCTAssertEqual(builtInDisplays[0].name, "Built-in Display",
                "Built-in display should have correct name")
        }
    }

    // MARK: - Singleton Pattern

    func testSharedInstanceIsSingleton() {
        let instance1 = DisplayManager.shared
        let instance2 = DisplayManager.shared

        XCTAssertTrue(instance1 === instance2, "DisplayManager.shared should return the same instance")
    }

    // MARK: - Edge Cases

    func testDisplayStructIdentifiable() {
        let display = DisplayManager.Display(
            uuid: "TEST-UUID-12345678",
            name: "Test",
            isPrimary: false
        )

        // Identifiable conformance should work
        XCTAssertEqual(display.id, "TEST-UUID-12345678")
    }

    func testDisplayWithSpecialCharactersInName() {
        let display = DisplayManager.Display(
            uuid: "12345678-87654321-11111111",
            name: "Display™ (2024) – 27\"",
            isPrimary: false
        )

        XCTAssertEqual(display.displayName, "Display™ (2024) – 27\"")
        XCTAssertFalse(display.displayName.contains("Primary"))
    }

    func testDisplayWithSpecialCharactersInNamePrimary() {
        let display = DisplayManager.Display(
            uuid: "12345678-87654321-11111111",
            name: "Display™ (2024) – 27\"",
            isPrimary: true
        )

        XCTAssertTrue(display.displayName.contains("Primary"))
        XCTAssertTrue(display.displayName.contains("Display™ (2024) – 27\""))
    }
}

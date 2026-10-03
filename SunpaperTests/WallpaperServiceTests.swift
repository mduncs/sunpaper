import XCTest
import AppKit
import ImageIO
@testable import Sunpaper

@MainActor
final class WallpaperServiceTests: XCTestCase {
    // These tests must not call setWallpaper(assetID:) because that mutates the
    // user's real macOS wallpaper Index.plist.

    func testCancelledRedownloadPreservesWorkingFileAndRemovesTemporaryFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("asset.mov")
        let temporary = directory.appendingPathComponent("download.tmp")
        try Data("working".utf8).write(to: destination)
        try Data("replacement".utf8).write(to: temporary)
        let remote = URL(string: "https://example.com/aerial.mov")!
        let service = WallpaperService(videosDirectoryURL: directory) { url in
            // Model cancellation just as URLSession finishes delivering a file.
            withUnsafeCurrentTask { $0?.cancel() }
            return (temporary, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let task = Task { try await service.redownloadAerial(assetID: "asset", from: remote) }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(try Data(contentsOf: destination), Data("working".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testIdleLayoutIsReplacedByRequiredLinkedEntry() throws {
        let plan = try plan(assetID: "new", plist: [
            "AllSpacesAndDisplays": ["Type": "idle"]
        ])
        let write = try XCTUnwrap(plan.mutations.first { $0.keyPath == "AllSpacesAndDisplays" })
        XCTAssertTrue(write.isRequired, "A failed layout write must not report a successful aerial change")
        let result = try applying(plan, to: ["AllSpacesAndDisplays": ["Type": "idle"]])
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: nil), "new")
    }

    func testPerDisplayPlanTranslatesPersistedIdentifierToWallpaperStoreUUID() throws {
        let persisted = "00000610-0000A001-00000000"
        let native = "2C2AA742-7DE3-4C67-85E2-8D5D5466C641"
        let other = "92C5959A-666B-43A0-B77C-70D2D25C0174"
        let fixture: [String: Any] = [
            "AllSpacesAndDisplays": "$null",
            "Displays": [native: entry("old"), other: entry("other")]
        ]
        let plan = try WallpaperService.shared.planAerialWallpaperChange(
            assetID: "asset", displayUUID: persisted, plistData: data(fixture),
            displayUUIDMapping: [persisted: native])
        XCTAssertEqual(plan.target, .display(uuid: native))
        XCTAssertFalse(plan.mutations.contains { $0.keyPath.contains(persisted) || "\($0.value)".contains(persisted) })
        let result = try applying(plan, to: fixture)
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: native), "asset")
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: other), "other")
    }

    // MARK: - Index.plist layout (verified live on macOS 27)

    private let mainDisplay = "66B343D4-A76F-4225-A97B-8AF122701588"
    private let sideDisplay = "158F8AC5-0E8B-4BF5-91EF-4EF39D82FD6F"

    func testAllDisplaysChangeReplacesPerDisplayLayout() throws {
        let fixture: [String: Any] = [
            "AllSpacesAndDisplays": "$null",
            "Displays": [sideDisplay: entry("old")],
            "Spaces": ["": ["Default": entry("old"), "Displays": [sideDisplay: entry("old")]]],
            "SystemDefault": entry("old")
        ]
        let result = try applying(try plan(assetID: "new", plist: fixture), to: fixture)

        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: nil), "new")
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: sideDisplay), "new",
                       "An all-displays entry overrides display and Space entries")
        XCTAssertEqual(WallpaperStoreLayout.assetID(inEntry: result["SystemDefault"]), "new")
    }

    func testFirstPerDisplayChangeKeepsOtherDisplaysOnTheirWallpaper() throws {
        let fixture: [String: Any] = [
            "AllSpacesAndDisplays": entry("old"),
            "Displays": [String: Any](),
            "Spaces": [String: Any]()
        ]
        let plan = try plan(assetID: "new", display: sideDisplay, connected: [mainDisplay, sideDisplay], plist: fixture)
        let result = try applying(plan, to: fixture)

        XCTAssertEqual(result["AllSpacesAndDisplays"] as? String, "$null")
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: sideDisplay), "new")
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: mainDisplay), "old")
        XCTAssertNil(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: nil),
                     "Per-display entries are not one wallpaper everywhere")
        XCTAssertEqual(plan.mutations.last?.keyPath, "AllSpacesAndDisplays",
                       "A failed display write must leave the all-displays wallpaper in charge")
    }

    func testPerDisplayChangeDropsSpacesDerivedFromThatDisplay() throws {
        let fixture: [String: Any] = [
            "AllSpacesAndDisplays": "$null",
            "Displays": [mainDisplay: entry("main"), sideDisplay: entry("side")],
            "Spaces": [
                "": ["Default": entry("main"), "Displays": [mainDisplay: entry("main")]],
                "FDFEC175-6F7E-4C76-A588-2C5FECD5C155": ["Default": entry("side"), "Displays": [sideDisplay: entry("side")]]
            ]
        ]
        let result = try applying(try plan(assetID: "new", display: sideDisplay, plist: fixture), to: fixture)

        let spaces = try XCTUnwrap(result["Spaces"] as? [String: Any])
        XCTAssertEqual(Array(spaces.keys), [""], "Only the Space derived from the changed display is dropped")
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: sideDisplay), "new")
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: mainDisplay), "main")
    }

    func testPerDisplayChangeCreatesMissingDisplayDictionary() throws {
        let fixture: [String: Any] = ["AllSpacesAndDisplays": entry("old")]
        let result = try applying(try plan(assetID: "new", display: sideDisplay, plist: fixture), to: fixture)
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: result, displayUUID: sideDisplay), "new")
    }

    func testSpaceEntriesWinOverDisplayEntriesWhenReadingCurrentWallpaper() {
        let plist: [String: Any] = [
            "AllSpacesAndDisplays": "$null",
            "Displays": [sideDisplay: entry("display")],
            "Spaces": ["S": ["Displays": [sideDisplay: entry("space")]]]
        ]
        XCTAssertEqual(WallpaperStoreLayout.currentAssetID(in: plist, displayUUID: sideDisplay), "space")

        var disagreeing = plist
        disagreeing["Spaces"] = [
            "S1": ["Displays": [sideDisplay: entry("a")]],
            "S2": ["Displays": [sideDisplay: entry("b")]]
        ]
        XCTAssertNil(WallpaperStoreLayout.currentAssetID(in: disagreeing, displayUUID: sideDisplay))
    }

    func testNonAerialChoiceIsNotReportedAsAnAerial() {
        let photo: [String: Any] = ["Type": "linked", "Linked": ["Content": ["Choices": [[
            "Provider": "com.apple.wallpaper.choice.image",
            "Configuration": Data("not an aerial".utf8),
            "Files": [Any]()
        ]]]]]
        XCTAssertNil(WallpaperStoreLayout.currentAssetID(in: ["AllSpacesAndDisplays": photo], displayUUID: nil))
    }

    private func entry(_ assetID: String) -> [String: Any] {
        let configuration = try! PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID], format: .binary, options: 0)
        return WallpaperStoreLayout.linkedEntry(choice: [
            "Configuration": configuration,
            "Files": [Any](),
            "Provider": "com.apple.wallpaper.choice.aerials"
        ], reusing: nil, at: Date(timeIntervalSince1970: 1_790_000_000))
    }

    private func data(_ plist: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    private func plan(assetID: String, display: String? = nil, connected: [String] = [],
                      plist: [String: Any]) throws -> WallpaperOperationPlan {
        try WallpaperService.shared.planAerialWallpaperChange(
            assetID: assetID, displayUUID: display, plistData: data(plist),
            connectedDisplayUUIDs: connected)
    }

    /// Runs the planned plutil commands against a temporary copy, never the real store.
    private func applying(_ plan: WallpaperOperationPlan, to plist: [String: Any]) throws -> [String: Any] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
        try data(plist).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        for mutation in plan.mutations {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            process.arguments = mutation.plutilArguments(plistURL: url)
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "plutil failed: \(mutation.purpose)")
        }
        return try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    func testFailedRedownloadPreservesWorkingFileAndCleansTemporaryDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("asset.mov")
        let temporary = directory.appendingPathComponent("download.tmp")
        try Data("working".utf8).write(to: destination)
        try Data("server error".utf8).write(to: temporary)
        let service = WallpaperService(videosDirectoryURL: directory) { url in
            (temporary, HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        do {
            try await service.redownloadAerial(assetID: "asset", from: URL(string: "https://example.com/aerial.mov")!)
            XCTFail("Expected HTTP failure")
        } catch WallpaperError.downloadFailed {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(try Data(contentsOf: destination), Data("working".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testSuccessfulRedownloadReplacesWorkingFileAndConsumesTemporaryDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("asset.mov")
        let temporary = directory.appendingPathComponent("download.tmp")
        try Data("working".utf8).write(to: destination)
        try Data("replacement".utf8).write(to: temporary)
        let service = WallpaperService(videosDirectoryURL: directory) { url in
            (temporary, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try await service.redownloadAerial(assetID: "asset", from: URL(string: "https://example.com/aerial.mov")!)
        XCTAssertEqual(try Data(contentsOf: destination), Data("replacement".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testCustomWallpaperRejectsUnreadableAndAnimatedImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unreadable = directory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: unreadable)
        XCTAssertThrowsError(try WallpaperService.shared.validateCustomWallpaper(path: unreadable.path))
        let animated = directory.appendingPathComponent("animation.png")
        // The extension alone cannot distinguish a still image from an animation.
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(animated as CFURL, "com.compuserve.gif" as CFString, 2, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for color in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)] {
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            CGImageDestinationAddImage(output, try XCTUnwrap(context.makeImage()), nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(output))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(animated as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        XCTAssertThrowsError(try WallpaperService.shared.validateCustomWallpaper(path: animated.path))
    }

    // MARK: - WallpaperError Description Tests

    func testPlistNotFoundErrorDescription() {
        let error = WallpaperError.plistNotFound

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains("Wallpaper configuration file not found") ?? false,
            "Error should mention plist not found"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("System Settings") ?? false,
            "Error should suggest System Settings as solution"
        )
    }

    func testPlistUpdateFailedErrorDescription() {
        let keyPath = "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration"
        let error = WallpaperError.plistUpdateFailed(keyPath: keyPath)

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains(keyPath) ?? false,
            "Error should include the failing keyPath"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("Failed to update") ?? false,
            "Error should mention update failure"
        )
    }

    func testAgentRestartFailedErrorDescription() {
        let error = WallpaperError.agentRestartFailed

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains("WallpaperAgent") ?? false,
            "Error should mention WallpaperAgent"
        )
    }

    func testCustomFileNotFoundErrorDescription() {
        let path = "/Users/test/wallpaper.jpg"
        let error = WallpaperError.customFileNotFound(path: path)

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains(path) ?? false,
            "Error should include the file path"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("not found") ?? false,
            "Error should mention file not found"
        )
    }

    func testCustomVideoNotSupportedErrorDescription() {
        let error = WallpaperError.customVideoNotSupported

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains("video") ?? false,
            "Error should mention video"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("not yet supported") ?? false,
            "Error should indicate feature not ready"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("aerials") ?? false,
            "Error should suggest using built-in aerials"
        )
    }

    func testUnsupportedFormatErrorDescription() {
        let ext = "webp"
        let error = WallpaperError.unsupportedFormat(ext: ext)

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains(ext) ?? false,
            "Error should include the unsupported extension"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("Unsupported") ?? false,
            "Error should mention unsupported format"
        )
    }

    func testNoMainScreenErrorDescription() {
        let error = WallpaperError.noMainScreen

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains("main screen") ?? false,
            "Error should mention main screen"
        )
    }

    func testAerialNotDownloadedErrorDescription() {
        let assetID = "4C108785-A7BA-422E-9C79-B0129F1D5550"
        let error = WallpaperError.aerialNotDownloaded(assetID: assetID)

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains("not downloaded") ?? false,
            "Error should mention not downloaded"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("System Settings") ?? false,
            "Error should suggest System Settings"
        )
        XCTAssertTrue(
            error.errorDescription?.contains(assetID) ?? false,
            "Error should include the asset ID"
        )
    }

    func testDownloadFailedErrorDescription() {
        let assetID = "4C108785-A7BA-422E-9C79-B0129F1D5550"
        let error = WallpaperError.downloadFailed(assetID: assetID)

        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(
            error.errorDescription?.contains("Failed to download") ?? false,
            "Error should mention download failure"
        )
        XCTAssertTrue(
            error.errorDescription?.contains(assetID) ?? false,
            "Error should include the asset ID"
        )
    }

    // MARK: - LocalizedError Conformance

    func testErrorDescriptionIsUserFriendly() {
        // All error descriptions should be human-readable, not technical jargon
        let errors: [WallpaperError] = [
            .plistNotFound,
            .plistUpdateFailed(keyPath: "test.path"),
            .agentRestartFailed,
            .customFileNotFound(path: "/test.jpg"),
            .customVideoNotSupported,
            .unsupportedFormat(ext: "xyz"),
            .noMainScreen,
            .aerialNotDownloaded(assetID: "test-asset-id"),
            .downloadFailed(assetID: "test-asset-id")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")

            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "Error description should not be empty")

            // User-friendly descriptions should be complete sentences or clear phrases
            XCTAssertGreaterThan(
                description.count,
                10,
                "Error description should be reasonably detailed: \(description)"
            )
        }
    }

    // MARK: - Custom Wallpaper Validation Tests

    func testCustomWallpaperRejectsNonExistentFile() {
        let service = WallpaperService.shared
        let nonExistentPath = "/tmp/nonexistent_\(UUID().uuidString).jpg"

        XCTAssertThrowsError(try service.validateCustomWallpaper(path: nonExistentPath)) { error in
            guard let wallpaperError = error as? WallpaperError else {
                XCTFail("Expected WallpaperError, got \(type(of: error))")
                return
            }

            if case .customFileNotFound(let path) = wallpaperError {
                XCTAssertEqual(path, nonExistentPath, "Error should include the path")
            } else {
                XCTFail("Expected customFileNotFound error, got \(wallpaperError)")
            }
        }
    }

    func testCustomWallpaperRejectsUnsupportedImageFormats() {
        // Create temp file with unsupported extension
        let tempDir = FileManager.default.temporaryDirectory
        let unsupportedFormats = ["webp", "svg", "gif", "ico", "psd"]

        for ext in unsupportedFormats {
            let tempFile = tempDir.appendingPathComponent("test.\(ext)")

            // Create empty file
            FileManager.default.createFile(atPath: tempFile.path, contents: Data())
            defer {
                try? FileManager.default.removeItem(at: tempFile)
            }

            let service = WallpaperService.shared

            XCTAssertThrowsError(try service.validateCustomWallpaper(path: tempFile.path)) { error in
                guard let wallpaperError = error as? WallpaperError else {
                    XCTFail("Expected WallpaperError for .\(ext), got \(type(of: error))")
                    return
                }

                if case .unsupportedFormat(let errorExt) = wallpaperError {
                    XCTAssertEqual(errorExt, ext, "Error should include the extension")
                } else {
                    XCTFail("Expected unsupportedFormat error for .\(ext), got \(wallpaperError)")
                }
            }
        }
    }

    func testCustomWallpaperAcceptsSupportedImageFormats() throws {
        // Test that supported formats don't throw unsupportedFormat or customFileNotFound
        let tempDir = FileManager.default.temporaryDirectory
        let supportedFormats = ["heic", "jpg", "jpeg", "png", "tiff", "bmp"]

        for ext in supportedFormats {
            let tempFile = tempDir.appendingPathComponent("test.\(ext)")

            try writeStillImage(to: tempFile)
            defer {
                try? FileManager.default.removeItem(at: tempFile)
            }

            let service = WallpaperService.shared

            do {
                try service.validateCustomWallpaper(path: tempFile.path)
                // If it succeeds, that's fine (we have a screen)
            } catch let error as WallpaperError {
                // Should not be format/file errors
                switch error {
                case .unsupportedFormat:
                    XCTFail(".\(ext) should be supported but got unsupportedFormat error")
                case .customFileNotFound:
                    XCTFail(".\(ext) file exists but got customFileNotFound error")
                case .customVideoNotSupported:
                    XCTFail(".\(ext) is an image but got customVideoNotSupported error")
                case .customImageUnreadable:
                    XCTFail(".\(ext) contains a readable still image")
                case .transitionInProgress, .noMainScreen, .plistNotFound, .plistUpdateFailed, .agentRestartFailed, .aerialNotDownloaded, .downloadFailed:
                    // These are acceptable - system/environment issues, not format issues
                    break
                }
            } catch {
                // NSWorkspace might throw its own errors - that's fine for this test
                // We're only checking that our validation logic doesn't reject supported formats
            }
        }
    }

    func testCustomWallpaperRejectsVideoFormats() {
        let tempDir = FileManager.default.temporaryDirectory
        let videoFormats = ["mov", "mp4", "m4v"]

        for ext in videoFormats {
            let tempFile = tempDir.appendingPathComponent("test.\(ext)")

            // Create empty file
            FileManager.default.createFile(atPath: tempFile.path, contents: Data())
            defer {
                try? FileManager.default.removeItem(at: tempFile)
            }

            let service = WallpaperService.shared

            XCTAssertThrowsError(try service.validateCustomWallpaper(path: tempFile.path)) { error in
                guard let wallpaperError = error as? WallpaperError else {
                    XCTFail("Expected WallpaperError for .\(ext), got \(type(of: error))")
                    return
                }

                if case .customVideoNotSupported = wallpaperError {
                    // Expected
                } else {
                    XCTFail("Expected customVideoNotSupported for .\(ext), got \(wallpaperError)")
                }
            }
        }
    }

    // MARK: - Extension Parsing Tests

    func testFileExtensionIsCaseInsensitive() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let service = WallpaperService.shared

        // Test uppercase extension
        let uppercaseFile = tempDir.appendingPathComponent("test.JPG")
        try writeStillImage(to: uppercaseFile)
        defer {
            try? FileManager.default.removeItem(at: uppercaseFile)
        }

        // Should not throw unsupportedFormat
        do {
            try service.validateCustomWallpaper(path: uppercaseFile.path)
        } catch let error as WallpaperError {
            switch error {
            case .unsupportedFormat:
                XCTFail(".JPG should be recognized as supported (case insensitive)")
            case .noMainScreen, .plistNotFound, .plistUpdateFailed, .agentRestartFailed:
                // System issues are fine
                break
            default:
                // Other errors might occur from NSWorkspace
                break
            }
        } catch {
            // NSWorkspace errors are fine
        }

        // Test mixed case
        let mixedFile = tempDir.appendingPathComponent("test.JpEg")
        try writeStillImage(to: mixedFile)
        defer {
            try? FileManager.default.removeItem(at: mixedFile)
        }

        do {
            try service.validateCustomWallpaper(path: mixedFile.path)
        } catch let error as WallpaperError {
            switch error {
            case .unsupportedFormat:
                XCTFail(".JpEg should be recognized as supported (case insensitive)")
            case .noMainScreen, .plistNotFound, .plistUpdateFailed, .agentRestartFailed:
                break
            default:
                break
            }
        } catch {
            // NSWorkspace errors are fine
        }
    }

    // MARK: - Singleton Tests

    private func writeStillImage(to url: URL) throws {
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        let image = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        CGImageDestinationAddImage(output, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
    }

    func testSharedInstanceIsSingleton() {
        let instance1 = WallpaperService.shared
        let instance2 = WallpaperService.shared

        XCTAssertTrue(instance1 === instance2, "shared should return same instance")
    }

    // MARK: - Error Equality Tests

    func testErrorCasesAreDistinct() {
        let errors: [WallpaperError] = [
            .plistNotFound,
            .plistUpdateFailed(keyPath: "test"),
            .agentRestartFailed,
            .customFileNotFound(path: "/test"),
            .customVideoNotSupported,
            .unsupportedFormat(ext: "xyz"),
            .noMainScreen,
            .aerialNotDownloaded(assetID: "test-asset"),
            .downloadFailed(assetID: "test-asset")
        ]

        // Each error should have a unique description
        var descriptions = Set<String>()
        for error in errors {
            if let desc = error.errorDescription {
                XCTAssertFalse(
                    descriptions.contains(desc),
                    "Error descriptions should be unique: \(desc)"
                )
                descriptions.insert(desc)
            }
        }

        XCTAssertEqual(descriptions.count, errors.count, "All errors should have unique descriptions")
    }
}

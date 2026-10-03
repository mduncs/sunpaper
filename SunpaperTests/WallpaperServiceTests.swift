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

    func testIdleModeRecoveryWriteIsRequired() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "AllSpacesAndDisplays": ["Type": "idle"]
        ], format: .binary, options: 0)
        let plan = try WallpaperService.shared.planAerialWallpaperChange(assetID: "asset", plistData: data)
        let modeWrite = try XCTUnwrap(plan.mutations.first { $0.keyPath == "AllSpacesAndDisplays.Type" })
        XCTAssertTrue(modeWrite.isRequired, "A failed mode switch must not report a successful aerial change")
    }

    func testPerDisplayPlanTranslatesPersistedIdentifierToWallpaperStoreUUID() throws {
        let persisted = "00000610-0000A001-00000000"
        let native = "2C2AA742-7DE3-4C67-85E2-8D5D5466C641"
        let other = "92C5959A-666B-43A0-B77C-70D2D25C0174"
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "AllSpacesAndDisplays": ["Type": "individual"],
            "Displays": [native: [:], other: [:]]
        ], format: .binary, options: 0)
        let plan = try WallpaperService.shared.planAerialWallpaperChange(
            assetID: "asset", displayUUID: persisted, plistData: data,
            displayUUIDMapping: [persisted: native])
        XCTAssertEqual(plan.target, .display(uuid: native))
        XCTAssertEqual(plan.configurationKeyPaths, [.desktopConfiguration(for: native)])
        XCTAssertFalse(plan.mutations.contains { $0.keyPath.contains(persisted) || $0.keyPath.contains(other) })
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

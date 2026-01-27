import XCTest
import AppKit
@testable import Sunpaper

final class WallpaperServiceTests: XCTestCase {

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
            .aerialNotDownloaded(assetID: "test-asset-id")
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

        XCTAssertThrowsError(try service.setCustomWallpaper(path: nonExistentPath)) { error in
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

            XCTAssertThrowsError(try service.setCustomWallpaper(path: tempFile.path)) { error in
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

    func testCustomWallpaperAcceptsSupportedImageFormats() {
        // Test that supported formats don't throw unsupportedFormat or customFileNotFound
        let tempDir = FileManager.default.temporaryDirectory
        let supportedFormats = ["heic", "jpg", "jpeg", "png", "tiff", "bmp"]

        for ext in supportedFormats {
            let tempFile = tempDir.appendingPathComponent("test.\(ext)")

            // Create empty file
            FileManager.default.createFile(atPath: tempFile.path, contents: Data())
            defer {
                try? FileManager.default.removeItem(at: tempFile)
            }

            let service = WallpaperService.shared

            do {
                try service.setCustomWallpaper(path: tempFile.path)
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
                case .noMainScreen, .plistNotFound, .plistUpdateFailed, .agentRestartFailed, .aerialNotDownloaded:
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

            XCTAssertThrowsError(try service.setCustomWallpaper(path: tempFile.path)) { error in
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

    func testFileExtensionIsCaseInsensitive() {
        let tempDir = FileManager.default.temporaryDirectory
        let service = WallpaperService.shared

        // Test uppercase extension
        let uppercaseFile = tempDir.appendingPathComponent("test.JPG")
        FileManager.default.createFile(atPath: uppercaseFile.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: uppercaseFile)
        }

        // Should not throw unsupportedFormat
        do {
            try service.setCustomWallpaper(path: uppercaseFile.path)
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
        FileManager.default.createFile(atPath: mixedFile.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: mixedFile)
        }

        do {
            try service.setCustomWallpaper(path: mixedFile.path)
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
            .aerialNotDownloaded(assetID: "test-asset")
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

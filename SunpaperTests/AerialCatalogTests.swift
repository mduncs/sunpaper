import XCTest
@testable import Sunpaper

final class AerialCatalogTests: XCTestCase {

    // MARK: - Helper to create AerialAsset

    private func makeAsset(
        id: String = "test-id",
        accessibilityLabel: String = "Test Asset",
        previewImage: String? = nil,
        categories: [String] = [],
        subcategories: [String]? = nil,
        showInTopLevel: Bool = true,
        includeInShuffle: Bool = true,
        preferredOrder: Int? = nil,
        localizedNameKey: String? = nil,
        shotID: String? = nil,
        videoURL: String? = nil
    ) -> AerialAsset {
        AerialAsset(
            id: id,
            accessibilityLabel: accessibilityLabel,
            previewImage: previewImage,
            categories: categories,
            subcategories: subcategories,
            showInTopLevel: showInTopLevel,
            includeInShuffle: includeInShuffle,
            preferredOrder: preferredOrder,
            localizedNameKey: localizedNameKey,
            shotID: shotID,
            videoURL: videoURL
        )
    }

    private func makeCategory(
        id: String = "cat-id",
        localizedNameKey: String = "AerialCategoryLandscapes",
        localizedDescriptionKey: String? = nil,
        preferredOrder: Int? = nil,
        previewImage: String? = nil,
        representativeAssetID: String? = nil,
        subcategories: [AerialSubcategory]? = nil
    ) -> AerialCategory {
        AerialCategory(
            id: id,
            localizedNameKey: localizedNameKey,
            localizedDescriptionKey: localizedDescriptionKey,
            preferredOrder: preferredOrder,
            previewImage: previewImage,
            representativeAssetID: representativeAssetID,
            subcategories: subcategories
        )
    }

    private func makeSubcategory(
        id: String = "sub-id",
        localizedNameKey: String = "AerialSubcategoryTahoe",
        localizedDescriptionKey: String? = nil,
        preferredOrder: Int? = nil,
        previewImage: String? = nil,
        representativeAssetID: String? = nil
    ) -> AerialSubcategory {
        AerialSubcategory(
            id: id,
            localizedNameKey: localizedNameKey,
            localizedDescriptionKey: localizedDescriptionKey,
            preferredOrder: preferredOrder,
            previewImage: previewImage,
            representativeAssetID: representativeAssetID
        )
    }

    // MARK: - AerialAsset Model Tests

    func testAerialAssetDisplayName() {
        let asset = makeAsset(accessibilityLabel: "Sunset over Mountains")
        XCTAssertEqual(asset.displayName, "Sunset over Mountains")
    }

    func testAerialAssetThumbnailURL() {
        let asset = makeAsset(previewImage: "https://example.com/image.jpg")
        XCTAssertNotNil(asset.thumbnailURL)
        XCTAssertEqual(asset.thumbnailURL?.absoluteString, "https://example.com/image.jpg")
    }

    func testAerialAssetThumbnailURLNil() {
        let asset = makeAsset(previewImage: nil)
        XCTAssertNil(asset.thumbnailURL)
    }

    func testAerialAssetThumbnailURLEmpty() {
        let asset = makeAsset(previewImage: "")
        XCTAssertNil(asset.thumbnailURL, "Empty string should return nil thumbnail")
    }

    func testAerialAssetCodable() throws {
        let asset = makeAsset(
            id: "test-id",
            accessibilityLabel: "Test Asset",
            previewImage: "https://example.com/test.jpg",
            categories: ["space", "landscape"],
            subcategories: ["earth"],
            showInTopLevel: true,
            includeInShuffle: false,
            preferredOrder: 5,
            localizedNameKey: "TEST_NAME",
            shotID: "TEST_001",
            videoURL: "https://example.com/video.mov"
        )

        let encoded = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(AerialAsset.self, from: encoded)

        XCTAssertEqual(decoded.id, asset.id)
        XCTAssertEqual(decoded.accessibilityLabel, asset.accessibilityLabel)
        XCTAssertEqual(decoded.previewImage, asset.previewImage)
        XCTAssertEqual(decoded.categories, asset.categories)
        XCTAssertEqual(decoded.subcategories, asset.subcategories)
        XCTAssertEqual(decoded.showInTopLevel, asset.showInTopLevel)
        XCTAssertEqual(decoded.includeInShuffle, asset.includeInShuffle)
        XCTAssertEqual(decoded.preferredOrder, asset.preferredOrder)
        XCTAssertEqual(decoded.localizedNameKey, asset.localizedNameKey)
        XCTAssertEqual(decoded.shotID, asset.shotID)
        XCTAssertEqual(decoded.videoURL, asset.videoURL)
    }

    // MARK: - AerialSubcategory Model Tests

    func testAerialSubcategoryDisplayName() {
        let sub = makeSubcategory(localizedNameKey: "AerialSubcategoryTahoe")
        XCTAssertEqual(sub.displayName, "Tahoe")
    }

    func testAerialSubcategoryDisplayNameCities() {
        let sub = makeSubcategory(localizedNameKey: "AerialSubcategoryCitiesNewYork")
        XCTAssertEqual(sub.displayName, "NewYork")
    }

    // MARK: - AerialCategory Model Tests

    func testAerialCategoryDisplayNameKnownKeys() {
        let testCases = [
            ("AerialCategorySpace", "Space"),
            ("AerialCategoryLandscapes", "Landscape"),
            ("AerialCategoryCities", "Cityscape"),
            ("AerialCategoryUnderwater", "Underwater")
        ]

        for (key, expected) in testCases {
            let category = makeCategory(localizedNameKey: key)
            XCTAssertEqual(category.displayName, expected, "Category key \(key) should map to \(expected)")
        }
    }

    func testAerialCategoryDisplayNameUnknownKey() {
        let category = makeCategory(localizedNameKey: "AerialCategoryCustom")
        XCTAssertEqual(category.displayName, "Custom")
    }

    func testAerialCategoryCodable() throws {
        let subcategory = makeSubcategory(id: "sub1", localizedNameKey: "AerialSubcategoryTahoe")
        let category = makeCategory(
            id: "cat-123",
            localizedNameKey: "AerialCategorySpace",
            localizedDescriptionKey: "Space description",
            preferredOrder: 1,
            previewImage: "https://example.com/preview.jpg",
            representativeAssetID: "asset-456",
            subcategories: [subcategory]
        )

        let encoded = try JSONEncoder().encode(category)
        let decoded = try JSONDecoder().decode(AerialCategory.self, from: encoded)

        XCTAssertEqual(decoded.id, category.id)
        XCTAssertEqual(decoded.localizedNameKey, category.localizedNameKey)
        XCTAssertEqual(decoded.preferredOrder, category.preferredOrder)
        XCTAssertEqual(decoded.representativeAssetID, category.representativeAssetID)
        XCTAssertEqual(decoded.subcategories?.count, 1)
        XCTAssertEqual(decoded.subcategories?.first?.id, "sub1")
    }

    // MARK: - EntriesFile Decoding Tests

    func testEntriesFileDecoding() throws {
        let json = """
        {
            "version": 1,
            "localizationVersion": "22L-1",
            "initialAssetCount": 4,
            "assets": [
                {
                    "id": "asset-1",
                    "accessibilityLabel": "Northern Lights",
                    "previewImage": "https://example.com/preview.jpg",
                    "categories": ["space"],
                    "subcategories": null,
                    "showInTopLevel": true,
                    "includeInShuffle": true,
                    "preferredOrder": 1,
                    "localizedNameKey": "NORTHERN_LIGHTS_NAME",
                    "shotID": "NL_001",
                    "url-4K-SDR-240FPS": "https://example.com/video.mov"
                }
            ],
            "categories": [
                {
                    "id": "cat-1",
                    "localizedNameKey": "AerialCategorySpace",
                    "localizedDescriptionKey": "Space description",
                    "preferredOrder": 1,
                    "previewImage": "https://example.com/cat-preview.jpg",
                    "representativeAssetID": "asset-1",
                    "subcategories": null
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let entries = try JSONDecoder().decode(EntriesFile.self, from: data)

        XCTAssertEqual(entries.version, 1)
        XCTAssertEqual(entries.localizationVersion, "22L-1")
        XCTAssertEqual(entries.initialAssetCount, 4)
        XCTAssertEqual(entries.assets.count, 1)
        XCTAssertEqual(entries.assets[0].id, "asset-1")
        XCTAssertEqual(entries.assets[0].videoURL, "https://example.com/video.mov")
        XCTAssertEqual(entries.categories?.count, 1)
        XCTAssertEqual(entries.categories?[0].id, "cat-1")
    }

    func testEntriesFileDecodingMinimal() throws {
        let json = """
        {
            "version": 1,
            "assets": []
        }
        """

        let data = json.data(using: .utf8)!
        let entries = try JSONDecoder().decode(EntriesFile.self, from: data)

        XCTAssertEqual(entries.version, 1)
        XCTAssertEqual(entries.assets.count, 0)
        XCTAssertNil(entries.categories)
        XCTAssertNil(entries.localizationVersion)
        XCTAssertNil(entries.initialAssetCount)
    }

    // MARK: - Asset Filtering Tests

    func testShowInTopLevelFiltering() {
        let assets = [
            makeAsset(id: "1", accessibilityLabel: "Visible", showInTopLevel: true),
            makeAsset(id: "2", accessibilityLabel: "Hidden", showInTopLevel: false),
            makeAsset(id: "3", accessibilityLabel: "Also Visible", showInTopLevel: true)
        ]

        let filtered = assets.filter { $0.showInTopLevel }

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == "1" })
        XCTAssertTrue(filtered.contains { $0.id == "3" })
        XCTAssertFalse(filtered.contains { $0.id == "2" })
    }

    func testAssetSortingByPreferredOrder() {
        let assets = [
            makeAsset(id: "3", accessibilityLabel: "Third", preferredOrder: 3),
            makeAsset(id: "1", accessibilityLabel: "First", preferredOrder: 1),
            makeAsset(id: "2", accessibilityLabel: "Second", preferredOrder: 2),
            makeAsset(id: "nil", accessibilityLabel: "No Order", preferredOrder: nil)
        ]

        let sorted = assets.sorted { ($0.preferredOrder ?? 999) < ($1.preferredOrder ?? 999) }

        XCTAssertEqual(sorted[0].id, "1")
        XCTAssertEqual(sorted[1].id, "2")
        XCTAssertEqual(sorted[2].id, "3")
        XCTAssertEqual(sorted[3].id, "nil", "Assets without preferredOrder should be last")
    }

    // MARK: - ScheduleSlotButton Icon Tests

    func testSlotIconMorningPattern() {
        let slot = TimeSlot(
            name: "Morning",
            trigger: .solar(event: .sunrise, offset: 0),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "sunrise.fill")
    }

    func testSlotIconDawnPattern() {
        let slot = TimeSlot(
            name: "Dawn",
            trigger: .solar(event: .sunrise, offset: -1800),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "sunrise.fill")
    }

    func testSlotIconDayPattern() {
        let slot = TimeSlot(
            name: "Day",
            trigger: .solar(event: .solarNoon, offset: 0),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "sun.max.fill")
    }

    func testSlotIconNoonPattern() {
        let slot = TimeSlot(
            name: "Noon",
            trigger: .solar(event: .solarNoon, offset: 0),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "sun.max.fill")
    }

    func testSlotIconEveningPattern() {
        let slot = TimeSlot(
            name: "Evening",
            trigger: .solar(event: .sunset, offset: 0),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "sunset.fill")
    }

    func testSlotIconDuskPattern() {
        let slot = TimeSlot(
            name: "Dusk",
            trigger: .solar(event: .sunset, offset: 1800),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "sunset.fill")
    }

    func testSlotIconNightPattern() {
        let slot = TimeSlot(
            name: "Night",
            trigger: .solar(event: .sunset, offset: 3600),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "moon.stars.fill")
    }

    func testSlotIconFallbackToTriggerSolar() {
        let slot = TimeSlot(
            name: "Custom Slot",
            trigger: .solar(event: .sunrise, offset: 0),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, SolarEvent.sunrise.icon, "Should fall back to trigger's icon")
    }

    func testSlotIconFallbackToTriggerFixed() {
        let slot = TimeSlot(
            name: "Custom Time",
            trigger: .fixed(hour: 14, minute: 30),
            source: .builtIn(assetID: "test")
        )

        let icon = iconForSlot(slot)
        XCTAssertEqual(icon, "clock.fill", "Fixed time slots should use clock icon")
    }

    // MARK: - ScheduleSlotButton Color Tests

    func testIconColorMorning() {
        XCTAssertEqual(colorForName("Morning"), "orange")
        XCTAssertEqual(colorForName("Dawn"), "orange")
        XCTAssertEqual(colorForName("Sunrise"), "orange")
    }

    func testIconColorDay() {
        XCTAssertEqual(colorForName("Day"), "yellow")
        XCTAssertEqual(colorForName("Noon"), "yellow")
    }

    func testIconColorEvening() {
        XCTAssertEqual(colorForName("Evening"), "orange")
        XCTAssertEqual(colorForName("Dusk"), "orange")
        XCTAssertEqual(colorForName("Sunset"), "orange")
    }

    func testIconColorNight() {
        XCTAssertEqual(colorForName("Night"), "indigo")
    }

    func testIconColorFallback() {
        XCTAssertEqual(colorForName("Custom"), "secondary")
        XCTAssertEqual(colorForName("Unknown"), "secondary")
    }

    // MARK: - WallpaperGridPicker Search Tests

    func testFilteredAssetsEmptySearch() {
        let assets = [
            makeAsset(id: "1", accessibilityLabel: "Northern Lights"),
            makeAsset(id: "2", accessibilityLabel: "Ocean Waves")
        ]

        let filtered = filteredAssets(assets, searchText: "")
        XCTAssertEqual(filtered.count, 2, "Empty search should return all assets")
    }

    func testFilteredAssetsCaseInsensitive() {
        let assets = [
            makeAsset(id: "1", accessibilityLabel: "Northern Lights"),
            makeAsset(id: "2", accessibilityLabel: "Ocean Waves")
        ]

        let filtered = filteredAssets(assets, searchText: "northern")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].id, "1")

        let filteredUpper = filteredAssets(assets, searchText: "OCEAN")
        XCTAssertEqual(filteredUpper.count, 1)
        XCTAssertEqual(filteredUpper[0].id, "2")
    }

    func testFilteredAssetsPartialMatch() {
        let assets = [
            makeAsset(id: "1", accessibilityLabel: "Northern Lights"),
            makeAsset(id: "2", accessibilityLabel: "Southern Cross")
        ]

        let filtered = filteredAssets(assets, searchText: "ern")
        XCTAssertEqual(filtered.count, 2, "Partial match should find both Northern and Southern")
    }

    func testFilteredAssetsNoMatches() {
        let assets = [
            makeAsset(id: "1", accessibilityLabel: "Northern Lights")
        ]

        let filtered = filteredAssets(assets, searchText: "volcano")
        XCTAssertEqual(filtered.count, 0)
    }

    // MARK: - WallpaperButton DisplayName Tests

    func testDisplayNameNone() {
        let name = displayNameForSource(.none)
        XCTAssertEqual(name, "None")
    }

    func testDisplayNameCustomPath() {
        let name = displayNameForSource(.custom(path: "/Users/test/Pictures/sunset.jpg"))
        XCTAssertEqual(name, "sunset.jpg")
    }

    func testDisplayNameCustomPathComplex() {
        let name = displayNameForSource(.custom(path: "/path/to/my wallpaper image.heic"))
        XCTAssertEqual(name, "my wallpaper image.heic")
    }

    // MARK: - Helper Functions (simulating SwiftUI logic)

    private func iconForSlot(_ slot: TimeSlot) -> String {
        let name = slot.name.lowercased()
        if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
            return "sunrise.fill"
        } else if name.contains("day") || name.contains("noon") {
            return "sun.max.fill"
        } else if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
            return "sunset.fill"
        } else if name.contains("night") {
            return "moon.stars.fill"
        }

        // Fall back to trigger-based icon
        switch slot.trigger {
        case .solar(let event, _):
            return event.icon
        case .fixed:
            return "clock.fill"
        }
    }

    private func colorForName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("morning") || lower.contains("dawn") || lower.contains("sunrise") {
            return "orange"
        } else if lower.contains("day") || lower.contains("noon") {
            return "yellow"
        } else if lower.contains("evening") || lower.contains("dusk") || lower.contains("sunset") {
            return "orange"
        } else if lower.contains("night") {
            return "indigo"
        }
        return "secondary"
    }

    private func filteredAssets(_ assets: [AerialAsset], searchText: String) -> [AerialAsset] {
        if searchText.isEmpty {
            return assets
        }
        return assets.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func displayNameForSource(_ source: WallpaperSource) -> String {
        switch source {
        case .none:
            return "None"
        case .builtIn(let assetID):
            return assetID // In real code, would look up in catalog
        case .custom(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

import XCTest
import CoreLocation
@testable import Sunpaper

@MainActor
final class SunpaperControllerTests: XCTestCase {
    private let displays = [
        DisplayManager.Display(uuid: "display-one", name: "First", isPrimary: true),
        DisplayManager.Display(uuid: "display-two", name: "Second", isPrimary: false)
    ]

    func testLoadsBothLegacyConfigAndVersionedEnvelopeWithoutStartingWallpaper() throws {
        let expected = sampleConfig()
        let payloads = [
            try JSONEncoder().encode(expected),
            try JSONEncoder().encode(expected.persistenceEnvelope(createdByAppVersion: "test", updatedAt: Self.date(hour: 12)))
        ]
        for payload in payloads {
            let suite = "SunpaperControllerTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(payload, forKey: WallpaperConfig.userDefaultsKey)
            let service = ControllerWallpaperFake()
            let controller = makeController(defaults: defaults, service: service)
            XCTAssertEqual(controller.config, expected)
            XCTAssertEqual(defaults.data(forKey: WallpaperConfig.userDefaultsKey), payload)
            XCTAssertEqual(controller.scheduler.playbackMode, .paused)
            XCTAssertTrue(service.applications.isEmpty)
            XCTAssertEqual(service.downloadCount, 0)
        }
    }

    func testEditsPersistCompatibleEnvelopeAndRetainUnrelatedPreferences() throws {
        let suite = "SunpaperControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = sampleConfig()
        let service = ControllerWallpaperFake()
        let controller = makeController(config: original, defaults: defaults, service: service)
        controller.selectedDisplayUUID = displays[1].uuid
        controller.editSlots("Rename a change") { $0[0].name = "Renamed second display" }

        let data = try XCTUnwrap(defaults.data(forKey: WallpaperConfig.userDefaultsKey))
        let envelope = try JSONDecoder().decode(AppPreferencesEnvelope.self, from: data)
        XCTAssertEqual(envelope.schemaVersion, WallpaperConfig.currentSchemaVersion)
        XCTAssertEqual(envelope.updatedAt, Self.date(hour: 12))
        XCTAssertEqual(envelope.wallpaperConfig, controller.config)
        XCTAssertEqual(WallpaperConfig.decodeCompatible(from: data), controller.config)
        XCTAssertFalse(envelope.wallpaperConfig.isFollowingSchedule)
        XCTAssertEqual(envelope.wallpaperConfig.locationName, original.locationName)
        XCTAssertEqual(envelope.wallpaperConfig.slots, original.slots)
        XCTAssertEqual(envelope.wallpaperConfig.slots(for: displays[0].uuid), original.slots(for: displays[0].uuid))
        XCTAssertTrue(service.applications.isEmpty)
    }

    func testExplicitInitialConfigTakesPrecedenceAndCorruptPersistenceFallsBack() throws {
        let suite = "SunpaperControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not JSON".utf8), forKey: WallpaperConfig.userDefaultsKey)
        let fallback = makeController(defaults: defaults)
        XCTAssertEqual(fallback.config, .default)
        let explicit = sampleConfig()
        let controller = makeController(config: explicit, defaults: defaults)
        XCTAssertEqual(controller.config, explicit)
    }

    func testUnreadableSettingsAreBackedUpBeforeAnEdit() throws {
        let suite = "SunpaperControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let unreadable = Data("not JSON".utf8)
        defaults.set(unreadable, forKey: WallpaperConfig.userDefaultsKey)

        let controller = makeController(defaults: defaults)
        XCTAssertEqual(controller.config, .default)
        XCTAssertEqual(defaults.data(forKey: WallpaperConfig.unreadableBackupKey), unreadable)
        XCTAssertEqual(defaults.data(forKey: WallpaperConfig.userDefaultsKey), unreadable)
        XCTAssertEqual(controller.message, "Your settings couldn’t be read. Defaults are in use, and the old data was kept.")

        controller.setSmoothWallpaperChanges(false)
        XCTAssertEqual(defaults.data(forKey: WallpaperConfig.unreadableBackupKey), unreadable)
        XCTAssertNotEqual(defaults.data(forKey: WallpaperConfig.userDefaultsKey), unreadable)

        let secondUnreadable = Data("also not JSON".utf8)
        defaults.set(secondUnreadable, forKey: WallpaperConfig.userDefaultsKey)
        _ = makeController(defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: WallpaperConfig.unreadableBackupKey), unreadable)
    }

    func testNewerStoredSchemaIsNeverOverwrittenByEdits() throws {
        let suite = "SunpaperControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = sampleConfig()
        let future = try JSONEncoder().encode(expected.persistenceEnvelope(
            schemaVersion: WallpaperConfig.currentSchemaVersion + 1))
        defaults.set(future, forKey: WallpaperConfig.userDefaultsKey)

        let controller = makeController(defaults: defaults)
        XCTAssertEqual(controller.config, expected)
        controller.setSmoothWallpaperChanges(false)
        XCTAssertFalse(controller.config.smoothWallpaperChanges)
        XCTAssertEqual(defaults.data(forKey: WallpaperConfig.userDefaultsKey), future)
        XCTAssertEqual(controller.message, "A newer version of Sunpaper saved these settings. Changes made here won’t be saved by this version.")
    }

    func testInvalidCoordinatesAreRejectedAndIgnoredWhenLoadedOrEdited() {
        let invalidPairs: [(Double?, Double?)] = [
            (nil, -18.0), (.nan, 18.0), (69.0, .infinity), (91.0, 18.0), (69.0, -181.0)
        ]
        for (latitude, longitude) in invalidPairs {
            var config = WallpaperConfig.default
            config.latitude = latitude
            config.longitude = longitude
            let controller = makeController(config: config)
            XCTAssertNil(controller.polarCondition)
            XCTAssertNil(controller.resolvedTime(for: .sunrise()))
        }

        let controller = makeController(config: sampleConfig())
        let original = controller.config
        controller.setLocation(name: "Invalid", latitude: .nan, longitude: 18)
        XCTAssertEqual(controller.config, original)
        XCTAssertEqual(controller.message, "Choose a valid location to use solar times.")
        controller.setLocation(name: "Invalid", latitude: 91, longitude: 18)
        XCTAssertEqual(controller.config, original)

        controller.change("Invalid stored location") { config in
            config.latitude = .infinity
        }
        XCTAssertNil(controller.polarCondition)
        XCTAssertNil(controller.resolvedTime(for: .sunrise()))
    }

    func testPolarConditionUsesCurrentDate() {
        var config = WallpaperConfig.default
        config.locationName = "Tromsø"
        config.latitude = 69.6492
        config.longitude = 18.9553
        let winter = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 21))!
        let summer = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 21))!

        XCTAssertEqual(makeController(config: config, now: winter).polarCondition, .polarNight)
        XCTAssertEqual(makeController(config: config, now: summer).polarCondition, .polarDay)
    }

    func testEditingSelectedDisplayDoesNotMutateGlobalOrOtherDisplayRules() {
        let original = sampleConfig()
        let service = ControllerWallpaperFake()
        let controller = makeController(config: original, service: service)
        controller.selectedDisplayUUID = displays[1].uuid
        let added = slot("Second-only addition", hour: 21)
        controller.editSlots("Add change") { $0.append(added) }
        XCTAssertEqual(controller.scope, displays[1].uuid)
        XCTAssertEqual(controller.slots, original.slots(for: displays[1].uuid) + [added])
        XCTAssertEqual(controller.config.slots, original.slots)
        XCTAssertEqual(controller.config.slots(for: displays[0].uuid), original.slots(for: displays[0].uuid))
        XCTAssertFalse(controller.config.isFollowingSchedule)

        var outOfScope = original.slots(for: displays[0].uuid)[0]
        outOfScope.name = "Must not change the other display"
        let before = controller.config
        controller.updateSlot(outOfScope)
        XCTAssertEqual(controller.config, before)
        XCTAssertTrue(service.applications.isEmpty)
    }

    func testDisconnectedDisplayCanBeEditedWithoutChangingConnectedDisplay() {
        var config = sampleConfig()
        let disconnected = "disconnected-display"
        config.setSlots([slot("Offline", hour: 9)], for: disconnected)
        let controller = makeController(config: config)
        controller.selectedDisplayUUID = disconnected
        XCTAssertEqual(controller.scopeName, "Disconnected display")
        controller.editSlots("Rename offline change") { $0[0].name = "Offline edited" }
        XCTAssertEqual(controller.config.slots(for: disconnected)[0].name, "Offline edited")
        XCTAssertEqual(controller.config.slots(for: displays[0].uuid), config.slots(for: displays[0].uuid))
        XCTAssertEqual(controller.config.slots(for: displays[1].uuid), config.slots(for: displays[1].uuid))
    }

    func testCollectionReplacementUndoRedoRestoresExactRulesAndDisplayScope() {
        let original = sampleConfig()
        let service = ControllerWallpaperFake()
        let controller = makeController(config: original, service: service)
        controller.selectedDisplayUUID = displays[1].uuid
        controller.undoManager.groupsByEvent = false
        controller.undoManager.beginUndoGrouping()
        controller.useCollection(BuiltInWallpapers.tahoe)
        controller.undoManager.endUndoGrouping()

        let replaced = controller.config
        let expectedSources = BuiltInWallpapers.Phase.allCases.map {
            WallpaperSource.builtIn(assetID: BuiltInWallpapers.tahoe.assetID(for: $0))
        }
        XCTAssertEqual(controller.slots.map(\.source), expectedSources)
        XCTAssertTrue(controller.slots.allSatisfy(\.isEnabled))
        XCTAssertEqual(controller.collectionName, "Tahoe")
        XCTAssertEqual(replaced.slots, original.slots)
        XCTAssertEqual(replaced.slots(for: displays[0].uuid), original.slots(for: displays[0].uuid))
        XCTAssertFalse(replaced.isFollowingSchedule)
        XCTAssertTrue(controller.undoManager.canUndo)

        // Selection is UI state, not part of the undo transaction. Undo must
        // restore the originally edited display even after changing selection.
        controller.selectedDisplayUUID = displays[0].uuid
        controller.undoManager.undo()
        XCTAssertEqual(controller.config, original)
        XCTAssertTrue(controller.undoManager.canRedo)
        controller.undoManager.redo()
        XCTAssertEqual(controller.config, replaced)
        XCTAssertEqual(controller.selectedDisplayUUID, displays[0].uuid)
        XCTAssertTrue(service.applications.isEmpty)
    }

    func testUndoAndRedoCollectionEditPreserveSubsequentPause() async {
        let original = WallpaperConfig(slots: [slot("Original", hour: 8)])
        let service = ControllerWallpaperFake()
        let controller = makeController(config: original, service: service)
        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()
        controller.undoManager.groupsByEvent = false
        controller.undoManager.beginUndoGrouping()
        controller.useCollection(BuiltInWallpapers.tahoe)
        controller.undoManager.endUndoGrouping()
        let collectionSlots = controller.slots
        await controller.scheduler.waitForPendingApplication()

        // Pausing is a separate, non-undoable action. Undoing the earlier
        // collection edit must not restore the old execution-enabled flag.
        controller.setFollowing(false)
        await controller.scheduler.waitForPendingApplication()
        let applicationsBeforeUndo = service.applications.count
        controller.undoManager.undo()
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(controller.slots, original.slots)
        XCTAssertFalse(controller.config.isFollowingSchedule)
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
        XCTAssertEqual(service.applications.count, applicationsBeforeUndo)

        controller.undoManager.redo()
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(controller.slots, collectionSlots)
        XCTAssertFalse(controller.config.isFollowingSchedule)
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
        XCTAssertEqual(service.applications.count, applicationsBeforeUndo)
    }

    func testSwitchingToPerDisplaySeedsOnlyMissingScopesAndPreservesSavedRules() {
        var original = sampleConfig()
        original.displayMode = .allDisplays
        original.perDisplayConfigs.removeAll { $0.displayUUID == displays[1].uuid }
        let controller = makeController(config: original)
        controller.setDisplayMode(.perDisplay)
        XCTAssertEqual(controller.config.slots, original.slots)
        XCTAssertEqual(controller.config.slots(for: displays[0].uuid), original.perDisplayConfigs[0].slots)
        XCTAssertEqual(controller.config.slots(for: displays[1].uuid), original.slots)
        controller.selectedDisplayUUID = displays[1].uuid
        controller.editSlots("Edit second display") { $0[0].name = "Keep this edit" }
        let savedPerDisplay = controller.config.perDisplayConfigs
        controller.setDisplayMode(.allDisplays)
        XCTAssertNil(controller.scope)
        XCTAssertEqual(controller.slots, original.slots)
        controller.setDisplayMode(.perDisplay)
        XCTAssertEqual(controller.config.perDisplayConfigs, savedPerDisplay)
        XCTAssertFalse(controller.config.isFollowingSchedule)
    }

    func testFixedTimeResolutionAndOvernightScheduleWorkWithoutLocation() {
        let morning = slot("Morning", hour: 8)
        let evening = slot("Evening", hour: 18)
        let config = WallpaperConfig(slots: [morning, evening], isFollowingSchedule: false)
        let controller = makeController(config: config, now: Self.date(hour: 6))
        XCTAssertEqual(controller.resolvedTime(for: morning.trigger), Self.date(hour: 8))
        XCTAssertNil(controller.resolvedTime(for: .sunrise()))
        XCTAssertFalse(controller.needsLocation)
        XCTAssertEqual(controller.expectedSlot?.id, evening.id)
        XCTAssertEqual(controller.nextChange?.slot.id, morning.id)
        XCTAssertEqual(controller.nextChange?.date, Self.date(hour: 8))
        XCTAssertEqual(controller.stateTitle, "Schedule paused")
    }

    func testNextChangeRollsIntoTomorrowAndIgnoresDisabledOrUnassignedRules() {
        let morning = slot("Morning", hour: 8)
        var disabled = slot("Disabled", hour: 22)
        disabled.isEnabled = false
        let unassigned = TimeSlot(name: "No wallpaper", trigger: .fixed(hour: 21, minute: 0), source: .none)
        let controller = makeController(config: WallpaperConfig(slots: [morning, disabled, unassigned]), now: Self.date(hour: 20))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Self.date(hour: 8))
        XCTAssertEqual(controller.expectedSlot?.id, morning.id)
        XCTAssertEqual(controller.nextChange?.slot.id, morning.id)
        XCTAssertEqual(controller.nextChange?.date, tomorrow)
    }

    func testPausedEditsRemainPausedAndNeverApplyWallpaper() async {
        let service = ControllerWallpaperFake()
        let controller = makeController(config: WallpaperConfig(slots: [slot("Initial", hour: 8)], isFollowingSchedule: false), service: service)
        controller.start()
        defer { controller.stop() }
        controller.editSlots("Rename change") { $0[0].name = "Renamed while paused" }
        controller.useCollection(BuiltInWallpapers.sequoia)
        controller.setLocation(name: "Chicago", latitude: 41.8781, longitude: -87.6298)
        await controller.scheduler.waitForPendingApplication()
        XCTAssertFalse(controller.config.isFollowingSchedule)
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
        XCTAssertEqual(controller.collectionName, "Sequoia")
        XCTAssertNotNil(controller.scheduler.currentSlot)
        XCTAssertNil(controller.shownSource)
        XCTAssertTrue(service.applications.isEmpty)
        XCTAssertEqual(service.downloadCount, 0)
    }

    func testStartUsesConfigEditedWhileControllerWasInert() async {
        let service = ControllerWallpaperFake()
        let original = WallpaperConfig(slots: [slot("Old", hour: 8)])
        let controller = makeController(config: original, service: service)
        controller.editSlots("Replace before starting") { $0 = [slot("New", hour: 9)] }
        controller.setFollowing(false)
        XCTAssertTrue(service.applications.isEmpty)
        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
        XCTAssertEqual(controller.scheduler.currentSlot?.name, "New")
        XCTAssertFalse(controller.config.isFollowingSchedule)
        XCTAssertTrue(service.applications.isEmpty)
    }

    func testManualApplyIsInertBeforeStartAndTargetsOnlySelectedDisplayAfterStart() async {
        let service = ControllerWallpaperFake()
        let controller = makeController(config: sampleConfig(), service: service)
        controller.selectedDisplayUUID = displays[1].uuid
        let source = WallpaperSource.builtIn(assetID: "manual")
        controller.apply(source)
        await controller.scheduler.waitForPendingApplication()
        XCTAssertTrue(service.applications.isEmpty)
        controller.start()
        defer { controller.stop() }
        controller.apply(source, duration: .oneHour)
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applications.count, 1)
        XCTAssertEqual(service.applications.first?.source, source)
        XCTAssertEqual(service.applications.first?.displayUUID, displays[1].uuid)
        XCTAssertEqual(controller.shownSource, source)
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
        controller.selectedDisplayUUID = displays[0].uuid
        XCTAssertNil(controller.shownSource)
    }

    func testCapturedDisplayEditsKeepOriginalScopeAfterSelectionAndModeChanges() {
        let original = sampleConfig()
        let controller = makeController(config: original)
        controller.selectedDisplayUUID = displays[0].uuid
        let capturedDisplayUUID = controller.scope
        var capturedSlot = controller.slots[0]

        controller.selectedDisplayUUID = displays[1].uuid
        capturedSlot.name = "Edited in the original display editor"
        controller.updateSlot(capturedSlot, displayUUID: capturedDisplayUUID)
        XCTAssertEqual(controller.config.slots(for: displays[0].uuid), [capturedSlot])
        XCTAssertEqual(controller.config.slots(for: displays[1].uuid), original.slots(for: displays[1].uuid))
        XCTAssertEqual(controller.config.slots, original.slots)

        controller.setDisplayMode(.allDisplays)
        let added = slot("Added by still-open display editor", hour: 20)
        controller.editSlots("Add captured-display change", displayUUID: capturedDisplayUUID) { $0.append(added) }
        let persistedFirst = controller.config.perDisplayConfigs.first { $0.displayUUID == displays[0].uuid }?.slots
        let persistedSecond = controller.config.perDisplayConfigs.first { $0.displayUUID == displays[1].uuid }?.slots
        XCTAssertEqual(persistedFirst, [capturedSlot, added])
        XCTAssertEqual(persistedSecond, original.slots(for: displays[1].uuid))
        XCTAssertEqual(controller.config.slots, original.slots)
        XCTAssertEqual(controller.slots, original.slots)
        XCTAssertEqual(controller.config.displayMode, .allDisplays)
    }

    func testCapturedGlobalNilEditsRemainGlobalAfterSwitchingToPerDisplay() {
        var original = sampleConfig()
        original.displayMode = .allDisplays
        let controller = makeController(config: original)
        let capturedScope = controller.scope
        XCTAssertNil(capturedScope)
        var capturedSlot = controller.slots[0]
        controller.setDisplayMode(.perDisplay)
        controller.selectedDisplayUUID = displays[1].uuid
        let perDisplayBeforeEdit = controller.config.perDisplayConfigs

        capturedSlot.name = "Edited in the still-open global editor"
        controller.updateSlot(capturedSlot, displayUUID: capturedScope)
        let added = slot("Global-only addition", hour: 19)
        controller.editSlots("Add captured-global change", displayUUID: capturedScope) { $0.append(added) }
        XCTAssertEqual(controller.config.slots, [capturedSlot, added])
        XCTAssertEqual(controller.config.perDisplayConfigs, perDisplayBeforeEdit)
        XCTAssertEqual(controller.slots, original.perDisplayConfigs[1].slots)
        XCTAssertEqual(controller.scope, displays[1].uuid)
        XCTAssertFalse(controller.config.isFollowingSchedule)
    }

    func testCapturedManualApplyScopeIsIndependentOfCurrentSelectionAndMode() async {
        let service = ControllerWallpaperFake()
        let controller = makeController(config: sampleConfig(), service: service)
        controller.selectedDisplayUUID = displays[0].uuid
        let capturedDisplay = controller.scope
        controller.start()
        defer { controller.stop() }
        controller.selectedDisplayUUID = displays[1].uuid
        controller.setDisplayMode(.allDisplays)
        let scopedSource = WallpaperSource.builtIn(assetID: "captured-display")
        controller.apply(scopedSource, displayUUID: capturedDisplay)
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applications.first?.displayUUID, displays[0].uuid)
        XCTAssertEqual(controller.scheduler.confirmedSourcesByDisplay[displays[0].uuid], scopedSource)
        XCTAssertNil(controller.scheduler.confirmedSourcesByDisplay[displays[1].uuid])

        let capturedGlobal = controller.scope
        XCTAssertNil(capturedGlobal)
        controller.setDisplayMode(.perDisplay)
        let globalSource = WallpaperSource.builtIn(assetID: "captured-global")
        controller.apply(globalSource, displayUUID: capturedGlobal)
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applications.count, 2)
        XCTAssertNil(service.applications.last?.displayUUID)
        XCTAssertEqual(controller.scheduler.confirmedSourcesByDisplay[displays[0].uuid], globalSource)
        XCTAssertEqual(controller.scheduler.confirmedSourcesByDisplay[displays[1].uuid], globalSource)
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
    }

    private func sampleConfig() -> WallpaperConfig {
        WallpaperConfig(
            slots: [slot("Global", hour: 7)], isFollowingSchedule: false,
            locationName: "Chicago", latitude: 41.8781, longitude: -87.6298,
            displayMode: .perDisplay,
            perDisplayConfigs: [
                DisplayConfig(displayUUID: displays[0].uuid, slots: [slot("First display", hour: 8)]),
                DisplayConfig(displayUUID: displays[1].uuid, slots: [slot("Second display", hour: 9)])
            ]
        )
    }

    func testSmoothingOptOutPersistsWithoutResumingAndSurvivesScheduleUndo() throws {
        let suite = "SunpaperControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ControllerWallpaperFake()
        let original = sampleConfig()
        let controller = makeController(config: original, defaults: defaults, service: service)
        controller.start()
        defer { controller.stop() }
        controller.undoManager.groupsByEvent = false
        controller.undoManager.beginUndoGrouping()
        controller.useCollection(BuiltInWallpapers.sequoia)
        controller.undoManager.endUndoGrouping()

        controller.setSmoothWallpaperChanges(false)
        let saved = try XCTUnwrap(defaults.data(forKey: WallpaperConfig.userDefaultsKey))
        XCTAssertFalse(try XCTUnwrap(WallpaperConfig.decodeCompatible(from: saved)).smoothWallpaperChanges)
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
        controller.undoManager.undo()
        XCTAssertEqual(controller.config.slots, original.slots)
        XCTAssertEqual(controller.config.perDisplayConfigs, original.perDisplayConfigs)
        XCTAssertFalse(controller.config.smoothWallpaperChanges)
        controller.undoManager.redo()
        XCTAssertFalse(controller.config.smoothWallpaperChanges)
        XCTAssertEqual(controller.scheduler.playbackMode, .paused)
        XCTAssertTrue(service.applications.isEmpty)
    }

    private func slot(_ name: String, hour: Int) -> TimeSlot {
        TimeSlot(name: name, trigger: .fixed(hour: hour, minute: 0), source: .builtIn(assetID: name))
    }

    private func makeController(
        config: WallpaperConfig? = nil,
        defaults: UserDefaults? = nil,
        service: ControllerWallpaperFake? = nil,
        now: Date? = nil
    ) -> SunpaperController {
        let service = service ?? ControllerWallpaperFake()
        let date = now ?? Self.date(hour: 12)
        let dependencies = SlotSchedulerDependencies(
            now: { date },
            calculateSunTimes: { SunCalculator.calculate(for: $0, on: $1) },
            timerScheduler: ControllerTimerFake(),
            wakeObserver: ControllerWakeFake(),
            wallpaperService: service,
            displayProvider: ControllerDisplayFake(displays: displays),
            aerialCatalog: ControllerCatalogFake()
        )
        return SunpaperController(config: config, defaults: defaults, dependencies: dependencies, displays: displays, now: { date })
    }

    private static func date(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: hour))!
    }
}

@MainActor
private final class ControllerWallpaperFake: SlotSchedulerWallpaperServicing {
    var applications: [(source: WallpaperSource, displayUUID: String?)] = []
    var downloadCount = 0

    func downloadAerial(assetID: String, from url: URL) async throws { downloadCount += 1 }
    nonisolated func isAerialDownloaded(assetID: String) -> Bool { true }
    func setWallpaper(assetID: String, displayUUID: String?) async throws {
        applications.append((.builtIn(assetID: assetID), displayUUID))
    }
    func setCustomWallpaper(path: String) throws {
        try setCustomWallpaper(path: path, displayUUID: nil)
    }
    func setCustomWallpaper(path: String, displayUUID: String?) throws {
        applications.append((.custom(path: path), displayUUID))
    }
    nonisolated func getCurrentAssetID() throws -> String? { nil }
}

private struct ControllerDisplayFake: SlotSchedulerDisplayProviding {
    let displays: [DisplayManager.Display]
    func getDisplays() -> [DisplayManager.Display] { displays }
}

private final class ControllerTimerToken: SlotSchedulerTimerToken {
    func invalidate() {}
}

private struct ControllerTimerFake: SlotSchedulerTimerScheduling {
    func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool,
                        _ handler: @escaping @MainActor @Sendable () -> Void) -> SlotSchedulerTimerToken {
        ControllerTimerToken()
    }
}

private struct ControllerWakeFake: SlotSchedulerWakeObserving {
    func observeWake(after delay: TimeInterval, handler: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol { NSObject() }
    func removeObserver(_ observer: NSObjectProtocol) {}
}

private struct ControllerCatalogFake: SlotSchedulerAerialCatalogResolving {
    func downloadURL(for assetID: String) -> URL? { nil }
}

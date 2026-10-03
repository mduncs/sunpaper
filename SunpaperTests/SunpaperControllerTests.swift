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

    func testMalformedVersionedEnvelopeIsBackedUpInsteadOfSilentlyDecodedAsDefaults() throws {
        let suite = "SunpaperControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let malformed = Data("{\"schemaVersion\":1,\"updatedAt\":\"broken\"}".utf8)
        defaults.set(malformed, forKey: WallpaperConfig.userDefaultsKey)
        let controller = makeController(defaults: defaults)
        XCTAssertEqual(controller.config, .default)
        XCTAssertEqual(defaults.data(forKey: WallpaperConfig.unreadableBackupKey), malformed)
        XCTAssertEqual(controller.message, "Your settings couldn’t be read. Defaults are in use, and the old data was kept.")
    }

    func testExpectedAndNextSolarChangesIncludeAdjacentDayOffsets() {
        let previousZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Chicago")!
        defer { NSTimeZone.default = previousZone }
        let now = Self.date(hour: 23)
        let solar = TimeSlot(name: "Before sunrise", trigger: .hoursBeforeSunrise(6), source: .builtIn(assetID: "early"))
        let fixed = slot("Evening", hour: 20)
        let config = WallpaperConfig(slots: [fixed, solar], latitude: 59.3293, longitude: -87.6298)
        let controller = makeController(config: config, now: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let tonight = controller.resolvedTime(for: solar.trigger, on: tomorrow)!
        XCTAssertLessThan(tonight, now)
        XCTAssertGreaterThan(tonight, controller.resolvedTime(for: fixed.trigger, on: now)!)
        XCTAssertEqual(controller.expectedSlot?.id, solar.id)
        XCTAssertGreaterThan(controller.nextChange!.date, now)
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

    func testRetryRestoresRetainedCoverBeforeRetryingChange() async {
        let service = ControllerWallpaperFake()
        let recovery = ControllerRecoveryFake(needsRecovery: true, restores: true)
        let controller = makeController(config: WallpaperConfig(slots: [slot("Morning", hour: 8)]), service: service, recovery: recovery)
        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applications.count, 1)

        await controller.retryWallpaperChange()
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(recovery.attempts, 1)
        XCTAssertFalse(recovery.needsRecovery)
        XCTAssertEqual(service.applications.count, 2)
    }

    func testRetryDoesNotChangeWallpaperWhileRestorationStillFails() async {
        let service = ControllerWallpaperFake()
        let recovery = ControllerRecoveryFake(needsRecovery: true, restores: false)
        let controller = makeController(config: WallpaperConfig(slots: [slot("Morning", hour: 8)]), service: service, recovery: recovery)
        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()

        await controller.retryWallpaperChange()
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(recovery.attempts, 1)
        XCTAssertEqual(service.applications.count, 1)
    }

    func testSettledDisplayChangeRestoresRetainedCoverThenReconciles() async {
        let service = ControllerWallpaperFake()
        let recovery = ControllerRecoveryFake(needsRecovery: true, restores: true)
        let controller = makeController(config: WallpaperConfig(slots: [slot("Morning", hour: 8)]), service: service, recovery: recovery)
        await controller.displayLayoutDidSettle()
        XCTAssertEqual(recovery.attempts, 0, "An inert controller must not restore")

        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()
        await controller.displayLayoutDidSettle()
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(recovery.attempts, 1)
        XCTAssertEqual(service.applications.count, 2)
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

    func testInactiveSolarRowsDoNotRequireLocationOrMisstateStatus() {
        var disabled = TimeSlot(name: "Disabled solar", trigger: .sunrise(), source: .builtIn(assetID: "sunrise"))
        disabled.isEnabled = false
        let unassigned = TimeSlot(name: "Unassigned solar", trigger: .sunset(), source: .none)
        let controller = makeController(config: WallpaperConfig(slots: [slot("Fixed", hour: 8), disabled, unassigned]))
        XCTAssertFalse(controller.needsLocation)
        XCTAssertEqual(controller.stateTitle, "Following schedule")
    }

    func testRetryStatusToneAgreesWithBusyTitleDespitePreviousError() async {
        let service = ControllerWallpaperFake()
        service.shouldFail = true
        let controller = makeController(config: WallpaperConfig(slots: [slot("Morning", hour: 8)]), service: service)
        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()
        XCTAssertNotNil(controller.scheduler.lastError)
        XCTAssertEqual(controller.statusTone, .attention)

        service.shouldFail = false
        controller.scheduler.retryLastApplication()
        XCTAssertTrue(controller.scheduler.isApplying)
        XCTAssertEqual(controller.stateTitle, "Changing wallpaper…")
        XCTAssertEqual(controller.statusTone, .busy)
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(controller.statusTone, .following)
    }

    func testDayRibbonIncludesSolarChangesFromAdjacentAnchorDays() throws {
        var config = WallpaperConfig(slots: [
            slot("Noon", hour: 12),
            TimeSlot(name: "Early sunrise", trigger: .sunrise(offset: -6 * 3600), source: .builtIn(assetID: "early")),
            TimeSlot(name: "Late sunset", trigger: .sunset(offset: 6 * 3600), source: .builtIn(assetID: "late"))
        ], isFollowingSchedule: false)
        config.latitude = 41.8781
        config.longitude = -87.6298
        let controller = makeController(config: config)
        let day = try XCTUnwrap(Calendar.current.dateInterval(of: .day, for: controller.currentDate))
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: controller.currentDate))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: controller.currentDate))
        // Choose offsets dynamically so this fixture also works in other time zones.
        let sunrise = try XCTUnwrap(controller.resolvedTime(for: .sunrise()))
        let sunset = try XCTUnwrap(controller.resolvedTime(for: .sunset()))
        config.slots[1].trigger = .sunrise(offset: day.start.timeIntervalSince(sunrise) - 3600)
        config.slots[2].trigger = .sunset(offset: day.end.timeIntervalSince(sunset) + 3600)
        let adjusted = makeController(config: config)
        let earlyToday = try XCTUnwrap(adjusted.resolvedTime(for: config.slots[1].trigger, on: tomorrow))
        let lateToday = try XCTUnwrap(adjusted.resolvedTime(for: config.slots[2].trigger, on: yesterday))
        XCTAssertTrue(day.contains(earlyToday))
        XCTAssertTrue(day.contains(lateToday))
        let model = DayRibbonModel(controller: adjusted)
        XCTAssertEqual(model.segments.map(\.source), [.builtIn(assetID: "early"), .builtIn(assetID: "late"), config.slots[0].source, .builtIn(assetID: "early")])
        XCTAssertEqual(try XCTUnwrap(model.segments.last).start, earlyToday.timeIntervalSince(day.start) / day.duration, accuracy: 0.000001)
        XCTAssertEqual(model.now, controller.currentDate.timeIntervalSince(day.start) / day.duration, accuracy: 0.000001)
        XCTAssertTrue(model.summary.contains("Early sunrise"))
        XCTAssertTrue(model.summary.contains("Late sunset"))

        let beforeLate = makeController(config: config, now: lateToday.addingTimeInterval(-60))
        XCTAssertEqual(beforeLate.nextChange?.date, lateToday)
        let afterEarly = makeController(config: config, now: earlyToday.addingTimeInterval(60))
        XCTAssertEqual(afterEarly.expectedSlot?.id, config.slots[1].id)
    }

    func testDayRibbonRetainsOneMinuteWallpaperSegments() throws {
        let first = slot("First", hour: 12)
        let second = TimeSlot(name: "Second", trigger: .fixed(hour: 12, minute: 1), source: .builtIn(assetID: "second"))
        let controller = makeController(config: WallpaperConfig(slots: [first, second], isFollowingSchedule: false))
        let model = DayRibbonModel(controller: controller)
        let brief = try XCTUnwrap(model.segments.first { $0.source == first.source })
        XCTAssertEqual(brief.start, 0.5, accuracy: 0.000001)
        XCTAssertEqual(brief.length, 1.0 / 1440, accuracy: 0.000001)
        XCTAssertEqual(model.segments.map(\.source), [second.source, first.source, second.source])
    }

    func testConcurrentAppLaunchesElectOneInstanceInsteadOfBothQuitting() {
        let date = Self.date(hour: 12)
        let processes: [(Int32, Date)] = [(100, date), (101, date)]
        XCTAssertTrue(AppDelegate.shouldStart(processIdentifier: 100, runningProcesses: processes))
        XCTAssertFalse(AppDelegate.shouldStart(processIdentifier: 101, runningProcesses: processes))
        XCTAssertTrue(AppDelegate.shouldStart(processIdentifier: 101, runningProcesses: [(101, date)]))
        // PIDs can wrap: a later launch with a smaller PID must still exit.
        let wrapped: [(Int32, Date)] = [(100, date), (1, date.addingTimeInterval(1))]
        XCTAssertTrue(AppDelegate.shouldStart(processIdentifier: 100, runningProcesses: wrapped))
        XCTAssertFalse(AppDelegate.shouldStart(processIdentifier: 1, runningProcesses: wrapped))
    }

    func testCancelledLocationManagerCannotFinishANewerRequest() async {
        let old = ControllerLocationManagerFake()
        let current = ControllerLocationManagerFake()
        var managers = [old, current]
        let search = LocationSearchModel(makeManager: { managers.removeFirst() })
        search.findCurrentLocation()
        search.findCurrentLocation()
        let originalResults = search.results.map(\.id)
        let location = CLLocation(latitude: 1, longitude: 2)

        // Delegate callbacks can already be queued when cancellation detaches
        // the old manager. They must not consume the newer request's state.
        search.locationManager(old, didUpdateLocations: [location])
        await Task.yield()
        XCTAssertTrue(search.locating)
        XCTAssertEqual(search.results.map(\.id), originalResults)

        search.locationManager(old, didFailWithError: NSError(domain: "test", code: 1))
        await Task.yield()
        XCTAssertTrue(search.locating)
        XCTAssertNil(search.error)

        search.locationManager(current, didUpdateLocations: [location])
        await Task.yield()
        XCTAssertFalse(search.locating)
        XCTAssertEqual(search.results.first?.latitude, 1)
        search.cancel()
    }

    func testExpectedSlotUsesTheSameTieOrderAsTheAppliedSchedule() async {
        let first = slot("First", hour: 8)
        let second = slot("Second", hour: 8)
        let controller = makeController(config: WallpaperConfig(slots: [first, second]))
        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()
        XCTAssertEqual(controller.shownSource, second.source)
        XCTAssertEqual(controller.expectedSlot?.id, second.id)
    }

    func testPickerRejectsSingleFrameGIFThatWallpaperServiceCannotApply() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SunpaperPicker-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        try data.write(to: url)
        XCTAssertThrowsError(try WallpaperService.shared.validateCustomWallpaper(path: url.path))
        XCTAssertNil(WallpaperGridPicker.validatedImage(at: url))
    }

    private func slot(_ name: String, hour: Int) -> TimeSlot {
        TimeSlot(name: name, trigger: .fixed(hour: hour, minute: 0), source: .builtIn(assetID: name))
    }

    private func makeController(
        config: WallpaperConfig? = nil,
        defaults: UserDefaults? = nil,
        service: ControllerWallpaperFake? = nil,
        recovery: WallpaperRecovering? = nil,
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
        return SunpaperController(config: config, defaults: defaults, dependencies: dependencies, displays: displays,
                                  recovery: recovery ?? ControllerRecoveryFake(needsRecovery: false, restores: true), now: { date })
    }

    private static func date(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: hour))!
    }
}

@MainActor
private final class ControllerWallpaperFake: SlotSchedulerWallpaperServicing {
    var applications: [(source: WallpaperSource, displayUUID: String?)] = []
    var downloadCount = 0
    var shouldFail = false

    func downloadAerial(assetID: String, from url: URL) async throws { downloadCount += 1 }
    nonisolated func isAerialDownloaded(assetID: String) -> Bool { true }
    func setWallpaper(assetID: String, displayUUID: String?) async throws {
        if shouldFail { throw WallpaperError.aerialNotDownloaded(assetID: assetID) }
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

@MainActor
private final class ControllerRecoveryFake: WallpaperRecovering {
    private(set) var needsRecovery: Bool
    private(set) var attempts = 0
    private let restores: Bool

    init(needsRecovery: Bool, restores: Bool) {
        self.needsRecovery = needsRecovery
        self.restores = restores
    }

    func retryRecovery() async {
        attempts += 1
        if restores { needsRecovery = false }
    }
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

private final class ControllerLocationManagerFake: CLLocationManager {
    override var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }
    override func requestLocation() {}
    override func stopUpdatingLocation() {}
}

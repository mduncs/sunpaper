import XCTest
@testable import Sunpaper

@MainActor
final class WallpaperTransitionTests: XCTestCase {
    private enum Failure: Error { case write, readiness, restore }

    func testMonochromeAndDarkScenesMatchWithoutColorOrBrightnessHeuristics() {
        for level in [0.04, 0.4, 0.8] {
            let values = (0..<96).map { index in level + Double(index % 9) * 0.004 }
            let frame = WallpaperFrameSignature(rgb: values)
            XCTAssertTrue(frame.matches(WallpaperFrameSignature(rgb: values.map { $0 + 0.003 })))
        }
    }

    func testCapturedNativeFramesMatchVideoReferencesOnBothDisplays() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "WallpaperFrameSignatures", withExtension: "json"))
        let fixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        XCTAssertEqual(fixtures.count, 4)
        for fixture in fixtures {
            func signature(_ key: String) throws -> WallpaperFrameSignature {
                let encoded = try XCTUnwrap(fixture[key])
                let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
                return WallpaperFrameSignature(rgb: bytes.map { Double($0) / 255 })
            }
            let captured = try signature("captured")
            XCTAssertTrue(captured.matches(try signature("reference")), fixture["name"] ?? "")
            XCTAssertFalse(captured.matches(try signature("otherScene")), fixture["name"] ?? "")
        }
    }

    func testCancellationBeforeMutationDoesNotRestoreOrReveal() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await WallpaperTransitionTransaction.perform(change: { XCTFail("Must not mutate") },
                finish: { XCTFail("Must not reveal") }, recover: { XCTFail("Nothing to restore") })
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testBlankAndWrongSceneDoNotEstablishReadiness() {
        let scene = WallpaperFrameSignature(rgb: (0..<96).map { Double($0 % 13) / 15 })
        for gray in [0.0, 0.09, 0.18, 0.5, 1.0] {
            XCTAssertFalse(WallpaperFrameSignature(rgb: Array(repeating: gray, count: 96)).matches(scene))
        }
        let reversed = WallpaperFrameSignature(rgb: scene.values.reversed())
        XCTAssertFalse(reversed.matches(scene))
    }

    func testReadinessRequiresThreeConsecutiveMatchesAcrossAllDisplays() {
        var state = WallpaperReadiness()
        XCTAssertFalse(state.observe(allDisplaysMatch: true))
        XCTAssertFalse(state.observe(allDisplaysMatch: true))
        XCTAssertFalse(state.observe(allDisplaysMatch: false))
        XCTAssertFalse(state.observe(allDisplaysMatch: true))
        XCTAssertFalse(state.observe(allDisplaysMatch: true))
        XCTAssertTrue(state.observe(allDisplaysMatch: true))
    }

    func testSameSceneReloadMustBeWitnessedOnEveryDisplayBeforeReveal() {
        let scene = WallpaperFrameSignature(rgb: (0..<96).map { Double($0 % 13) / 15 })
        let blank = WallpaperFrameSignature(rgb: Array(repeating: 0.18, count: 96))
        var readiness = WallpaperReloadReadiness(originals: [1: scene, 2: scene], expected: [1: [scene], 2: [scene]])
        for _ in 0..<4 { XCTAssertFalse(readiness.observe([1: scene, 2: scene])) }
        XCTAssertFalse(readiness.observe([1: blank, 2: scene]))
        for _ in 0..<4 { XCTAssertFalse(readiness.observe([1: scene, 2: scene])) }
        XCTAssertFalse(readiness.observe([1: scene, 2: blank]))
        XCTAssertFalse(readiness.observe([1: scene, 2: scene]))
        XCTAssertFalse(readiness.observe([:])) // a missed capture resets the streak
        XCTAssertFalse(readiness.observe([1: scene, 2: scene]))
        XCTAssertFalse(readiness.observe([1: scene, 2: scene]))
        XCTAssertTrue(readiness.observe([1: scene, 2: scene]))
    }

    func testWriteFailureRestoresBeforeReturningAndNeverReveals() async {
        var events: [String] = []
        do {
            try await WallpaperTransitionTransaction.perform(change: {
                events.append("partial-write")
                throw Failure.write
            }, finish: { events.append("reveal") }, recover: { events.append("restore") })
            XCTFail("Expected write failure")
        } catch Failure.write {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(events, ["partial-write", "restore"])
    }

    func testReadinessFailureRestoresAndReportsOriginalFailure() async {
        var restored = false
        do {
            try await WallpaperTransitionTransaction.perform(change: {}, finish: {
                throw Failure.readiness
            }, recover: { restored = true })
            XCTFail("Expected readiness failure")
        } catch Failure.readiness {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(restored)
    }

    func testFailedRecoveryIsNotReportedAsRestored() async {
        do {
            try await WallpaperTransitionTransaction.perform(change: { throw Failure.write }, finish: {}, recover: {
                throw Failure.restore
            })
            XCTFail("Expected recovery failure")
        } catch WallpaperTransitionError.recoveryFailed {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testUncoveredRecoveryFailureDoesNotClaimThereIsACover() async {
        do {
            try await WallpaperTransitionTransaction.perform(
                change: { throw Failure.write }, finish: {},
                recover: { throw Failure.restore }, recoveryFailure: .uncoveredRecoveryFailed)
            XCTFail("Expected restoration failure")
        } catch WallpaperTransitionError.uncoveredRecoveryFailed {
            // The uncovered path must not report the covered recovery error.
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testRecoveryAfterDisplayChangeRemovesCoversAndRestoresWithoutThem() async throws {
        var events: [String] = []
        try await WallpaperCoverRecovery.perform(
            layoutMatches: false,
            removeCovers: { events.append("remove") },
            restore: { events.append("restore") },
            verifiedRestore: { XCTFail("Stale covers can never be verified") })
        XCTAssertEqual(events, ["remove", "restore"])
    }

    func testRecoveryWithUnchangedLayoutKeepsCoversForVerifiedRestore() async throws {
        var events: [String] = []
        try await WallpaperCoverRecovery.perform(
            layoutMatches: true,
            removeCovers: { XCTFail("Covers must stay up while they still fit") },
            restore: { XCTFail("Restore runs inside the verified path") },
            verifiedRestore: { events.append("verified") })
        XCTAssertEqual(events, ["verified"])
    }

    func testFailedRestoreAfterDisplayChangeStillReportsFailure() async {
        do {
            try await WallpaperCoverRecovery.perform(
                layoutMatches: false, removeCovers: {},
                restore: { throw Failure.restore }, verifiedRestore: {})
            XCTFail("Expected restoration failure")
        } catch Failure.restore {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCancellationAfterMutationStillCompletesUncancelledRecovery() async {
        let changed = expectation(description: "mutation started")
        var resumeMutation: CheckedContinuation<Void, Never>?
        var recovered = false
        let task = Task {
            try await WallpaperTransitionTransaction.perform(change: {
                changed.fulfill()
                await withCheckedContinuation { resumeMutation = $0 }
            }, finish: { XCTFail("Cancelled request must not reveal") }, recover: {
                try Task.checkCancellation()
                recovered = true
            })
        }
        await fulfillment(of: [changed], timeout: 2)
        task.cancel()
        resumeMutation?.resume()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(recovered)
    }

    func testQueueWaitsForRecoveryAndSkipsCancelledQueuedRequest() async {
        let gate = WallpaperChangeGate()
        let began = expectation(description: "first began")
        var release: CheckedContinuation<Void, Never>?
        var events: [Int] = []
        let first = Task {
            try await gate.perform {
                events.append(1)
                began.fulfill()
                await withCheckedContinuation { release = $0 }
                events.append(2)
            }
        }
        await fulfillment(of: [began], timeout: 2)
        let cancelled = Task { try await gate.perform { events.append(99) } }
        cancelled.cancel()
        let last = Task { try await gate.perform { events.append(3) } }
        release?.resume()
        _ = await first.result
        _ = await cancelled.result
        _ = await last.result
        XCTAssertEqual(events, [1, 2, 3])
        XCTAssertFalse(gate.isBusy)
    }
}

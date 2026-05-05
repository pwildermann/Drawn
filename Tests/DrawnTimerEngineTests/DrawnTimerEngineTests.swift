import DrawnTimerEngine
import Foundation
import XCTest

final class DrawnTimerEngineTests: XCTestCase {
    func testPrimaryPickerPrefersSoonestRunning() throws {
        let a = UUID()
        let b = UUID()
        let input: [PrimaryTimerPickInput] = [
            PrimaryTimerPickInput(id: a, hasStarted: true, isRunning: true, remainingSeconds: 120),
            PrimaryTimerPickInput(id: b, hasStarted: true, isRunning: true, remainingSeconds: 30),
        ]
        XCTAssertEqual(PrimaryTimerPicker.preferredTimerID(from: input), b)
    }

    func testPrimaryPickerWhenNoneRunningUsesPausedNearestZero() throws {
        let a = UUID()
        let b = UUID()
        let input: [PrimaryTimerPickInput] = [
            PrimaryTimerPickInput(id: a, hasStarted: true, isRunning: false, remainingSeconds: 300),
            PrimaryTimerPickInput(id: b, hasStarted: true, isRunning: false, remainingSeconds: 12),
        ]
        XCTAssertEqual(PrimaryTimerPicker.preferredTimerID(from: input), b)
    }

    func testPrimaryPickerIgnoresNeverStarted() throws {
        let a = UUID()
        let input: [PrimaryTimerPickInput] = [
            PrimaryTimerPickInput(id: a, hasStarted: false, isRunning: false, remainingSeconds: 10),
        ]
        XCTAssertNil(PrimaryTimerPicker.preferredTimerID(from: input))
    }

    /// Running must stay eligible even if `hasStarted` is stale (`false`) so Live Activity never reconciles with nil and ends.
    func testPrimaryPickerRunningCountsEvenIfHasStartedFalse() throws {
        let id = UUID()
        let input: [PrimaryTimerPickInput] = [
            PrimaryTimerPickInput(id: id, hasStarted: false, isRunning: true, remainingSeconds: 42),
        ]
        XCTAssertEqual(PrimaryTimerPicker.preferredTimerID(from: input), id)
    }

    func testPrimaryPickerRunningBeatsPaused() throws {
        let running = UUID()
        let paused = UUID()
        let input: [PrimaryTimerPickInput] = [
            PrimaryTimerPickInput(id: paused, hasStarted: true, isRunning: false, remainingSeconds: 5),
            PrimaryTimerPickInput(id: running, hasStarted: true, isRunning: true, remainingSeconds: 999),
        ]
        XCTAssertEqual(PrimaryTimerPicker.preferredTimerID(from: input), running)
    }

    func testDeadlineMathCeilsAndFloors() throws {
        let now = Date()
        let d = now.addingTimeInterval(1.1)
        XCTAssertEqual(RunningTimerDeadlineMath.remainingSecondsUntil(deadline: d, now: now), 2)
        let past = now.addingTimeInterval(-5)
        XCTAssertEqual(RunningTimerDeadlineMath.remainingSecondsUntil(deadline: past, now: now), 0)
    }

    func testRemainingAfterElapsedSubtractsWallClockTime() throws {
        XCTAssertEqual(
            RunningTimerDeadlineMath.remainingAfterElapsed(savedRemainingSeconds: 3600, elapsedSeconds: 2400),
            1200
        )
    }

    func testRemainingAfterElapsedClampsToZero() throws {
        XCTAssertEqual(
            RunningTimerDeadlineMath.remainingAfterElapsed(savedRemainingSeconds: 30, elapsedSeconds: 90),
            0
        )
    }
}

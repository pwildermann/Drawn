import DrawnTimerEngine
import XCTest

final class TimerLifecycleMatrixTests: XCTestCase {
    func testSecondLongTimerFullFlow() {
        var s = TimerLifecycleState(totalSeconds: 12)
        s = TimerLifecycleEngine.reduce(s, action: .start)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 4))
        XCTAssertEqual(s.remainingSeconds, 8)
        XCTAssertTrue(s.isRunning)

        s = TimerLifecycleEngine.reduce(s, action: .pause)
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.remainingSeconds, 8)

        // Duplicate external delivery should stay paused (idempotent).
        s = TimerLifecycleEngine.reduce(s, action: .pause)
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.remainingSeconds, 8)

        s = TimerLifecycleEngine.reduce(s, action: .resume)
        XCTAssertTrue(s.isRunning)

        // Duplicate resume should not flip back.
        s = TimerLifecycleEngine.reduce(s, action: .resume)
        XCTAssertTrue(s.isRunning)

        s = TimerLifecycleEngine.reduce(s, action: .stop)
        XCTAssertFalse(s.isRunning)
        XCTAssertFalse(s.hasStarted)
        XCTAssertFalse(s.isRinging)
        XCTAssertEqual(s.remainingSeconds, 12)
    }

    func testMinuteLongTimerPauseResumeAndExpiry() {
        var s = TimerLifecycleState(totalSeconds: 5 * 60)
        s = TimerLifecycleEngine.reduce(s, action: .start)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 120))
        XCTAssertEqual(s.remainingSeconds, 180)

        s = TimerLifecycleEngine.reduce(s, action: .pause)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 120))
        XCTAssertEqual(s.remainingSeconds, 180, "Paused timer must not count down")

        s = TimerLifecycleEngine.reduce(s, action: .resume)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 180))

        XCTAssertTrue(s.isRinging)
        XCTAssertFalse(s.isRunning)
        XCTAssertFalse(s.hasStarted)
        XCTAssertEqual(s.remainingSeconds, 300, "Ringing snapshot resets model timer for next run")
    }

    func testHourLongTimerLargeElapsedPauseResume() {
        var s = TimerLifecycleState(totalSeconds: 3 * 3600)
        s = TimerLifecycleEngine.reduce(s, action: .start)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 2 * 3600 + 50 * 60))
        XCTAssertEqual(s.remainingSeconds, 600)

        s = TimerLifecycleEngine.reduce(s, action: .pause)
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.remainingSeconds, 600)

        s = TimerLifecycleEngine.reduce(s, action: .resume)
        XCTAssertTrue(s.isRunning)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 600))
        XCTAssertTrue(s.isRinging)
    }

    func testStopAlwaysWinsFromAnyState() {
        var s = TimerLifecycleState(totalSeconds: 90)
        s = TimerLifecycleEngine.reduce(s, action: .start)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 89))
        XCTAssertEqual(s.remainingSeconds, 1)

        s = TimerLifecycleEngine.reduce(s, action: .stop)
        XCTAssertEqual(s.remainingSeconds, 90)
        XCTAssertFalse(s.isRunning)
        XCTAssertFalse(s.hasStarted)
        XCTAssertFalse(s.isRinging)
    }

    func testRingingIgnoresPauseResumeUntilStopped() {
        var s = TimerLifecycleState(totalSeconds: 10)
        s = TimerLifecycleEngine.reduce(s, action: .start)
        s = TimerLifecycleEngine.reduce(s, action: .tick(seconds: 10))
        XCTAssertTrue(s.isRinging)

        s = TimerLifecycleEngine.reduce(s, action: .pause)
        XCTAssertTrue(s.isRinging)
        s = TimerLifecycleEngine.reduce(s, action: .resume)
        XCTAssertTrue(s.isRinging)

        s = TimerLifecycleEngine.reduce(s, action: .stop)
        XCTAssertFalse(s.isRinging)
        XCTAssertEqual(s.remainingSeconds, 10)
    }
}

import DrawnTimerEngine
import XCTest

final class LiveActivityControlRouteTests: XCTestCase {
    func testRouteParsingAcceptsCaseAndWhitespace() {
        XCTAssertEqual(LiveActivityControlRoute(token: " pause "), .pause)
        XCTAssertEqual(LiveActivityControlRoute(token: "RESUME"), .resume)
        XCTAssertEqual(LiveActivityControlRoute(token: "toggle"), .toggle)
        XCTAssertNil(LiveActivityControlRoute(token: "unknown"))
    }

    func testPlayPauseRouteIsIdempotentByState() {
        XCTAssertEqual(LiveActivityControlRoute.playPauseRoute(isPaused: false), .pause)
        XCTAssertEqual(LiveActivityControlRoute.playPauseRoute(isPaused: true), .resume)
    }

    func testResultingRunningStateForPauseResumeToggle() {
        XCTAssertEqual(LiveActivityControlRoute.pause.resultingRunningState(currentRunning: true), false)
        XCTAssertEqual(LiveActivityControlRoute.pause.resultingRunningState(currentRunning: false), false)

        XCTAssertEqual(LiveActivityControlRoute.resume.resultingRunningState(currentRunning: false), true)
        XCTAssertEqual(LiveActivityControlRoute.resume.resultingRunningState(currentRunning: true), true)

        XCTAssertEqual(LiveActivityControlRoute.toggle.resultingRunningState(currentRunning: true), false)
        XCTAssertEqual(LiveActivityControlRoute.toggle.resultingRunningState(currentRunning: false), true)
        XCTAssertNil(LiveActivityControlRoute.stop.resultingRunningState(currentRunning: true))
    }
}

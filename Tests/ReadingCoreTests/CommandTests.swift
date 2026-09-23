import XCTest
@testable import ReadingCore

final class CommandTests: XCTestCase {
    func testExactHomeFreshTargetAndOptInRequired() {
        let intent = HomeCommand.Intent(home: "home", accessory: "light", characteristic: UUID(), expected: false, desired: true)
        var command = HomeCommand()
        XCTAssertNil(command.begin(intent, currentHome: "other", currentState: false, reachable: true, allowed: true))
        XCTAssertNil(command.begin(intent, currentHome: "home", currentState: nil, reachable: true, allowed: true))
        XCTAssertNil(command.begin(intent, currentHome: "home", currentState: true, reachable: true, allowed: true))
        XCTAssertNil(command.begin(intent, currentHome: "home", currentState: false, reachable: false, allowed: true))
        XCTAssertNil(command.begin(intent, currentHome: "home", currentState: false, reachable: true, allowed: false))
        XCTAssertNotNil(command.begin(intent, currentHome: "home", currentState: false, reachable: true, allowed: true))
        XCTAssertNil(command.begin(intent, currentHome: "home", currentState: false, reachable: true, allowed: true))
    }
    func testLateCompletionsCannotFinishAnotherRunOrReplay() throws {
        let now = Date(); let intent = HomeCommand.Intent(home: "home", accessory: "light", characteristic: UUID(), expected: false, desired: true)
        var command = HomeCommand()
        let first = try XCTUnwrap(command.begin(intent, currentHome: "home", currentState: false, reachable: true, allowed: true, now: now))
        XCTAssertTrue(command.expire(now: now.addingTimeInterval(21)))
        XCTAssertFalse(command.accepts(first)); XCTAssertNil(command.active)
        let second = try XCTUnwrap(command.begin(intent, currentHome: "home", currentState: false, reachable: true, allowed: true))
        XCTAssertFalse(command.finish(first)); XCTAssertTrue(command.accepts(second))
        command.reset(); XCTAssertFalse(command.finish(second))
    }
}

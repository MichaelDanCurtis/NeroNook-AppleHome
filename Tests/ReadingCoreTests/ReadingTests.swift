import XCTest
@testable import ReadingCore
final class ReadingTests: XCTestCase {
    func testLargeInventoryEventuallyReadsEveryItemWithBoundedConcurrency() {
        var tracker = ReadingTracker(); let ids = (0..<192).map { _ in UUID() }; tracker.enqueue(ids)
        let now = Date(); var active: [ReadingTracker.Ticket] = []
        for _ in 0..<8 { active.append(tracker.next(now: now)!) }; XCTAssertNil(tracker.next(now: now))
        var completed = Set<UUID>()
        while !active.isEmpty {
            let ticket = active.removeFirst(); XCTAssertTrue(tracker.complete(ticket, success: true, now: now)); completed.insert(ticket.characteristic)
            if let next = tracker.next(now: now) { active.append(next) }
        }
        XCTAssertEqual(completed, Set(ids)); XCTAssertFalse(tracker.busy)
    }
    func testExpiredAndOldSessionCallbacksCannotCompleteNewerRead() {
        var tracker = ReadingTracker(); let id = UUID(), now = Date(); tracker.enqueue([id]); let old = tracker.next(now: now)!
        tracker.expire(now: now.addingTimeInterval(13)); XCTAssertFalse(tracker.fresh(id)); XCTAssertFalse(tracker.busy)
        tracker.enqueue([id]); let new = tracker.next(now: now.addingTimeInterval(14))!
        XCTAssertFalse(tracker.complete(old, success: true)); XCTAssertTrue(tracker.busy)
        XCTAssertTrue(tracker.complete(new, success: true, now: now.addingTimeInterval(15)))
        tracker.reset(); XCTAssertFalse(tracker.complete(new, success: true)); XCTAssertFalse(tracker.fresh(id))
    }
    func testValuesExpireAndEventsRefreshThem() {
        var tracker = ReadingTracker(); let id = UUID(), now = Date(); tracker.event(id, now: now)
        XCTAssertTrue(tracker.fresh(id, now: now.addingTimeInterval(119)))
        XCTAssertFalse(tracker.fresh(id, now: now.addingTimeInterval(121)))
        tracker.expire(now: now.addingTimeInterval(121)); tracker.event(id, now: now.addingTimeInterval(122))
        XCTAssertTrue(tracker.fresh(id, now: now.addingTimeInterval(123)))
    }
}

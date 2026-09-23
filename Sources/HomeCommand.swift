import Foundation

/// A single explicitly reviewed power command. Timeout never schedules a retry.
struct HomeCommand {
    struct Intent: Equatable {
        let home: String
        let accessory: String
        let characteristic: UUID
        let expected: Bool
        let desired: Bool
    }
    struct Run: Equatable { let id: UUID; let intent: Intent; let deadline: Date }
    private(set) var active: Run?
    mutating func begin(_ intent: Intent, currentHome: String, currentState: Bool?, reachable: Bool, allowed: Bool, now: Date = Date()) -> Run? {
        guard active == nil, !intent.home.isEmpty, intent.home == currentHome,
              currentState == intent.expected, reachable, allowed else { return nil }
        let run = Run(id: UUID(), intent: intent, deadline: now.addingTimeInterval(20)); active = run; return run
    }
    func accepts(_ run: Run, now: Date = Date()) -> Bool { active == run && now <= run.deadline }
    @discardableResult mutating func finish(_ run: Run) -> Bool { guard active == run else { return false }; active = nil; return true }
    mutating func expire(now: Date = Date()) -> Bool { guard let active, now > active.deadline else { return false }; self.active = nil; return true }
    mutating func reset() { active = nil }
}

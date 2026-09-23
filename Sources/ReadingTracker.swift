import Foundation

/// Bounded reads with expiring values and unique tickets: a late callback cannot
/// complete a newer read for the same HomeKit characteristic.
struct ReadingTracker {
    struct Ticket: Equatable {
        let characteristic: UUID
        let operation: UUID
        let deadline: Date
    }
    private var queue: [UUID] = []
    private var active: [UUID: Ticket] = [:]
    private var refreshed: [UUID: Date] = [:]
    private(set) var failed = Set<UUID>()
    var busy: Bool { !queue.isEmpty || !active.isEmpty }
    mutating func enqueue(_ ids: [UUID]) {
        guard !busy else { return }
        var seen = Set<UUID>(); queue = ids.prefix(4800).filter { seen.insert($0).inserted }
    }
    mutating func next(now: Date = Date()) -> Ticket? {
        guard active.count < 8, !queue.isEmpty else { return nil }
        let id = queue.removeFirst(); let ticket = Ticket(characteristic: id, operation: UUID(), deadline: now.addingTimeInterval(12))
        active[id] = ticket; return ticket
    }
    @discardableResult mutating func complete(_ ticket: Ticket, success: Bool, now: Date = Date()) -> Bool {
        guard active[ticket.characteristic] == ticket else { return false }
        active[ticket.characteristic] = nil
        if success && now <= ticket.deadline { refreshed[ticket.characteristic] = now; failed.remove(ticket.characteristic) }
        else { refreshed[ticket.characteristic] = nil; failed.insert(ticket.characteristic) }
        return true
    }
    mutating func expire(now: Date = Date()) {
        for ticket in active.values.filter({ $0.deadline < now }) { complete(ticket, success: false, now: now) }
        refreshed = refreshed.filter { now.timeIntervalSince($0.value) <= 120 }
    }
    mutating func event(_ id: UUID, now: Date = Date()) { refreshed[id] = now; failed.remove(id) }
    func fresh(_ id: UUID, now: Date = Date()) -> Bool { refreshed[id].map { now.timeIntervalSince($0) <= 120 } ?? false }
    mutating func reset() { queue = []; active = [:]; refreshed = [:]; failed = [] }
}

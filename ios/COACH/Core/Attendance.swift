import SwiftUI

/// Who came to training (Attendance.java). The coach's marks live in their own small doc per session,
/// config/att_<sessionId> = {sessionId, marks:{athleteId: true|false}}, so marking never rewrites the session.
/// Without a mark: a logged result counts as present; a past session with something to log counts as absent;
/// today's and future sessions stay open. A session only counts for an athlete from their first result or mark on,
/// and only when it was meant for them (whole team, or the group they were in on that day).
@MainActor
enum Attendance {
    static let unset = 0, yes = 1, no = 2

    static func docId(_ sessionId: String) -> String { "att_" + sessionId }

    static func mark(_ s: Store, _ sessionId: String, _ athleteId: String) -> Bool? {
        let m = s.doc(Store.config, docId(sessionId))?["marks"] ?? .null
        if !m.has(athleteId) { return nil }
        return m.bool(athleteId)
    }

    /// Saves the coach's mark; nil removes it (back to automatic).
    static func set(_ s: Store, _ sessionId: String, _ athleteId: String, _ present: Bool?) {
        let d = s.doc(Store.config, docId(sessionId))
        var m = d?["marks"] ?? .object()
        if !m.isObject { m = .object() }
        if let p = present { m[athleteId] = .bool(p) } else { m.remove(athleteId) }
        if m.keys.isEmpty {
            if d != nil { s.delete(Store.config, docId(sessionId)) }
            return
        }
        s.put(Store.config, ["id": .str(docId(sessionId)), "sessionId": .str(sessionId), "marks": m])
    }

    static func forget(_ s: Store, _ sessionId: String) {
        if s.doc(Store.config, docId(sessionId)) != nil { s.delete(Store.config, docId(sessionId)) }
    }

    static func logged(_ s: Store, _ session: JSON, _ athleteId: String) -> Bool {
        logged(session, s.doc(Store.results, Model.resultId(session.string("id"), athleteId)))
    }

    private static func logged(_ session: JSON, _ result: JSON?) -> Bool {
        guard let r = result else { return false }
        return Model.totals(session, r).done > 0
    }

    /// Has a rep, set or run to log (a session of notes only doesn't count unless the coach marks it).
    static func loggable(_ session: JSON) -> Bool {
        session["items"].list.contains { ["run", "gym", "gps"].contains($0.string("type")) }
    }

    // MARK: one pass over the data

    @MainActor
    struct Snapshot {
        let sessions: [JSON]
        var marks: [String: JSON] = [:]
        let known: Set<String>
        let moves: [JSON]
        let store: Store

        init(_ s: Store) {
            store = s
            sessions = s.all(Store.sessions).sorted { $0.string("date") < $1.string("date") }
            for c in s.all(Store.config) where c.string("id").hasPrefix("att_") && c["marks"].isObject {
                marks[c.string("sessionId")] = c["marks"]
            }
            known = Set(Groups.all(s).map { $0.string("id") })
            moves = Groups.moves(s)
        }

        func mark(_ session: JSON, _ athleteId: String) -> Bool? {
            guard let m = marks[session.string("id")], m.has(athleteId) else { return nil }
            return m.bool(athleteId)
        }
    }

    @MainActor
    struct Person {
        let id: String
        let group: String
        var results: [String: JSON] = [:]
        var start: String?

        init(_ d: Snapshot, _ athleteId: String) {
            id = athleteId
            group = Groups.of(d.store, athleteId)
            for r in d.store.where(Store.results, "athleteId", athleteId) { results[r.string("sessionId")] = r }
            for x in d.sessions where d.mark(x, athleteId) != nil || Attendance.logged(x, results[x.string("id")]) {
                start = x.string("date")
                break
            }
        }
    }

    static func status(_ d: Snapshot, _ p: Person, _ x: JSON, _ today: String) -> Int {
        let date = x.string("date")
        if let m = d.mark(x, p.id) { return m ? yes : no }
        if logged(x, p.results[x.string("id")]) { return yes }
        guard let start = p.start, date >= start else { return unset }
        if date >= today || !loggable(x) { return unset }
        if x["groups"].isArray {
            let then = Groups.groupOn(d.moves, p.id, date, p.group)
            var any = false, mine = false
            for g in x["groups"].list.map({ $0.asString }) where d.known.contains(g) {
                any = true
                if g == then { mine = true }
            }
            if !any || !mine { return unset }
        }
        return no
    }

    static func forSession(_ s: Store, _ session: JSON, _ team: [JSON], _ today: String) -> [Int] {
        let d = Snapshot(s)
        return team.map { status(d, Person(d, $0.string("id")), session, today) }
    }

    struct Tally {
        var yes = 0, no = 0
        /// Statuses of counted sessions, oldest first.
        var days: [Int] = []
        var total: Int { yes + no }
        var pct: Int { total == 0 ? -1 : Int((Double(yes) * 100 / Double(total)).rounded()) }
    }

    static func tally(_ s: Store, _ athleteId: String, _ from: String?, _ today: String) -> Tally {
        tally(Snapshot(s), athleteId, from, today)
    }

    static func tally(_ d: Snapshot, _ athleteId: String, _ from: String?, _ today: String) -> Tally {
        let p = Person(d, athleteId)
        var t = Tally()
        guard let start = p.start else { return t }
        for x in d.sessions {
            let date = x.string("date")
            if date > today { break }
            if date < start || (from != nil && date < from!) { continue }
            let st = status(d, p, x, today)
            if st == yes { t.yes += 1 } else if st == no { t.no += 1 } else { continue }
            t.days.append(st)
        }
        return t
    }

    static func tallies(_ s: Store, _ team: [JSON], _ from: String?, _ today: String) -> [Tally] {
        let d = Snapshot(s)
        return team.map { tally(d, $0.string("id"), from, today) }
    }

    /// First day of the last n days, nil for everything.
    static func from(_ days: Int) -> String? { days <= 0 ? nil : Fmt.iso(Fmt.addDays(Date(), -(days - 1))) }

    static func color(_ pct: Int) -> Color { pct < 0 ? C.muted : pct >= 80 ? C.green : pct >= 50 ? C.coral : C.red }
}

/// The last sessions as dots, oldest on the left: green came, red missed.
struct AttendanceDots: View {
    let tally: Attendance.Tally
    var max = 20
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tally.days.suffix(max).enumerated()), id: \.offset) { _, st in
                Circle()
                    .fill(st == Attendance.yes ? C.green : C.white)
                    .overlay(Circle().stroke(st == Attendance.yes ? C.green : C.red, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

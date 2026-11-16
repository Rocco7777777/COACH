import Foundation

/// Team leaderboards (Boards.java): one board per exercise or distance, built from the same series as Napredak.
///   Napredak: trend now against the trend a year earlier (or the first result), in %.
///   Najbolji rezultat: best result in the last 12 months (gym = estimated 1RM).
/// The arrow is the change of place against the same board 7 days ago, only for whoever trained it in those 7 days.
@MainActor
enum Boards {
    struct Row {
        var id = "", name = ""
        var value = 0.0
        var sub = ""
        var place = 0, move = 0
        var me = false
    }

    struct Board {
        var key = "", name = ""
        var series: Progress.Series
        var rows: [Row] = []
        var mine: Row? { rows.first { $0.me } }
    }

    /// An athlete's boards: teammates' results come from the server (team_board), mine from this phone.
    static func forTeam(_ store: Store, prog: Bool) -> [Board] {
        // the coach's phone has every athlete's results; so has the demo
        let me = Prefs.isCoach ? "" : Prefs.athleteId
        let local = store.demo || Prefs.isCoach
        var names: [(String, String)] = Groups.boardTeam(store, me).map { ($0.string("id"), $0.string("name")) }
        if !me.isEmpty && !names.contains(where: { $0.0 == me }) { names.append((me, Prefs.name)) }
        var theirs: [String: [JSON]] = [:]
        if !local {
            for r in store.boardResults() { theirs[r.string("athleteId"), default: []].append(r) }
        }
        var series: [String: [Progress.Series]] = [:]
        for (id, _) in names {
            let rs = local || id == me ? store.where(Store.results, "athleteId", id) : (theirs[id] ?? [])
            series[id] = Progress.build(store, id, rs)
        }
        return build(names, series, me, prog, Progress.todayDay())
    }

    static func build(_ names: [(String, String)], _ series: [String: [Progress.Series]], _ me: String, _ prog: Bool, _ today: Int) -> [Board] {
        var byKey: [String: [Progress.Series]] = [:]
        var who: [String: [String]] = [:]
        var firsts: [Progress.Series] = []
        for (id, _) in names {
            guard let m = series[id] else { continue }
            for s in m {
                if byKey[s.key] == nil {
                    byKey[s.key] = []
                    who[s.key] = []
                    firsts.append(s)
                }
                byKey[s.key]!.append(s)
                who[s.key]!.append(id)
            }
        }
        firsts.sort(by: Progress.order)
        let nameOf = Dictionary(names, uniquingKeysWith: { a, _ in a })
        var out: [Board] = []
        for first in firsts {
            let ss = byKey[first.key]!, ids = who[first.key]!
            var now = rank(first, ss, ids, nameOf, me, today, prog)
            if now.count < 2 { continue }
            var before: [String: Int] = [:]
            for r in rank(first, ss, ids, nameOf, me, today - 7, prog) { before[r.id] = r.place }
            for i in now.indices {
                guard let idx = ids.firstIndex(of: now[i].id) else { continue }
                let active = ss[idx].pts.contains { $0.day > today - 7 && $0.day <= today }
                if active, let b = before[now[i].id] { now[i].move = b - now[i].place } else { now[i].move = 0 }
            }
            out.append(Board(key: first.key, name: displayName(ss), series: first, rows: now))
        }
        return out
    }

    private static func displayName(_ ss: [Progress.Series]) -> String {
        var n: [String: Int] = [:]
        var best = ss[0].name
        for s in ss {
            n[s.name, default: 0] += 1
            if n[s.name]! > (n[best] ?? 0) { best = s.name }
        }
        return best
    }

    private static func rank(_ kind: Progress.Series, _ ss: [Progress.Series], _ ids: [String], _ names: [String: String],
                             _ me: String, _ asOf: Int, _ prog: Bool) -> [Row] {
        var rows: [Row] = []
        for (i, s) in ss.enumerated() {
            guard var r = score(s, asOf, prog) else { continue }
            r.id = ids[i]
            let nm = (names[r.id] ?? "").trimmingCharacters(in: .whitespaces)
            r.name = nm.isEmpty ? "Sportaš" : nm
            r.me = r.id == me
            rows.append(r)
        }
        rows.sort { a, b in
            if prog { return a.value > b.value }
            return kind.lower ? a.value < b.value : a.value > b.value
        }
        for i in rows.indices { rows[i].place = i + 1 }
        if !prog && kind.kind != Progress.gym && rows.count > 1 {
            let lead = rows[0].value
            for i in rows.indices {
                rows[i].sub = i == 0 ? gap(kind, rows[1].value - rows[i].value) + " ispred" : "+" + gap(kind, rows[i].value - lead)
            }
        }
        return rows
    }

    static func score(_ s: Progress.Series, _ asOf: Int, _ prog: Bool) -> Row? {
        var pts = s.pts.filter { $0.v > 0 && $0.day <= asOf }
        var r = Row()
        if prog {
            if pts.count < 2 { return nil }
            Progress.trend(&pts)
            let now = pts[pts.count - 1].tr
            var ago: Progress.Pt? = nil
            for p in pts where p.day <= asOf - 365 { ago = p }
            let a = ago ?? pts[0]
            if a.tr <= 0 { return nil }
            r.value = (s.lower ? a.tr - now : now - a.tr) / a.tr * 100
            r.sub = s.fmt(a.tr) + " → " + s.fmt(now) + unit(s)
            return r
        }
        var best: Progress.Pt? = nil
        for p in pts where p.day > asOf - 365 { if best == nil || s.better(p.v, best!.v) { best = p } }
        guard let b = best else { return nil }
        r.value = b.v
        if s.kind == Progress.gym { r.sub = b.set }
        return r
    }

    static func value(_ b: Board, _ r: Row, _ prog: Bool) -> String {
        prog ? pct(r.value) : b.series.fmt(r.value) + unit(b.series)
    }

    static func pct(_ v: Double) -> String {
        let n = String(format: "%.1f", abs(v)).replacingOccurrences(of: ".", with: ",")
        return (v > 0.05 ? "+" : v < -0.05 ? "−" : "±") + n + " %"
    }

    static func unit(_ s: Progress.Series) -> String {
        s.kind == Progress.gym ? " kg" : s.kind == Progress.run ? " s" : "/km"
    }

    private static func gap(_ s: Progress.Series, _ d: Double) -> String {
        if s.kind == Progress.gps { return Fmt.clock(abs(d)) + "/km" }
        return Progress.sec(abs(d)) + " s"
    }
}

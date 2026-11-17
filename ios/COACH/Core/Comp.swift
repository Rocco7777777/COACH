import Foundation

/// Competition disciplines and results. The coach sets them up and types the results in.
///   config/disciplines   = {id: "disciplines",
///                           list: [{id, name, unit}]           unit "s" = time (lower is better), "m" = metres, "pts" = points
///                           of:   {athleteId: [disciplineId]}}  what each athlete competes in
///   results/comp_<athleteId> = {id, athleteId, athleteName, comp: true,
///                               results: [{id, d: disciplineId, date: "yyyy-MM-dd", v: seconds | metres | points, meet}]}
/// The results sit with the athlete's other results on purpose: the athlete reads their own, teammates get
/// them through team_board like training results, and deleting the account deletes them (no SQL change).
/// Every discipline is a series "comp:<id>", like an exercise: a graph in Napredak and its own leaderboard.
enum Comp {
    static let doc = "disciplines"
    static let time = "s", length = "m", points = "pts"
    static let units = [time, length, points]
    static let unitNames = ["Vrijeme", "Metri", "Bodovi"]

    /// Offered when the coach adds a discipline.
    static let presets: [(String, String)] = [
        ("60 m", time), ("100 m", time), ("200 m", time), ("400 m", time), ("800 m", time), ("1500 m", time),
        ("3000 m", time), ("5000 m", time), ("10 000 m", time), ("60 m prepone", time), ("100 m prepone", time),
        ("110 m prepone", time), ("400 m prepone", time), ("3000 m zapreke", time), ("Polumaraton", time), ("Maraton", time),
        ("Skok u dalj", length), ("Troskok", length), ("Skok u vis", length), ("Skok s motkom", length),
        ("Kugla", length), ("Disk", length), ("Koplje", length), ("Kladivo", length),
        ("Sedmoboj", points), ("Desetoboj", points),
    ]

    static func key(_ id: String) -> String { "comp:" + id }

    /// The doc with one athlete's competition results.
    static func resultsId(_ athleteId: String) -> String { "comp_" + athleteId }

    /// The results in such a doc as stored: [{id, d, date, v, meet}].
    static func rows(_ doc: JSON?) -> [JSON] { (doc?["results"].list ?? []).filter { $0.isObject } }
    static func lower(_ unit: String) -> Bool { unit == time }

    static func unitName(_ unit: String) -> String {
        if let i = units.firstIndex(of: unit) { return unitNames[i].lowercased() }
        return ""
    }

    // MARK: formatting

    /// 10.84 → "10,84", 112.3 → "1:52,30", 9930 → "2:45:30"; metres "7,45"; points "7256".
    static func fmt(_ unit: String, _ v: Double) -> String {
        switch unit {
        case time: return clock(v)
        case length: return String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
        default: return String(Int64(v.rounded()))
        }
    }

    static func clock(_ v: Double) -> String {
        let hund = Int((max(0, v) * 100).rounded())
        let h = hund / 360000, m = (hund % 360000) / 6000, s = (hund % 6000) / 100, c = hund % 100
        if h > 0 { return "\(h):" + two(m) + ":" + two(s) }
        if m > 0 { return "\(m):" + two(s) + "," + two(c) }
        return "\(s)," + two(c)
    }

    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// What follows a formatted value: " s" for times under a minute, " m", " bod."
    static func suffix(_ unit: String, _ v: Double) -> String {
        switch unit {
        case time: return v < 60 ? " s" : ""
        case length: return " m"
        default: return " bod."
        }
    }

    static func text(_ unit: String, _ v: Double) -> String { fmt(unit, v) + suffix(unit, v) }

    /// Metres or points as typed ("7,45", "7256"); nil when it isn't a number above zero.
    static func parse(_ raw: String) -> Double? {
        let v = Fmt.num(raw)
        return v > 0 ? (v * 100).rounded() / 100 : nil
    }

    /// "2026-06-14" → "14.6.2026."
    static func day(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? "\(p[2]).\(p[1]).\(p[0])." : iso
    }

    /// The best result of one calendar year, nil when there was none.
    static func seasonBest(_ s: Progress.Series, _ year: Int) -> Progress.Pt? {
        var b: Progress.Pt? = nil
        for p in s.pts where p.v > 0 && Progress.dateComponents(p.day).year == year {
            if b == nil || s.better(p.v, b!.v) { b = p }
        }
        return b
    }

    static func thisYear() -> Int { Progress.dateComponents(Progress.todayDay()).year ?? 0 }

    /// Under the discipline's name in a list: "OR 10,84 s  ·  sezona 10,91 s".
    static func rowText(_ s: Progress.Series) -> String {
        guard let b = s.best else { return "" }
        var t = "OR " + text(s.cunit, b.v)
        if let sb = seasonBest(s, thisYear()) { t += "  ·  sezona " + text(s.cunit, sb.v) }
        return t
    }

    // MARK: reads

    @MainActor
    static func root(_ s: Store) -> JSON {
        var d: JSON = s.doc(Store.config, doc) ?? ["id": .str(doc)]
        if !d["list"].isArray { d["list"] = .array() }
        if !d["of"].isObject { d["of"] = .object() }
        return d
    }

    @MainActor
    static func all(_ s: Store) -> [JSON] {
        let list: [JSON] = s.doc(Store.config, doc)?["list"].list ?? []
        return list.filter { $0.isObject && !$0.string("id").isEmpty }
    }

    @MainActor
    static func get(_ s: Store, _ id: String) -> JSON? { all(s).first { $0.string("id") == id } }

    @MainActor
    static func ids(_ s: Store, _ athleteId: String) -> [String] {
        let mine: [JSON] = s.doc(Store.config, doc)?["of"][athleteId].list ?? []
        return mine.map { $0.asString }
    }

    /// What the athlete competes in, in the coach's order.
    @MainActor
    static func of(_ s: Store, _ athleteId: String) -> [JSON] {
        let mine = Set(ids(s, athleteId))
        return all(s).filter { mine.contains($0.string("id")) }
    }

    @MainActor
    static func does(_ s: Store, _ athleteId: String, _ did: String) -> Bool { ids(s, athleteId).contains(did) }

    /// Results on this phone, newest first, each with "a" = the athlete; nil = everyone now in the team, or any discipline.
    @MainActor
    static func results(_ s: Store, athlete: String? = nil, discipline: String? = nil) -> [JSON] {
        let who: [String] = athlete.map { [$0] } ?? s.all(Store.athletes).map { $0.string("id") }
        var out: [JSON] = []
        for aid in who {
            for r in rows(s.doc(Store.results, resultsId(aid))) {
                if let d = discipline, r.string("d") != d { continue }
                var x = r
                x["a"] = .str(aid)
                out.append(x)
            }
        }
        return out.sorted { a, b in
            a.string("date") != b.string("date") ? a.string("date") > b.string("date") : a.string("id") > b.string("id")
        }
    }

    /// One series per discipline the athlete has a result in.
    @MainActor
    static func series(_ s: Store, _ athleteId: String) -> [Progress.Series] {
        series(s, doc: s.doc(Store.results, resultsId(athleteId)))
    }

    /// The same from the athlete's results doc itself: a teammate's comes from team_board, not from the store.
    @MainActor
    static func series(_ s: Store, doc: JSON?) -> [Progress.Series] {
        var out: [Progress.Series] = []
        let mine = rows(doc)
        if mine.isEmpty { return out }
        for d in all(s) {
            let did = d.string("id")
            let unit = d.string("unit", time)
            let ser = Progress.Series()
            ser.key = key(did)
            ser.kind = Progress.comp
            ser.name = d.string("name")
            ser.metric = "najbolji rezultat"
            ser.cunit = unit
            ser.lower = lower(unit)
            for r in mine where r.string("d") == did {
                guard let day = Progress.epochDay(r.string("date")) else { continue }
                let v = r.double("v")
                if v <= 0 { continue }
                var p = Progress.Pt()
                p.day = day
                p.v = v
                p.top = v
                let meet = r.string("meet").trimmingCharacters(in: .whitespaces)
                p.set = text(unit, v) + (meet.isEmpty ? "" : "  ·  " + meet)
                p.topSet = p.set
                // two results on one day: the better one stays
                if let i = ser.pts.firstIndex(where: { $0.day == day }) {
                    if ser.better(v, ser.pts[i].v) { ser.pts[i] = p }
                } else {
                    ser.pts.append(p)
                }
            }
            if ser.pts.isEmpty { continue }
            ser.pts.sort { $0.day < $1.day }
            let slowest: Double = ser.pts.map { $0.v }.max() ?? 0
            ser.unit = unit == time ? (slowest < 60 ? "s" : "") : unit == length ? "m" : "bod."
            out.append(ser)
        }
        return out
    }

    /// The best result in a discipline over everyone, nil without results.
    @MainActor
    static func top(_ s: Store, _ did: String) -> JSON? {
        guard let d = get(s, did) else { return nil }
        let low = lower(d.string("unit", time))
        var best: JSON? = nil
        for r in results(s, discipline: did) where r.double("v") > 0 {
            guard let b = best else { best = r; continue }
            let v: Double = r.double("v")
            let better: Bool = low ? v < b.double("v") : v > b.double("v")
            if better { best = r }
        }
        return best
    }

    /// Names of meets already typed in, newest first, each with its date: (meet, date).
    @MainActor
    static func meets(_ s: Store, _ max: Int) -> [(String, String)] {
        var out: [(String, String)] = []
        for r in results(s) {
            let m = r.string("meet").trimmingCharacters(in: .whitespaces)
            if m.isEmpty || out.contains(where: { $0.0 == m }) { continue }
            out.append((m, r.string("date")))
            if out.count >= max { break }
        }
        return out
    }

    @MainActor
    static func athleteName(_ s: Store, _ id: String) -> String {
        let n = s.doc(Store.athletes, id)?.string("name").trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "Sportaš" : n
    }

    // MARK: writes (coach)

    /// New discipline; returns its id. The same name twice gives the one that exists.
    @MainActor
    @discardableResult
    static func add(_ s: Store, _ name: String, _ unit: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let same = all(s).first(where: { $0.string("name").lowercased() == n.lowercased() }) { return same.string("id") }
        var d = root(s)
        let id = "d" + Fmt.id()
        var list = d["list"].list
        list.append(["id": .str(id), "name": .str(n), "unit": .str(unit)])
        d["list"] = .arr(list)
        s.put(Store.config, d)
        return id
    }

    @MainActor
    static func rename(_ s: Store, _ id: String, _ name: String) {
        var d = root(s)
        var list = d["list"].list
        for i in list.indices where list[i].string("id") == id { list[i]["name"] = .str(name.trimmingCharacters(in: .whitespaces)) }
        d["list"] = .arr(list)
        s.put(Store.config, d)
    }

    /// Removes the discipline with its results and takes it off every athlete.
    @MainActor
    static func delete(_ s: Store, _ id: String) {
        for at in s.all(Store.athletes) {
            guard var doc = s.doc(Store.results, resultsId(at.string("id"))) else { continue }
            let before = rows(doc)
            let keep = before.filter { $0.string("d") != id }
            if keep.count == before.count { continue }
            doc["results"] = .arr(keep)
            s.put(Store.results, doc)
        }
        var d = root(s)
        d["list"] = .arr(d["list"].list.filter { $0.string("id") != id })
        var of = JSON.object()
        for (a, v) in d["of"].dict {
            let keep = v.list.filter { $0.asString != id }
            if !keep.isEmpty { of[a] = .arr(keep) }
        }
        d["of"] = of
        s.put(Store.config, d)
    }

    /// The athlete competes in the discipline (on) or not any more; their results stay either way.
    @MainActor
    static func assign(_ s: Store, _ athleteId: String, _ did: String, _ on: Bool) {
        var d = root(s)
        var of = d["of"]
        var mine = of[athleteId].list.filter { $0.asString != did }
        if on { mine.append(.str(did)) }
        if mine.isEmpty { of.remove(athleteId) } else { of[athleteId] = .arr(mine) }
        d["of"] = of
        s.put(Store.config, d)
    }

    /// Adds a result; the athlete gets the discipline if they didn't have it.
    @MainActor
    static func addResult(_ s: Store, _ athleteId: String, _ did: String, _ date: String, _ v: Double, _ meet: String) {
        let id = resultsId(athleteId)
        var doc: JSON = s.doc(Store.results, id) ?? ["id": .str(id), "athleteId": .str(athleteId), "comp": true]
        doc["athleteName"] = .str(athleteName(s, athleteId))
        var list = rows(doc)
        list.append(["id": .str("r" + Fmt.id()), "d": .str(did), "date": .str(date),
                     "v": .num((v * 100).rounded() / 100), "meet": .str(meet.trimmingCharacters(in: .whitespaces))])
        doc["results"] = .arr(list)
        s.put(Store.results, doc)
        if !does(s, athleteId, did) { assign(s, athleteId, did, true) }
    }

    @MainActor
    static func deleteResult(_ s: Store, _ athleteId: String, _ rid: String) {
        guard var doc = s.doc(Store.results, resultsId(athleteId)) else { return }
        doc["results"] = .arr(rows(doc).filter { $0.string("id") != rid })
        s.put(Store.results, doc)
    }
}

import Foundation

/// Shapes of the stored documents, identical to the Android app (Model.java):
///
/// sessions: {id, date, title, notes, groups?, items:[item]}
///   run:  {id, type:"run", distance(m), reps, target, rest, start (blok|let|el), note}
///   gym:  {id, type:"gym", name, sets, reps, kg, rpe, unit ("s" = isometric hold), note}
///   gps:  {id, type:"gps", km, pace ("4:30"), note}
///   note: {id, type:"note", name, note}
///   any item may carry per:{athleteId:{field:value}}
/// results: {id: sessionId_athleteId, sessionId, athleteId, athleteName, date, entries:{itemId:[{t}|{kg,reps,rpe,done}|{km,s,manual}]}, comment, ts:{cell:millis}}
/// daily:   {id: athleteId_date, athleteId, athleteName, date, sleep, protein, creatine, vitamins:[..], wellness:{qid:answer}, wellnessLabels, wellnessDone}
/// config/questionnaire, config/groups, athletes {id, name}
enum Model {
    static let vitamins = ["Vitamin D", "Vitamin C", "Magnezij", "Omega-3", "Multivitamin", "Cink", "Željezo", "B12"]

    static func defaultQuestionnaire() -> JSON {
        var whereQ = multi("q_where", "Što je upaljeno?", ["Listovi", "Stražnja loža", "Prednja loža", "Kukovi", "Prepone", "Leđa", "Stopala", "Ramena"])
        whereQ["onlyIfYes"] = true
        let qs: [JSON] = [
            scale("q_sleep", "Kako si spavao/la?", "Loše", "Odlično"),
            scale("q_fatigue", "Koliko si odmoran/na?", "Iscrpljen", "Svjež"),
            ["id": "q_sore", "text": "Jesi li upaljen/a?", "type": "yesno"],
            whereQ,
            scale("q_mood", "Kako si raspoložen/a?", "Loše", "Super"),
            scale("q_stress", "Razina stresa", "Puno", "Nimalo"),
            ["id": "q_note", "text": "Nešto za trenera? (nije obavezno)", "type": "text"],
        ]
        return ["id": "questionnaire", "questions": .arr(qs)]
    }

    static func scale(_ id: String, _ text: String, _ low: String, _ high: String) -> JSON {
        ["id": .str(id), "text": .str(text), "type": "scale", "low": .str(low), "high": .str(high)]
    }

    static func multi(_ id: String, _ text: String, _ opts: [String]) -> JSON {
        ["id": .str(id), "text": .str(text), "type": "multi", "options": .arr(opts.map { .str($0) })]
    }

    static func resultId(_ sessionId: String, _ athleteId: String) -> String { sessionId + "_" + athleteId }
    static func dailyId(_ athleteId: String, _ date: String) -> String { athleteId + "_" + date }

    // MARK: per-athlete numbers

    static func perFields(_ type: String) -> [String] {
        switch type {
        case "gym": return ["sets", "reps", "kg", "rpe"]
        case "run": return ["distance", "reps", "target"]
        case "gps": return ["km", "pace"]
        default: return []
        }
    }

    /// The coach's own numbers for this athlete on this item, or nil when they do the plan.
    static func own(_ item: JSON, _ athleteId: String) -> JSON? {
        let o = item["per"][athleteId]
        guard o.isObject else { return nil }
        for k in perFields(item.string("type")) where !o.string(k).trimmingCharacters(in: .whitespaces).isEmpty { return o }
        return nil
    }

    /// The item as this athlete does it: the plan with the coach's numbers for them on top.
    static func forAthlete(_ item: JSON, _ athleteId: String) -> JSON {
        guard let o = own(item, athleteId) else { return item }
        var c = item
        for k in perFields(item.string("type")) {
            let v = o.string(k).trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { c[k] = .str(v) }
        }
        if otherDistance(item, o) && o.string("target").trimmingCharacters(in: .whitespaces).isEmpty { c.remove("target") }
        if otherDistance(item, o) && Fmt.num(c.string("distance")) > 200 { c.remove("start") }
        return c
    }

    static func few(_ n: Int) -> Bool {
        let t = n % 10, h = n % 100
        return t >= 2 && t <= 4 && (h < 12 || h > 14)
    }

    static func otherDistance(_ item: JSON, _ o: JSON) -> Bool {
        guard item.string("type") == "run" else { return false }
        let d = o.string("distance").trimmingCharacters(in: .whitespaces)
        return !d.isEmpty && Fmt.num(d) != Fmt.num(item.string("distance"))
    }

    /// Only what differs for this athlete: "110 kg  ·  6 pon.  ·  @8,5".
    static func ownText(_ item: JSON, _ athleteId: String) -> String {
        guard let o = own(item, athleteId) else { return "" }
        let type = item.string("type")
        var parts: [String] = []
        for k in perFields(type) {
            let v = o.string(k).trimmingCharacters(in: .whitespaces)
            if v.isEmpty { continue }
            if type == "gym" {
                switch k {
                case "sets": parts.append(v + (few(Int(Fmt.num(v))) ? " serije" : " serija"))
                case "reps": parts.append(v + (hold(item) ? " s" : " pon."))
                case "kg": parts.append(v + " kg")
                default: parts.append("@" + v)
                }
            } else if type == "run" {
                parts.append(k == "distance" ? distance(v) : k == "reps" ? v + "×" : "prolaz " + v)
            } else {
                parts.append(k == "km" ? Fmt.n(Fmt.num(v)) + " km" : "tempo " + v + "/km")
            }
        }
        var s = parts.joined(separator: "  ·  ")
        if otherDistance(item, o) && o.string("target").trimmingCharacters(in: .whitespaces).isEmpty && !item.string("target").trimmingCharacters(in: .whitespaces).isEmpty {
            s += "  ·  bez prolaza"
        }
        return s
    }

    static func hold(_ item: JSON) -> Bool { item.string("unit") == "s" }

    static func setText(_ item: JSON, _ e: JSON, rpe: Bool) -> String {
        var s = e.string("kg") + "×" + e.string("reps") + (hold(item) ? " s" : "")
        if rpe && !e.string("rpe").isEmpty { s += " @" + e.string("rpe") }
        return s
    }

    static func title(_ item: JSON) -> String {
        switch item.string("type") {
        case "run":
            let dist = distance(item.string("distance"))
            let reps = Int(Fmt.num(item.string("reps")))
            return reps > 1 ? "\(dist) × \(reps)" : dist
        case "gps": return Fmt.n(Fmt.num(item.string("km"))) + " km"
        default: return item.string("name")
        }
    }

    static func distance(_ meters: String) -> String {
        let m = Fmt.num(meters)
        if m >= 1000 && m.truncatingRemainder(dividingBy: 100) == 0 { return Fmt.n(m / 1000) + " km" }
        return Fmt.n(m) + "m"
    }

    /// Plan line under the headline.
    static func plan(_ item: JSON) -> String {
        var b = ""
        func add(_ s: String) { b += (b.isEmpty ? "" : "  ·  ") + s }
        switch item.string("type") {
        case "run":
            let start = Progress.startName(item.string("start"))
            if !start.isEmpty { add(start) }
            if !item.string("target").isEmpty { add("prolaz " + item.string("target")) }
            if !item.string("rest").isEmpty { add("pauza " + item.string("rest")) }
        case "gps":
            if !item.string("pace").isEmpty { add("tempo " + item.string("pace") + "/km") }
        case "gym":
            let sets = item.string("sets"), reps = item.string("reps")
            if !sets.isEmpty || !reps.isEmpty { b = (sets.isEmpty ? "?" : sets) + " × " + (reps.isEmpty ? "?" : reps) + (hold(item) ? " s" : "") }
            if !item.string("kg").isEmpty { b += "  ·  " + item.string("kg") + " kg" }
            if !item.string("rpe").isEmpty { b += "  ·  @" + item.string("rpe") }
        default: break
        }
        return b
    }

    /// RPE explained: @8 means 2 reps in reserve.
    static func rir(_ rpe: String) -> String {
        let v = Fmt.num(rpe)
        if v <= 0 { return "" }
        return Fmt.n(10 - v) + " u rezervi"
    }

    static func entries(_ result: JSON?, _ itemId: String) -> [JSON] {
        guard let r = result else { return [] }
        return r["entries"][itemId].list
    }

    /// Totals of one athlete's result for one session: (km, kg lifted, reps done).
    static func totals(_ session: JSON?, _ result: JSON?) -> (km: Double, kg: Double, done: Double) {
        guard let s = session, let r = result else { return (0, 0, 0) }
        var km = 0.0, kg = 0.0, done = 0.0
        let athleteId = r.string("athleteId")
        for raw in s["items"].list where raw.isObject {
            let it = forAthlete(raw, athleteId)
            let en = entries(r, it.string("id"))
            switch it.string("type") {
            case "run":
                let dist = Fmt.num(it.string("distance"))
                let cap = min(en.count, max(1, Int(Fmt.num(it.string("reps")))))
                for k in 0..<max(0, cap) where Fmt.parseTime(en[k].string("t")) > 0 {
                    km += dist / 1000
                    done += 1
                }
            case "gps":
                if let e = en.first, e.double("km") > 0 {
                    km += e.double("km")
                    done += 1
                }
            case "gym":
                let cap = min(en.count, max(1, Int(Fmt.num(it.string("sets")))))
                for k in 0..<max(0, cap) where en[k].bool("done") {
                    if !hold(it) { kg += Fmt.num(en[k].string("kg")) * Fmt.num(en[k].string("reps")) }
                    done += 1
                }
            default: break
            }
        }
        return (km, kg, done)
    }

    /// The recorded run for a gps item, or nil.
    static func run(_ result: JSON?, _ itemId: String) -> JSON? {
        guard let e = entries(result, itemId).first, e.double("km") > 0 else { return nil }
        return e
    }

    static func runLine(_ run: JSON) -> String {
        let km = run.double("km"), s = run.double("s")
        return Fmt.km(km) + " km  ·  " + Fmt.clock(s) + (km > 0.05 ? "  ·  " + Fmt.clock(s / km) + "/km" : "")
    }

    static func recorded(_ run: JSON?) -> Bool { (run?["path"].count ?? 0) > 1 }

    /// Colour level for a pace against the coach's target: 0 none, 1 good, 2 a bit slow, 3 slow.
    static func paceLevel(_ pace: Double, _ target: Double) -> Int {
        if pace <= 0 || target <= 0 { return 0 }
        if pace <= target + 3 { return 1 }
        if pace <= target + 15 { return 2 }
        return 3
    }
}

/// Per-cell merge of one result doc written from two devices (Results.java).
enum Results {
    static let comment = "comment"

    static func cell(_ itemId: String, _ i: Int) -> String { "\(itemId)/\(i)" }

    static func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    static func touch(_ result: inout JSON, _ key: String) {
        result["ts"][key] = .num(nowMs())
    }

    static func edited(_ result: JSON?, _ key: String) -> Bool { (result?["ts"].long(key) ?? 0) > 0 }

    static func mergeable(_ d: JSON?) -> Bool {
        guard let d = d, d.isObject else { return false }
        return !d.bool("history") && d.has("sessionId")
    }

    static func empty(_ c: JSON?) -> Bool {
        guard let c = c, c.isObject else { return true }
        return c.string("t").isEmpty && !c.bool("done") && c.double("km") <= 0
    }

    /// mine merged over theirs: newer cell wins; mine wins ties between two filled cells.
    static func merge(_ mine: JSON, _ theirs: JSON?) -> JSON {
        guard let theirs = theirs, mergeable(mine), mergeable(theirs) else { return mine }
        var out = theirs
        for (k, v) in mine.dict where k != "entries" && k != "ts" && k != comment { out[k] = v }
        let tm = mine["ts"], tt = theirs["ts"]
        var ts = JSON.object()
        let em = mine["entries"], et = theirs["entries"]
        var en = JSON.object()
        var items: [String] = []
        for k in et.keys where !items.contains(k) { items.append(k) }
        for k in em.keys where !items.contains(k) { items.append(k) }
        for item in items {
            let am = em[item], at = et[item]
            let n = max(am.count, at.count)
            var a: [JSON] = []
            for i in 0..<n {
                let key = cell(item, i)
                let cm = am[i].isObject ? am[i] : nil, ct = at[i].isObject ? at[i] : nil
                let m = tm.long(key), t = tt.long(key)
                let takeMine = m != t ? m > t : !(empty(cm) && !empty(ct))
                a.append((takeMine ? cm : ct) ?? .object())
                if max(m, t) > 0 { ts[key] = .num(Double(max(m, t))) }
            }
            en[item] = .arr(a)
        }
        out["entries"] = en
        let m = tm.long(comment), t = tt.long(comment)
        let cm = mine.string(comment), ct = theirs.string(comment)
        let takeMine = m != t ? m > t : !(cm.isEmpty && !ct.isEmpty)
        out[comment] = .str(takeMine ? cm : ct)
        if max(m, t) > 0 { ts[comment] = .num(Double(max(m, t))) }
        out["ts"] = ts
        return out
    }
}

/// Groups inside one team (Groups.java), the parts an athlete's phone needs.
@MainActor
enum Groups {
    static let doc = "groups"

    static func all(_ s: Store) -> [JSON] {
        (s.doc(Store.config, doc)?["groups"].list ?? []).filter { $0.isObject && !$0.string("id").isEmpty }
    }

    static func any(_ s: Store) -> Bool { !all(s).isEmpty }

    static func get(_ s: Store, _ gid: String) -> JSON? {
        if gid.isEmpty { return nil }
        return all(s).first { $0.string("id") == gid }
    }

    static func name(_ s: Store, _ gid: String) -> String { get(s, gid)?.string("name") ?? "" }

    static func of(_ s: Store, _ athleteId: String) -> String {
        for g in all(s) where g["members"].list.contains(where: { $0.asString == athleteId && !athleteId.isEmpty }) { return g.string("id") }
        return ""
    }

    static func members(_ s: Store, _ gid: String) -> [JSON] {
        guard let g = get(s, gid) else { return [] }
        let m = g["members"].list.map { $0.asString }
        return s.all(Store.athletes).filter { m.contains($0.string("id")) }.sorted { $0.string("name") < $1.string("name") }
    }

    static func ofSession(_ s: Store, _ session: JSON?) -> [String] {
        guard let session = session else { return [] }
        let known = Set(all(s).map { $0.string("id") })
        var out: [String] = []
        for g in session["groups"].list {
            let id = g.asString
            if known.contains(id) && !out.contains(id) { out.append(id) }
        }
        return out
    }

    static func meantFor(_ s: Store, _ session: JSON, _ athleteId: String) -> Bool {
        let gs = ofSession(s, session)
        return gs.isEmpty || gs.contains(of(s, athleteId))
    }

    static func sees(_ s: Store, _ session: JSON, _ athleteId: String) -> Bool {
        if meantFor(s, session, athleteId) || of(s, athleteId).isEmpty { return true }
        return s.doc(Store.results, Model.resultId(session.string("id"), athleteId)) != nil
    }

    static func visible(_ s: Store, _ athleteId: String, _ sessions: [JSON]) -> [JSON] {
        if !any(s) { return sessions }
        return sessions.filter { sees(s, $0, athleteId) }
    }

    /// Whose results go on the athlete's leaderboards: their group, or the whole team.
    static func boardTeam(_ s: Store, _ me: String) -> [JSON] {
        let everyone = s.all(Store.athletes)
        if !any(s) { return everyone }
        let gid = of(s, me)
        return gid.isEmpty ? everyone : members(s, gid)
    }
}

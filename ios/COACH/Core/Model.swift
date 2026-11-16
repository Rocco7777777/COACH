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

    /// One logged gym set, reps first: "5 pon.  ·  100 kg  ·  @8", "30 s  ·  40 kg"; the RPE only when asked for.
    static func setText(_ item: JSON, _ e: JSON, rpe: Bool) -> String {
        let reps = e.string("reps").trimmingCharacters(in: .whitespaces)
        return (reps.isEmpty ? "?" : number(reps)) + (hold(item) ? " s" : " pon.") + kgRpe(e, rpe)
    }

    /// The ticked sets of one gym item the way the coach writes the plan: sets, reps, kg, RPE.
    /// Equal sets in a row are merged: ["3 × 5  ·  100 kg  ·  @8", "1 × 4  ·  102,5 kg  ·  @9"].
    static func setLines(_ item: JSON, _ en: [JSON], rpe: Bool) -> [String] {
        var out: [String] = []
        var last: String?
        var n = 0
        for e in en where e.isObject && e.bool("done") {
            let reps = e.string("reps").trimmingCharacters(in: .whitespaces)
            let tail = (reps.isEmpty ? "?" : number(reps)) + (hold(item) ? " s" : "") + kgRpe(e, rpe)
            if tail == last {
                n += 1
                continue
            }
            if let l = last { out.append("\(n) × " + l) }
            last = tail
            n = 1
        }
        if let l = last { out.append("\(n) × " + l) }
        return out
    }

    /// "  ·  100 kg  ·  @8" (no kg part for body weight, no @ when not asked for).
    private static func kgRpe(_ e: JSON, _ rpe: Bool) -> String {
        var s = ""
        if Fmt.num(e.string("kg")) > 0 { s += "  ·  " + number(e.string("kg")) + " kg" }
        if rpe && Fmt.num(e.string("rpe")) > 0 { s += "  ·  @" + number(e.string("rpe")) }
        return s
    }

    /// "102.5" → "102,5", "100" → "100"; anything that isn't a number stays as typed.
    static func number(_ v: String) -> String {
        let t = v.trimmingCharacters(in: .whitespaces)
        guard let d = Decimal(string: t.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
              t.range(of: "^-?[0-9]*[.,]?[0-9]+$", options: .regularExpression) != nil else { return t }
        return NSDecimalNumber(decimal: d).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    /// "Ivan K., Petra N." – athletes with their own numbers somewhere in the session.
    static func ownNames(_ session: JSON?, _ athletes: [JSON]) -> String {
        guard let items = session?["items"].list else { return "" }
        var out: [String] = []
        for at in athletes {
            let id = at.string("id")
            if items.contains(where: { own($0, id) != nil }) { out.append(Fmt.shortName(at.string("name"))) }
        }
        return out.joined(separator: ", ")
    }

    static func findItem(_ session: JSON?, _ itemId: String) -> JSON? {
        session?["items"].list.first { $0.isObject && $0.string("id") == itemId }
    }

    /// Season totals of one athlete: km, kg, sessions with something logged.
    @MainActor
    static func season(_ s: Store, _ athleteId: String) -> (km: Double, kg: Double, n: Double) {
        var km = 0.0, kg = 0.0, n = 0.0
        for r in s.where(Store.results, "athleteId", athleteId) {
            let t = totals(s.doc(Store.sessions, r.string("sessionId")), r)
            km += t.km
            kg += t.kg
            if t.done > 0 { n += 1 }
        }
        return (km, kg, n)
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

/// Groups inside one team (Groups.java): config/groups = {groups:[{id, name, members:[athleteId]}], moves:[{a, g, d}]}.
/// A session with session.groups = [groupId] is for those groups only; without the field it is for the whole team.
/// An athlete is in at most one group; one without a group sees every session. moves logs every change of group
/// ("" date = from the start), so attendance judges each past session by the group the athlete was in on that day.
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
        for g in all(s) where has(g["members"], athleteId) { return g.string("id") }
        return ""
    }

    static func moves(_ s: Store) -> [JSON] { s.doc(Store.config, doc)?["moves"].list ?? [] }

    /// The athlete's group on that date by the move log. A move counts from the day after it was made.
    /// Without any logged move: their group now.
    static func groupOn(_ moves: [JSON], _ athleteId: String, _ date: String, _ now: String) -> String {
        var g: String?
        for m in moves where m.isObject && m.string("a") == athleteId {
            if g == nil { g = "" }
            if m.string("d") < date { g = m.string("g") }
        }
        return g ?? now
    }

    private static func move(_ a: String, _ g: String, _ d: String) -> JSON { ["a": .str(a), "g": .str(g), "d": .str(d)] }

    static func members(_ s: Store, _ gid: String) -> [JSON] {
        guard let g = get(s, gid) else { return [] }
        return byName(s.all(Store.athletes).filter { has(g["members"], $0.string("id")) })
    }

    /// Athletes of the team in no group (empty when there are no groups).
    static func unassigned(_ s: Store) -> [JSON] {
        if !any(s) { return [] }
        return byName(s.all(Store.athletes).filter { of(s, $0.string("id")).isEmpty })
    }

    static func byName(_ a: [JSON]) -> [JSON] {
        a.sorted { $0.string("name").localizedCompare($1.string("name")) == .orderedAscending }
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

    /// Keeps only groups that still exist; none left or every group = the whole team (no field).
    static func tidy(_ s: Store, _ session: inout JSON) {
        if !session["groups"].isArray { return }
        let gs = ofSession(s, session)
        if gs.isEmpty || gs.count == all(s).count {
            session.remove("groups")
            return
        }
        session["groups"] = .arr(gs.map { .str($0) })
    }

    /// The coach's list for one group: sessions for that group or for the whole team. Empty gid = everything.
    static func forGroup(_ s: Store, _ session: JSON, _ gid: String) -> Bool {
        if gid.isEmpty { return true }
        let gs = ofSession(s, session)
        return gs.isEmpty || gs.contains(gid)
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

    /// Who the session is for (Zapisnik rows, "x/y upisalo", Dolazak), sorted by name.
    static func audience(_ s: Store, _ session: JSON) -> [JSON] {
        let everyone = byName(s.all(Store.athletes))
        if !any(s) { return everyone }
        return everyone.filter { sees(s, session, $0.string("id")) }
    }

    /// Whose results go on the leaderboards: the coach's chosen group, the athlete's own group, or the whole team.
    static func boardTeam(_ s: Store, _ me: String) -> [JSON] {
        let everyone = s.all(Store.athletes)
        if !any(s) { return everyone }
        let gid = Prefs.isCoach ? selected(s) : of(s, me)
        return gid.isEmpty ? everyone : members(s, gid)
    }

    /// "Obje grupe", "Sve grupe", "Sprinteri + Skakači", or "" when the session is for one group or there is one group.
    static func tag(_ s: Store, _ session: JSON) -> String {
        let gs = all(s)
        if gs.count < 2 { return "" }
        let mine = ofSession(s, session)
        if mine.isEmpty || mine.count == gs.count { return gs.count == 2 ? "Obje grupe" : "Sve grupe" }
        if mine.count == 1 { return "" }
        return mine.map { name(s, $0) }.joined(separator: " + ")
    }

    // MARK: the coach's chosen group

    static func selected(_ s: Store) -> String {
        let gs = all(s)
        if gs.isEmpty { return "" }
        let id = Prefs.group
        return gs.contains { $0.string("id") == id } ? id : gs[0].string("id")
    }

    static func select(_ gid: String) { Prefs.group = gid }

    // MARK: writes (coach)

    private static func save(_ s: Store, _ groups: [JSON], _ moves: [JSON]) {
        s.put(Store.config, ["id": .str(doc), "groups": .arr(groups), "moves": .arr(moves)])
    }

    /// New group. The first group gets every athlete of the team, so nobody is left out. Returns its id.
    @discardableResult
    static func create(_ s: Store, _ name: String) -> String {
        var gs = all(s)
        var mv = moves(s)
        let id = "g" + Fmt.id()
        var members: [JSON] = []
        if gs.isEmpty {
            for at in s.all(Store.athletes) {
                members.append(.str(at.string("id")))
                mv.append(move(at.string("id"), id, "")) // founding members: in the group from the start
            }
        }
        gs.append(["id": .str(id), "name": .str(name.trimmingCharacters(in: .whitespaces)), "members": .arr(members)])
        save(s, gs, mv)
        return id
    }

    static func rename(_ s: Store, _ gid: String, _ name: String) {
        let gs = all(s).map { g -> JSON in
            var g = g
            if g.string("id") == gid { g["name"] = .str(name.trimmingCharacters(in: .whitespaces)) }
            return g
        }
        save(s, gs, moves(s))
    }

    /// Removes the group; its athletes are left in no group and its sessions count as the whole team's.
    static func delete(_ s: Store, _ gid: String) {
        var keep: [JSON] = []
        var mv = moves(s)
        for g in all(s) {
            if g.string("id") != gid { keep.append(g); continue }
            for m in g["members"].list { mv.append(move(m.asString, "", Fmt.today())) }
        }
        save(s, keep, mv)
    }

    /// Puts the athlete into the group (and out of any other) from today on; empty gid = no group.
    static func assign(_ s: Store, _ athleteId: String, _ gid: String) {
        let was = of(s, athleteId)
        if gid == was { return }
        var mv = moves(s)
        // someone in a group from before the log existed: keep that as their past
        if !was.isEmpty && groupOn(mv, athleteId, "9999", "").isEmpty { mv.append(move(athleteId, was, "")) }
        let gs = all(s).map { g -> JSON in
            var g = g
            var n = g["members"].list.filter { $0.asString != athleteId }
            if g.string("id") == gid { n.append(.str(athleteId)) }
            g["members"] = .arr(n)
            return g
        }
        mv.append(move(athleteId, gid, Fmt.today()))
        save(s, gs, mv)
    }

    private static func has(_ a: JSON, _ v: String) -> Bool {
        !v.isEmpty && a.list.contains { $0.asString == v }
    }
}

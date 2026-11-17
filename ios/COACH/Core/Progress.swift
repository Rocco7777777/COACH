import Foundation

/// Progress per exercise (Progress.java): one point per training day.
///   gym: estimated 1RM of the best set by the RPE chart (see e1rm), no RPE = @10
///   run reps: best rep of the day; gps: average pace. Lower is better for both.
///   comp: results from competitions in a discipline the coach set up (Comp), one point per result.
enum Progress {
    static let gym = 0, run = 1, gps = 2, comp = 3
    static let starts = ["blok", "let", "el"]
    static let startNames = ["Iz bloka", "Leteći", "Električno"]

    static func historyId(_ athleteId: String) -> String { "hist_" + athleteId }

    struct Pt {
        var day: Int = 0
        var v: Double = 0, top: Double = 0
        var set = "", topSet = ""
        var manual = false, month = false
        var tr: Double = 0
        var pr = false
    }

    final class Series {
        var key = "", name = "", metric = "", unit = ""
        var kind = 0
        var lower = false
        var band = 0.0, prMargin = 0.0
        var pts: [Pt] = []
        var best3 = 0.0, best5 = 0.0
        var best3Day = 0, best5Day = 0
        /// comp only: the discipline's unit (Comp.time, Comp.length, Comp.points).
        var cunit = ""

        func fmt(_ v: Double) -> String {
            if kind == Progress.gym { return Progress.kg(v) }
            if kind == Progress.gps { return Fmt.clock(v) }
            if kind == Progress.comp { return Comp.fmt(cunit, v) }
            return Progress.sec(v)
        }

        var group: String {
            switch kind {
            case Progress.gym: return "Teretana"
            case Progress.run: return "Sprint i dionice"
            case Progress.comp: return "Natjecanja"
            default: return "Trčanje km"
            }
        }

        /// The best result ever, nil without results.
        var best: Pt? {
            var b: Pt? = nil
            for p in pts where p.v > 0 { if b == nil || better(p.v, b!.v) { b = p } }
            return b
        }

        func better(_ a: Double, _ b: Double) -> Bool { lower ? a < b : a > b }
    }

    // MARK: formatting

    static func kg(_ v: Double) -> String { Fmt.n((v * 2).rounded() / 2) }

    static func sec(_ v: Double) -> String {
        if v >= 60 { return Fmt.time((v * 100).rounded() / 100).replacingOccurrences(of: ".", with: ",") }
        return String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func dist(_ m: Double) -> String {
        if m >= 1000 && m.truncatingRemainder(dividingBy: 100) == 0 { return Fmt.n(m / 1000) + " km" }
        return Fmt.n(m) + " m"
    }

    static func startName(_ s: String) -> String {
        if let i = starts.firstIndex(of: s) { return startNames[i].lowercased() }
        return ""
    }

    static var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Days since 1970-01-01 for "yyyy-MM-dd", nil when it isn't a date.
    static func epochDay(_ iso: String) -> Int? {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return Int((d.timeIntervalSince1970 / 86400).rounded(.down))
    }

    static func todayDay() -> Int { epochDay(Fmt.today()) ?? 0 }

    static func dateComponents(_ day: Int) -> DateComponents {
        utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(day) * 86400))
    }

    static func date(_ day: Int) -> String {
        let c = dateComponents(day)
        return "\(c.day ?? 0).\(c.month ?? 0).\(c.year ?? 0)."
    }

    /// The RPE chart lifters use (RTS / Tuchscherer): % of 1RM for n = 1…12, where n = reps done + reps left in reserve.
    static let rpeChart: [Double] = [100, 95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0]

    /// Share of the 1RM a set stands for, 1.0 … 0.68. Reps in reserve = 10 − RPE; no RPE (or nonsense) counts as @10.
    /// 1 rep @10 is 1.0, so the estimate is exactly the weight on the bar. Half RPEs fall between two steps of the
    /// chart; anything past 12 counts as 12, so long easy sets don't blow the estimate up.
    static func share(_ reps: Double, _ rpe0: Double) -> Double {
        let rpe = (rpe0 <= 0 || rpe0 > 10) ? 10 : rpe0
        let n = min(max(reps + (10 - rpe), 1), 12)
        let i = Int(n.rounded(.down))
        let a = rpeChart[i - 1]
        let b = i < 12 ? rpeChart[i] : a
        return (a + (b - a) * (n - Double(i))) / 100
    }

    /// Estimated 1RM of one set: kg / share. 100 kg × 1 @10 = 100; × 5 @8 = 123,3; × 3 @9 = 112,1.
    static func e1rm(_ kg: Double, _ reps: Double, _ rpe0: Double) -> Double {
        kg / share(reps, rpe0)
    }

    // MARK: keys

    static func gymKey(_ name: String) -> String {
        "gym:" + name.trimmingCharacters(in: .whitespaces).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func runKey(_ meters: Double, _ start: String) -> String { "run:\(Int64(meters.rounded())):\(start)" }

    static func gpsKey(_ km: Double) -> String { "gps:" + Fmt.n((km * 2).rounded() / 2) }

    static func keyFor(_ item: JSON) -> String? {
        switch item.string("type") {
        case "gym":
            return item.string("name").trimmingCharacters(in: .whitespaces).isEmpty || Model.hold(item) ? nil : gymKey(item.string("name"))
        case "run":
            let m = Fmt.num(item.string("distance"))
            return m > 0 ? runKey(m, item.string("start")) : nil
        case "gps":
            return gpsKey(Fmt.num(item.string("km")))
        default: return nil
        }
    }

    private static func make(_ key: String, _ rawName: String) -> Series {
        let s = Series()
        s.key = key
        let p = key.components(separatedBy: ":")
        if key.hasPrefix("gym:") {
            s.kind = gym
            s.name = rawName.trimmingCharacters(in: .whitespaces)
            s.metric = "proc. 1RM"
            s.unit = "kg"
        } else if key.hasPrefix("run:") {
            s.kind = run
            let m = Fmt.num(p[1])
            let st = p.count > 2 ? p[2] : ""
            s.name = dist(m) + (st.isEmpty ? "" : " · " + startName(st))
            s.metric = "najbolja dionica"
            s.unit = "s"
            s.lower = true
            let hand = st != "el"
            s.band = hand && m <= 200 ? 0.1 : 0
            s.prMargin = hand && m <= 200 ? 0.05 : 0
        } else {
            s.kind = gps
            s.name = "Trčanje " + (p.count > 1 ? p[1] : "") + " km"
            s.metric = "prosj. tempo"
            s.unit = "/km"
            s.lower = true
        }
        return s
    }

    // MARK: building

    @MainActor
    static func build(_ store: Store, _ athleteId: String) -> [Series] {
        build(store, athleteId, store.where(Store.results, "athleteId", athleteId))
    }

    @MainActor
    static func build(_ store: Store, _ athleteId: String, _ results: [JSON]) -> [Series] {
        var all: [String: Series] = [:]
        var latestName: [String: String] = [:]
        var latestDate: [String: String] = [:]
        var recs: [JSON] = []
        var compDoc: JSON? = nil
        for r in results {
            if r.string("id") == historyId(athleteId) {
                recs.append(contentsOf: r["records"].list.filter { $0.isObject })
                continue
            }
            if r.string("id") == Comp.resultsId(athleteId) {
                compDoc = r
                continue
            }
            guard let ses = store.doc(Store.sessions, r.string("sessionId")), ses["items"].isArray else { continue }
            let iso = ses.string("date", r.string("date"))
            guard let day = epochDay(iso) else { continue }
            let who = r.string("athleteId", athleteId)
            for raw in ses["items"].list where raw.isObject {
                let it = Model.forAthlete(raw, who.isEmpty ? athleteId : who)
                guard let key = keyFor(it) else { continue }
                if all[key] == nil { all[key] = make(key, it.string("name")) }
                let series = all[key]!
                guard let p = point(it, Model.entries(r, it.string("id")), series, day) else { continue }
                let nm = it.string("name").trimmingCharacters(in: .whitespaces)
                if !nm.isEmpty && iso >= (latestDate[key] ?? "") {
                    latestDate[key] = iso
                    latestName[key] = nm
                }
                add(series, p)
            }
        }
        for rec in recs {
            guard let key = recordKey(rec), let p = recordPoint(rec) else { continue }
            if all[key] == nil { all[key] = make(key, rec.string("name")) }
            let nm = rec.string("name").trimmingCharacters(in: .whitespaces)
            if latestName[key] == nil && !nm.isEmpty { latestName[key] = nm }
            let s = all[key]!
            if s.kind == gym { bestN(s, Fmt.num(rec.string("kg")), Int(Fmt.num(rec.string("reps"))), p.day) }
            add(s, p)
        }
        for (k, n) in latestName { if let s = all[k], s.kind == gym { s.name = n } }
        var list = Array(all.values)
        for s in list { s.pts.sort { $0.day < $1.day } }
        list.append(contentsOf: Comp.series(store, doc: compDoc))
        list.sort(by: order)
        return list.filter { !$0.pts.isEmpty }
    }

    /// Competitions first, then gym, reps, runs in km.
    private static func rank(_ kind: Int) -> Int { kind == comp ? -1 : kind }

    static func order(_ a: Series, _ b: Series) -> Bool {
        if a.kind != b.kind { return rank(a.kind) < rank(b.kind) }
        if a.kind == run {
            let pa = a.key.components(separatedBy: ":"), pb = b.key.components(separatedBy: ":")
            let da = Fmt.num(pa[1]), db = Fmt.num(pb[1])
            if da != db { return da < db }
            return (pa.count > 2 ? pa[2] : "") < (pb.count > 2 ? pb[2] : "")
        }
        if a.kind == gps { return Fmt.num(String(a.key.dropFirst(4))) < Fmt.num(String(b.key.dropFirst(4))) }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private static func add(_ s: Series, _ p: Pt) {
        if let i = s.pts.firstIndex(where: { $0.day == p.day }) {
            if s.better(p.v, s.pts[i].v) { s.pts[i].v = p.v; s.pts[i].set = p.set; s.pts[i].manual = p.manual }
            if p.top > s.pts[i].top { s.pts[i].top = p.top; s.pts[i].topSet = p.topSet }
            return
        }
        s.pts.append(p)
    }

    private static func bestN(_ s: Series, _ kg: Double, _ reps: Int, _ day: Int) {
        if kg <= 0 { return }
        if reps >= 3 && kg > s.best3 { s.best3 = kg; s.best3Day = day }
        if reps >= 5 && kg > s.best5 { s.best5 = kg; s.best5Day = day }
    }

    private static func point(_ it: JSON, _ en: [JSON], _ series: Series, _ day: Int) -> Pt? {
        var p = Pt()
        p.day = day
        switch it.string("type") {
        case "gym":
            let itemRpe = Fmt.num(it.string("rpe"))
            var best = 0.0
            for e in en where e.isObject && e.bool("done") {
                let kgv = Fmt.num(e.string("kg")), reps = Fmt.num(e.string("reps"))
                if kgv <= 0 || reps <= 0 { continue }
                let rpe = e.has("rpe") ? Fmt.num(e.string("rpe")) : itemRpe
                let label = kg(kgv) + " kg × " + Fmt.n(reps) + (rpe > 0 ? " @" + Fmt.n(rpe) : "")
                let v = e1rm(kgv, reps, rpe)
                if v > best { best = v; p.set = label }
                if kgv > p.top { p.top = kgv; p.topSet = label }
                bestN(series, kgv, Int(reps), day)
            }
            if best <= 0 { return nil }
            p.v = best
            return p
        case "run":
            var best = -1.0
            var n = 0
            for e in en {
                let t = e.isObject ? Fmt.parseTime(e.string("t")) : -1
                if t <= 0 { continue }
                n += 1
                if best < 0 || t < best { best = t }
            }
            if best <= 0 { return nil }
            p.v = best
            p.set = "\(n) × " + dist(Fmt.num(it.string("distance"))) + ", najbolja " + sec(best) + " s"
            return p
        case "gps":
            guard let r = en.first, r.isObject, r.double("km") >= 0.5 else { return nil }
            let km = r.double("km"), s = r.double("s")
            if s <= 0 { return nil }
            p.v = s / km
            p.set = Fmt.km(km) + " km u " + Fmt.clock(s)
            return p
        default: return nil
        }
    }

    // MARK: old records typed in by hand

    @MainActor
    static func records(_ store: Store, _ athleteId: String) -> [JSON] {
        store.doc(Store.results, historyId(athleteId))?["records"].list.filter { $0.isObject } ?? []
    }

    static func recordKey(_ r: JSON) -> String? {
        switch r.string("kind") {
        case "gym": return r.string("name").trimmingCharacters(in: .whitespaces).isEmpty ? nil : gymKey(r.string("name"))
        case "run": return Fmt.num(r.string("dist")) > 0 ? runKey(Fmt.num(r.string("dist")), r.string("start")) : nil
        case "gps": return Fmt.num(r.string("km")) > 0 ? gpsKey(Fmt.num(r.string("km"))) : nil
        default: return nil
        }
    }

    static func recordPoint(_ r: JSON) -> Pt? {
        var p = Pt()
        guard let d = epochDay(r.string("date")) else { return nil }
        p.day = d
        p.manual = !r.bool("plain")
        switch r.string("kind") {
        case "gym":
            let kgv = Fmt.num(r.string("kg")), reps = max(1, Fmt.num(r.string("reps"))), rpe = Fmt.num(r.string("rpe"))
            if kgv <= 0 { return nil }
            p.v = e1rm(kgv, reps, rpe)
            p.top = kgv
            p.set = kg(kgv) + " kg × " + Fmt.n(reps) + (rpe > 0 ? " @" + Fmt.n(rpe) : "")
            p.topSet = p.set
        case "run":
            let t = Fmt.parseTime(r.string("t"))
            if t <= 0 { return nil }
            p.v = t
            p.set = dist(Fmt.num(r.string("dist"))) + " u " + sec(t) + " s"
        case "gps":
            let pace = Fmt.parseTime(r.string("pace"))
            if pace <= 0 { return nil }
            p.v = pace
            p.set = Fmt.n(Fmt.num(r.string("km"))) + " km, tempo " + Fmt.clock(pace) + "/km"
        default: return nil
        }
        return p
    }

    @MainActor
    static func saveRecord(_ store: Store, _ athleteId: String, _ rec0: JSON) {
        var h = store.doc(Store.results, historyId(athleteId)) ?? ["id": .str(historyId(athleteId)), "athleteId": .str(athleteId), "history": true]
        var rec = rec0
        if !rec.has("id") { rec["id"] = .str(Fmt.id()) }
        var a = h["records"].isArray ? h["records"] : JSON.array()
        a.append(rec)
        h["records"] = a
        store.put(Store.results, h)
    }

    @MainActor
    static func deleteRecord(_ store: Store, _ athleteId: String, _ recId: String) {
        guard var h = store.doc(Store.results, historyId(athleteId)) else { return }
        h["records"] = .arr(h["records"].list.filter { $0.isObject && $0.string("id") != recId })
        store.put(Store.results, h)
    }

    // MARK: views of a series

    static let r3m = "3m", r1g = "1g", rAll = "all"

    static func view(_ s: Series, _ range: String, top: Bool) -> [Pt] {
        let useTop = top && s.kind == gym
        let today = todayDay()
        var pts: [Pt] = []
        for p in s.pts {
            var q = p
            q.month = false
            q.pr = false
            if useTop { q.v = p.top; q.set = p.topSet }
            if q.v <= 0 { continue }
            pts.append(q)
        }
        if range == r3m || range == r1g {
            trend(&pts)
            let from = today - (range == r3m ? 92 : 365)
            pts = pts.filter { $0.day > from }
        } else if s.kind == comp {
            // a handful of competitions a year: every result stays
            trend(&pts)
        } else {
            var by: [Int: Pt] = [:]
            for p in pts {
                let c = dateComponents(p.day)
                let m = (c.year ?? 0) * 12 + (c.month ?? 0)
                if let b = by[m], !s.better(p.v, b.v) { continue }
                by[m] = p
            }
            pts = by.keys.sorted().map { var p = by[$0]!; p.month = true; return p }
            trend(&pts)
        }
        // competitions: the line goes through the results themselves, a median of five would hide a season
        if s.kind == comp { for i in pts.indices { pts[i].tr = pts[i].v } }
        var prDays = Set<Int>()
        var best = Double.nan
        for p in s.pts {
            let v = useTop ? p.top : p.v
            if v <= 0 { continue }
            let m = useTop ? 0 : s.prMargin
            if best.isNaN || (s.lower ? v < best - m - 1e-9 : v > best + m + 1e-9) {
                if !best.isNaN { prDays.insert(p.day) }
                best = v
            }
        }
        for i in pts.indices { pts[i].pr = prDays.contains(pts[i].day) }
        return pts
    }

    static func trend(_ pts: inout [Pt]) {
        for i in pts.indices {
            var w: [Double] = []
            for k in max(0, i - 4)...i { w.append(pts[k].v) }
            w.sort()
            pts[i].tr = w[w.count / 2]
        }
    }

    /// Trend now, its change against a year ago (or the first point), whether a full year, and that day.
    static func delta(_ s: Series) -> (now: Double, change: Double, full: Bool, day: Int)? {
        var pts = s.pts.filter { $0.v > 0 }
        if pts.isEmpty { return nil }
        trend(&pts)
        let now = pts[pts.count - 1].tr
        let yearAgo = todayDay() - 365
        var ago: Pt? = nil
        for p in pts where p.day <= yearAgo { ago = p }
        let full = ago != nil
        let a = ago ?? pts[0]
        return (now, now - a.tr, full, a.day)
    }

    static func deltaText(_ s: Series, _ d: Double) -> String {
        let sign = d > 0 ? "+" : d < 0 ? "−" : "±"
        let a = abs(d)
        if s.kind == gym { return sign + kg(a) + " kg" }
        if s.kind == run { return sign + sec(a) + " s" }
        if s.kind == comp { return sign + Comp.text(s.cunit, a) }
        return sign + Fmt.clock(a)
    }

    static func good(_ s: Series, _ d: Double) -> Bool { s.lower ? d < 0 : d > 0 }
}

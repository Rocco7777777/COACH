import Foundation

/// "Isprobaj demo": no login, a sample week of training and a month of history for five athletes (Demo.java).
/// Nothing goes to the server. This is also how Apple's reviewers see the app without an account.
@MainActor
enum Demo {
    static let me = "demo_rocco"
    static let team: [(String, String)] = [
        (me, "Rocco Martinović"), ("demo_ivan", "Ivan Kovač"), ("demo_luka", "Luka Babić"),
        ("demo_marko", "Marko Jurić"), ("demo_petra", "Petra Novak"),
    ]

    static func start() {
        let s = Store.shared
        s.wipe()
        Prefs.demoMode = true
        setUp()
        s.sessionChanged()
    }

    static func exit() {
        Prefs.demoMode = false
        Store.shared.wipe()
    }

    static func setUp() {
        if Prefs.athleteId.isEmpty {
            Prefs.setSession(id: me, email: "demo@coach.app", access: "", refresh: "", expiry: 0)
            Prefs.setProfile(name: team[0].1, role: "athlete")
        }
        let s = Store.shared
        if s.all(Store.sessions).isEmpty {
            seed(s)
        } else if s.doc(Store.config, Comp.doc) == nil {
            // a demo started before competitions existed: add them to what's there
            competitions(s)
            s.seedDone()
        }
    }

    static let code = "TRK426"
    static let teamName = "AK Demo"

    /// The demo has both sides: the same made-up team seen by its coach or by an athlete.
    static func switchRole() {
        Prefs.setProfile(name: team[0].1, role: Prefs.isCoach ? "athlete" : "coach")
        Store.shared.sessionChanged()
        Toast.shared.show(Prefs.isCoach ? "Sad gledaš kao trener" : "Sad gledaš kao sportaš")
    }

    static func reset() {
        let s = Store.shared
        let role = Prefs.role
        s.wipe()
        Prefs.demoMode = true
        Prefs.setSession(id: me, email: "demo@coach.app", access: "", refresh: "", expiry: 0)
        Prefs.setProfile(name: team[0].1, role: role)
        seed(s)
        s.sessionChanged()
    }

    // MARK: seeded random (same idea as java.util.Random(seed): repeatable sample data)

    struct Rnd {
        var state: UInt64
        init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func float() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func bool() -> Bool { next() & 1 == 1 }
        mutating func gauss() -> Double {
            let u = max(float(), 1e-12), v = float()
            return sqrt(-2 * log(u)) * cos(2 * .pi * v)
        }
    }

    private static func kgText(_ kg: Double) -> String { Fmt.n(kg).replacingOccurrences(of: ",", with: ".") }

    private static func run(_ id: String, _ dist: Int, _ reps: Int, _ target: String, _ rest: String, _ note: String) -> JSON {
        ["id": .str(id), "type": "run", "distance": .str("\(dist)"), "reps": .str("\(reps)"), "target": .str(target), "rest": .str(rest), "note": .str(note)]
    }

    private static func gym(_ id: String, _ name: String, _ sets: Int, _ reps: String, _ kg: Double, _ rpe: String, _ note: String) -> JSON {
        ["id": .str(id), "type": "gym", "name": .str(name), "sets": .str("\(sets)"), "reps": .str(reps), "kg": .str(kg > 0 ? kgText(kg) : ""), "rpe": .str(rpe), "note": .str(note)]
    }

    private static func gpsRun(_ id: String, _ km: Double, _ pace: String, _ note: String) -> JSON {
        ["id": .str(id), "type": "gps", "km": .str(kgText(km)), "pace": .str(pace), "note": .str(note)]
    }

    private static func note(_ id: String, _ name: String, _ text: String) -> JSON {
        ["id": .str(id), "type": "note", "name": .str(name), "note": .str(text)]
    }

    private static func session(_ d: Date, _ title: String, _ notes: String, _ items: [JSON]) -> JSON {
        let iso = Fmt.iso(d)
        return ["id": .str("s_" + iso), "date": .str(iso), "title": .str(title), "notes": .str(notes), "items": .arr(items)]
    }

    private static func week(_ mon: Date, _ w: Int) -> [JSON] {
        let k = -2.5 * Double(w)
        var r = run("r", 400, 5, w == 0 ? "1:30" : "1:3\(w)", "1:30", "Ravnomjerno, zadnja može brže")
        r["per"] = [me: ["target": .str(w == 0 ? "1:27" : "1:2\(min(9, 7 + w))")], "demo_petra": ["reps": "4", "target": "1:38"]]
        var squat = gym("g1", "Čučanj", 4, "5", 100 + k, "8", "Duboko, kontrolirano spuštanje")
        squat["per"] = [me: ["kg": .str(kgText(110 + k))], "demo_petra": ["kg": .str(kgText(60 + k)), "reps": "6", "rpe": "7"]]
        var hold = gym("g4", "Polučučanj uza zid", 3, "45", 0, "", "Izometrija, koljena 90°")
        hold["unit"] = "s"
        var s60 = run("r1", 60, 6, "7.6", "3:00", "Iz niskog starta")
        s60["start"] = "blok"
        var s150 = run("r2", 150, 3, "18.5", "5:00", "Leteći start")
        s150["start"] = "let"
        return [
            session(mon, "Dionice", "Zagrijavanje 15 min + ABC, 4 ubrzanja", [note("n", "Zagrijavanje", "15 min lagano, ABC vježbe, 4 × 80m ubrzanja"), r]),
            session(Fmt.addDays(mon, 1), "Teretana", "Snaga donji dio", [
                squat, gym("g2", "Rumunjsko mrtvo dizanje", 3, "8", 80 + k, "7", ""),
                gym("g3", "Iskoraci s bučicama", 3, "10", 24, "8", "Po nozi"), hold,
                note("n", "Core", "3 × 45 s plank + 3 × 12 dead bug"),
            ]),
            session(Fmt.addDays(mon, 2), "Sprint", "Puna pauza, kvaliteta ispred kvantitete", [s60, s150]),
            session(Fmt.addDays(mon, 3), "Tempo trčanje", "Ravnomjerno po tempu", [
                gpsRun("t", 8, "4:30", "Prva 2 km lagano ulaziš u tempo, zadnji km možeš brže"),
                note("n", "Mobilnost", "15 min istezanje kukova i listova"),
            ]),
            session(Fmt.addDays(mon, 4), "Teretana", "Snaga gornji dio + stražnji lanac", [
                gym("g1", "Mrtvo dizanje", 4, "4", 140 + k, "8", ""), gym("g2", "Bench press", 4, "6", 70 + k, "8", ""),
                gym("g3", "Zgibovi", 3, "8", 0, "9", "S vlastitom težinom"), gym("g4", "Hip thrust", 3, "10", 100 + k, "7", "Pauza 1 s gore"),
            ]),
            session(Fmt.addDays(mon, 5), "Dionice", "Mješovito: brzina + izdržljivost", [
                run("r1", 200, 8, "30", "1:00", ""), run("r2", 1000, 2, w == 0 ? "3:15" : "3:2\(min(w, 9))", "4:00", "Kontrolirano"),
            ]),
            session(Fmt.addDays(mon, 6), "Regeneracija", "Odmor od trčanja", [note("n", "Aktivni odmor", "20 min bicikl lagano + 20 min istezanje / valjak")]),
        ]
    }

    private static func seed(_ s: Store) {
        var rnd = Rnd(7)
        for t in team { s.seedPut(Store.athletes, ["id": .str(t.0), "name": .str(t.1)]) }
        s.seedPut(Store.config, Model.defaultQuestionnaire())
        let today = Fmt.today()
        let mon = Fmt.monday(Date())
        for w in stride(from: 3, through: -1, by: -1) {
            for ses in week(Fmt.addDays(mon, -7 * w), max(w, 0)) {
                s.seedPut(Store.sessions, ses)
                if ses.string("date") >= today { continue }
                for (ai, t) in team.enumerated() {
                    if rnd.float() < 0.12 { continue }
                    s.seedPut(Store.results, result(ses, t, ai, &rnd))
                }
            }
        }
        // today's training always has a run and reps, so logging one is a tap away
        if var now = s.doc(Store.sessions, "s_" + today) {
            var items = now["items"].list
            if !items.contains(where: { $0.string("type") == "gps" }) { items.append(gpsRun("gps", 5, "5:15", "Lagano i ravnomjerno")) }
            var reps = items.first(where: { $0.string("type") == "run" })
            if reps == nil {
                reps = run("u", 80, 4, "11", "1:00", "Ubrzanja, opušteno brzo")
                items.append(reps!)
            }
            now["items"] = .arr(items)
            s.seedPut(Store.sessions, now)
            for ai in 1...3 {
                let target = Fmt.parseTime(Model.forAthlete(reps!, team[ai].0).string("target"))
                var en: [JSON] = []
                for _ in 0..<2 {
                    en.append(["t": .str(Fmt.time(target * (1 + Double(ai - 2) * 0.02) * (0.98 + rnd.float() * 0.04)))])
                }
                s.seedPut(Store.results, ["id": .str(Model.resultId(now.string("id"), team[ai].0)), "sessionId": .str(now.string("id")),
                                          "athleteId": .str(team[ai].0), "athleteName": .str(team[ai].1), "date": .str(now.string("date")),
                                          "entries": [reps!.string("id"): .arr(en)], "comment": ""])
            }
        }
        for (ai, t) in team.enumerated() { history(s, t.0, ai, Fmt.addDays(mon, -22)) }
        let sore = ["Listovi", "Stražnja loža", "Prednja loža", "Kukovi", "Leđa"]
        var labels = JSON.object()
        for q in Model.defaultQuestionnaire()["questions"].list { labels[q.string("id")] = .str(q.string("text")) }
        for i in 1...28 {
            let d = Fmt.iso(Fmt.addDays(Date(), -i))
            for t in team {
                var w: JSON = ["q_sleep": .num(Double(2 + rnd.int(4))), "q_fatigue": .num(Double(2 + rnd.int(4))),
                               "q_mood": .num(Double(2 + rnd.int(4))), "q_stress": .num(Double(2 + rnd.int(4)))]
                let sor = rnd.float() < 0.3
                w["q_sore"] = .str(sor ? "da" : "ne")
                if sor { w["q_where"] = [.str(sore[rnd.int(sore.count)])] }
                s.seedPut(Store.daily, ["id": .str(Model.dailyId(t.0, d)), "athleteId": .str(t.0), "athleteName": .str(t.1), "date": .str(d),
                                        "sleep": .num(6 + Double(rnd.int(7)) * 0.5), "protein": .num(Double(1 + rnd.int(3))),
                                        "creatine": .num(rnd.float() < 0.8 ? 5 : 0),
                                        "vitamins": ["Vitamin D", .str(rnd.bool() ? "Magnezij" : "Omega-3")],
                                        "wellness": w, "wellnessLabels": labels, "wellnessDone": true])
            }
        }
        competitions(s)
        s.seedDone()
    }

    /// Four disciplines, who competes in what, and three seasons of made-up results; and a picked set of
    /// leaderboards, so the demo shows both of the coach's lists in use.
    private static func competitions(_ s: Store) {
        var rnd = Rnd(55)
        let list: [(String, String, String)] = [
            ("d100", "100 m", Comp.time), ("d200", "200 m", Comp.time), ("d400", "400 m", Comp.time), ("ddalj", "Skok u dalj", Comp.length),
        ]
        // athlete, discipline, what they are good for this season
        let who: [(Int, String, Double)] = [
            (0, "d100", 10.95), (0, "d200", 22.10), (1, "d100", 11.12), (1, "d200", 22.48), (2, "d200", 22.95),
            (2, "d400", 49.80), (3, "d400", 50.60), (3, "ddalj", 6.85), (4, "ddalj", 5.62), (4, "d100", 12.45),
        ]
        let meets: [(Int, Int, String)] = [
            (5, 10, "Miting Zagreb"), (5, 24, "Miting Rijeka"), (6, 7, "Kup Hrvatske"), (6, 21, "Miting Split"),
            (7, 12, "Prvenstvo Hrvatske"), (8, 2, "Miting Osijek"), (9, 6, "Finale lige"),
        ]
        let today = Fmt.today()
        let year = Comp.thisYear()
        var of = JSON.object()
        var results: [JSON] = []
        for (ai, did, best) in who {
            let aid = team[ai].0
            var mine = of[aid].list
            mine.append(.str(did))
            of[aid] = .arr(mine)
            let time = did != "ddalj"
            for y in (year - 2)...year {
                for (mi, meet) in meets.enumerated() {
                    let iso = String(format: "%04d-%02d-%02d", y, meet.0, meet.1)
                    if iso >= today || rnd.float() < 0.3 { continue }
                    // earlier seasons and the start of a season are a little worse; the form peaks in July
                    let age: Double = Double(year - y) * 0.018 + abs(Double(mi) - 4) * 0.004
                    let noise: Double = abs(rnd.gauss()) * 0.006
                    let slower: Double = best * (1 + age + noise)
                    let shorter: Double = best * (1 - age * 1.4 - noise * 1.6)
                    let v: Double = time ? slower : shorter
                    results.append(["id": .str("r\(results.count)"), "a": .str(aid), "d": .str(did), "date": .str(iso),
                                    "v": .num((v * 100).rounded() / 100), "meet": .str(meet.2)])
                }
            }
        }
        let ds: [JSON] = list.map { ["id": .str($0.0), "name": .str($0.1), "unit": .str($0.2)] }
        s.seedPut(Store.config, ["id": .str(Comp.doc), "list": .arr(ds), "of": of, "results": .arr(results)])
        // the coach left the small accessory lifts and the odd distances without a leaderboard
        let on: [String] = [
            Progress.gymKey("Čučanj"), Progress.gymKey("Mrtvo dizanje"), Progress.gymKey("Bench press"),
            Progress.runKey(60, "blok"), Progress.runKey(150, "let"), Progress.runKey(400, ""), Progress.gpsKey(8),
        ]
        s.seedPut(Store.config, ["id": .str(BoardPick.doc), "custom": true, "on": .arr(on.map { .str($0) })])
    }

    /// Three years of made-up history before the demo weeks, so the progress graphs have something to show.
    private static func history(_ s: Store, _ athleteId: String, _ ai: Int, _ end: Date) {
        var rnd = Rnd(UInt64(100 + ai))
        let skill = 1 + Double(ai - 2) * 0.02
        guard let endDay = Progress.epochDay(Fmt.iso(end)) else { return }
        let startDay = endDay - 1096
        let span = Double(endDay - startDay)
        var recs: [JSON] = []
        let names = ["Bench press", "Čučanj", "Mrtvo dizanje"]
        // what the demo weeks' sets stand for: bench 6 @8, squat 5 @8, deadlift 4 @8
        let now1rm = [Progress.e1rm(70 / skill, 6, 8), Progress.e1rm(100 / skill, 5, 8), Progress.e1rm(140 / skill, 4, 8)]
        let repsPick = [3, 4, 5, 5, 6]
        let rpePick = [7, 7.5, 8, 8, 8.5, 9]
        func iso(_ day: Int) -> String {
            let c = Progress.dateComponents(day)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        for g in 0..<names.count {
            var d = startDay + g
            while d < endDay {
                let f = Double(d - startDay) / span
                let m = Progress.dateComponents(d).month ?? 1
                let trueMax = now1rm[g] * (0.76 + 0.2 * (1 - pow(1 - f, 1.6))) - (m == 7 || m == 8 ? 4 : 0)
                let reps = repsPick[rnd.int(repsPick.count)]
                let rpe = rpePick[rnd.int(rpePick.count)]
                let kg = ((trueMax * (1 + rnd.gauss() * 0.02) * Progress.share(Double(reps), rpe)) / 2.5).rounded() * 2.5
                recs.append(["kind": "gym", "name": .str(names[g]), "date": .str(iso(d)), "kg": .str(kgText(kg)), "reps": .str("\(reps)"),
                             "rpe": .str(kgText(rpe)), "plain": true])
                d += 6 + rnd.int(4)
            }
        }
        let season = [0.02, 0, 0.03, 0.06, 0.05, 0.04, 0.07, 0.12, 0.1, 0.11, 0.08, 0.05]
        var d = startDay + 2
        while d < endDay {
            let f = Double(d - startDay) / span
            let tr = 7.41 * skill + 0.42 * pow(1 - f, 1.4) + season[(Progress.dateComponents(d).month ?? 1) - 1]
            var best = 9.0
            for _ in 0..<5 { best = min(best, tr + abs(rnd.gauss()) * 0.06 + rnd.gauss() * 0.04) }
            recs.append(["kind": "run", "dist": "60", "start": "blok", "date": .str(iso(d)), "t": .str(Fmt.time((best * 100).rounded() / 100)), "plain": true])
            d += 5 + rnd.int(5)
        }
        d = startDay + 40
        while d < endDay {
            let f = Double(d - startDay) / span
            let pace = ((272 + 30 * (1 - f) + rnd.gauss() * 5) * skill).rounded()
            recs.append(["kind": "gps", "km": "8", "date": .str(iso(d)), "pace": .str(Fmt.clock(pace)), "plain": true])
            d += 8 + rnd.int(6)
        }
        recs.append(["kind": "gym", "name": "Bench press", "date": .str(iso(startDay - 60)), "kg": .str(kgText((now1rm[0] * 0.8 / 2.5).rounded() * 2.5)),
                     "reps": "1", "id": .str("demo_old_\(ai)")])
        s.seedPut(Store.results, ["id": .str(Progress.historyId(athleteId)), "athleteId": .str(athleteId), "history": true, "records": .arr(recs)])
    }

    private static func result(_ ses: JSON, _ athlete: (String, String), _ ai: Int, _ rnd: inout Rnd) -> JSON {
        var entries = JSON.object()
        let skill = 1 + Double(ai - 2) * 0.02
        for raw in ses["items"].list {
            let it = Model.forAthlete(raw, athlete.0)
            var en: [JSON] = []
            switch it.string("type") {
            case "run":
                let target = Fmt.parseTime(it.string("target"))
                let reps = Int(Fmt.num(it.string("reps")))
                for r in 0..<max(0, reps) {
                    let t = target * skill * (0.97 + rnd.float() * 0.06) + Double(r) * target * 0.004
                    en.append(["t": .str(Fmt.time(t))])
                }
            case "gps":
                let km = Fmt.num(it.string("km")), pace = Fmt.parseTime(it.string("pace"))
                let full = Int(km.rounded(.down))
                var total = 0.0
                for k in 0..<max(0, full) {
                    let split = pace * skill * (0.975 + rnd.float() * 0.06) - (k == full - 1 ? 6 : 0)
                    total += (split * 10).rounded() / 10
                }
                let realKm = ((km + rnd.float() * 0.06) * 100).rounded() / 100
                total += (realKm - Double(full)) * pace * skill
                en.append(["km": .num(realKm), "s": .num(total.rounded()), "manual": true])
            case "gym":
                let sets = Int(Fmt.num(it.string("sets")))
                let kg = Fmt.num(it.string("kg"))
                let mine = kg <= 0 ? 0 : (kg / skill / 2.5).rounded() * 2.5
                let rpe = it.string("rpe")
                for r in 0..<max(0, sets) {
                    var e: JSON = ["kg": .str(mine > 0 ? Fmt.n(mine) : "0"), "reps": .str(it.string("reps")), "done": true]
                    if !rpe.isEmpty {
                        e["rpe"] = .str(r == sets - 1 && ai % 2 == 0 ? kgText(min(10, Fmt.num(rpe) + 0.5)) : rpe)
                    }
                    en.append(e)
                }
            default: continue
            }
            entries[it.string("id")] = .arr(en)
        }
        return ["id": .str(Model.resultId(ses.string("id"), athlete.0)), "sessionId": .str(ses.string("id")), "athleteId": .str(athlete.0),
                "athleteName": .str(athlete.1), "date": .str(ses.string("date")), "entries": entries,
                "comment": .str(rnd.float() < 0.25 ? "Dobar osjećaj danas" : "")]
    }
}

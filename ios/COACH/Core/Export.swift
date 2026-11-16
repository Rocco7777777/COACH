import Foundation

/// Season export (Export.java): one sheet per athlete with progression tables, plus a summary, sessions and attendance.
@MainActor
enum Export {
    /// Writes the workbook to a temporary file for the share sheet.
    static func file(_ s: Store) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("COACH_sezona_" + Fmt.today() + ".xlsx")
        try build(s).data().write(to: url, options: .atomic)
        return url
    }

    static func build(_ s: Store) -> Xlsx {
        let x = Xlsx()
        let athletes = Groups.byName(s.all(Store.athletes))
        // also athletes that were removed from the team but still have data
        var who: [(String, String)] = athletes.map { ($0.string("id"), $0.string("name")) }
        var seen = Set(who.map { $0.0 })
        for r in s.all(Store.results) + s.all(Store.daily) {
            let id = r.string("athleteId")
            if id.isEmpty || seen.contains(id) { continue }
            seen.insert(id)
            who.append((id, r.string("athleteName", "Sportaš")))
        }

        let sum = x.sheet("Sezona")
        sum.setWidths([24, 12, 12, 12, 14, 16, 16])
        sum.styled(Xlsx.title, ["COACH · sezona"])
        sum.row(["Izvezeno " + Fmt.nice(Fmt.today())])
        sum.blank()
        sum.styled(Xlsx.header, ["Sportaš", "Treninga", "km", "Tona", "Prosj. san (h)", "Upitnik (dana)", "Serija u teretani"])
        let rows = who.map { athleteSheet(x, s, $0.0, $0.1) }
        for r in rows { sum.row(r) }
        sessionsSheet(x, s)
        attendanceSheet(x, s, athletes)
        return x
    }

    private static func attendanceSheet(_ x: Xlsx, _ s: Store, _ athletes: [JSON]) {
        let sh = x.sheet("Dolasci")
        let groups = Groups.any(s)
        sh.setWidths([24, 16, 12, 12, 12, 12, 12, 12])
        sh.styled(Xlsx.header, ["Sportaš", groups ? "Grupa" : "", "30 dana", "30 dana %", "90 dana", "90 dana %", "Sve", "Sve %"])
        let today = Fmt.today()
        let t30 = Attendance.tallies(s, athletes, Attendance.from(30), today)
        let t90 = Attendance.tallies(s, athletes, Attendance.from(90), today)
        let tAll = Attendance.tallies(s, athletes, nil, today)
        for (i, at) in athletes.enumerated() {
            let m = t30[i], q = t90[i], a = tAll[i]
            func pct(_ t: Attendance.Tally) -> Any { t.pct < 0 ? "" : t.pct }
            sh.row([at.string("name"), groups ? Groups.name(s, Groups.of(s, at.string("id"))) : "",
                    "\(m.yes)/\(m.total)", pct(m), "\(q.yes)/\(q.total)", pct(q), "\(a.yes)/\(a.total)", pct(a)])
        }
    }

    /// (result, session, the athlete's own version of each item) for every result with a known session, by date.
    private static func rows(_ s: Store, _ athleteId: String) -> [(r: JSON, ses: JSON, items: [JSON])] {
        s.where(Store.results, "athleteId", athleteId).sorted { $0.string("date") < $1.string("date") }.compactMap { r in
            guard let ses = s.doc(Store.sessions, r.string("sessionId")), ses["items"].isArray else { return nil }
            return (r, ses, ses["items"].list.filter { $0.isObject }.map { Model.forAthlete($0, athleteId) })
        }
    }

    private static func athleteSheet(_ x: Xlsx, _ s: Store, _ id: String, _ name: String) -> [Any?] {
        let sh = x.sheet(name)
        sh.setWidths([12, 16, 22, 18, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11])
        let season = Model.season(s, id)
        sh.styled(Xlsx.title, [name])
        sh.row([Xlsx.c("Ukupno km", Xlsx.bold), Xlsx.c(round2(season.km), Xlsx.dec), "", Xlsx.c("Ukupno tona", Xlsx.bold),
                Xlsx.c(round2(season.kg / 1000), Xlsx.dec), "", Xlsx.c("Treninga", Xlsx.bold), Int(season.n)])
        sh.blank()
        let rs = rows(s, id)

        // running reps
        sh.styled(Xlsx.section, ["TRČANJE: DIONICE"])
        var maxReps = 1
        for x in rs { for it in x.items where it.string("type") == "run" { maxReps = max(maxReps, Model.entries(x.r, it.string("id")).count) } }
        var head: [Any?] = ["Datum", "Trening", "Dionica", "Cilj"]
        for i in 1...maxReps { head.append("#\(i)") }
        head += ["Prosjek", "Najbolje", "km"]
        sh.styled(Xlsx.header, head)
        var runProg: [String: [(String, Double, Double, Int)]] = [:]
        for x in rs {
            for it in x.items where it.string("type") == "run" {
                let en = Model.entries(x.r, it.string("id"))
                var row: [Any?] = [x.r.string("date"), x.ses.string("title"), Model.title(it), Xlsx.timeCell(Fmt.parseTime(it.string("target")))]
                var sum = 0.0, best = 0.0
                var n = 0
                for k in 0..<maxReps {
                    let t = k < en.count && en[k].isObject ? Fmt.parseTime(en[k].string("t")) : -1
                    row.append(Xlsx.timeCell(t))
                    if t > 0 {
                        sum += t
                        n += 1
                        if best == 0 || t < best { best = t }
                    }
                }
                if n == 0 { continue }
                row += [Xlsx.timeCell(sum / Double(n)), Xlsx.timeCell(best), round2(Double(n) * Fmt.num(it.string("distance")) / 1000)]
                sh.row(row)
                runProg[Model.distance(it.string("distance")), default: []].append((x.r.string("date"), sum / Double(n), best, n))
            }
        }
        sh.blank()

        // runs in km
        var maxKm = 0
        var gpsRows: [[Any?]] = []
        var gpsSplits: [[Double]] = []
        for x in rs {
            for it in x.items where it.string("type") == "gps" {
                guard let run = Model.run(x.r, it.string("id")) else { continue }
                let sp = run["splits"].list.map { $0.doubleValue() }
                maxKm = max(maxKm, sp.count)
                let km = run.double("km"), sec = run.double("s")
                gpsRows.append([x.r.string("date"), x.ses.string("title"),
                                Model.title(it) + (it.string("pace").isEmpty ? "" : " @ " + it.string("pace") + "/km"),
                                round2(km), Fmt.clock(sec), km > 0.05 ? Xlsx.timeCell(sec / km) : ""])
                gpsSplits.append(sp)
            }
        }
        if !gpsRows.isEmpty {
            sh.styled(Xlsx.section, ["TRČANJE (KM)"])
            var gh: [Any?] = ["Datum", "Trening", "Cilj", "km", "Vrijeme", "Prosj. tempo /km"]
            if maxKm > 0 { for k in 1...maxKm { gh.append("\(k). km") } }
            sh.styled(Xlsx.header, gh)
            for (i, g) in gpsRows.enumerated() {
                var row = g
                for k in 0..<maxKm { row.append(k < gpsSplits[i].count ? Xlsx.timeCell(gpsSplits[i][k]) : "") }
                sh.row(row)
            }
            sh.blank()
        }

        // gym
        sh.styled(Xlsx.section, ["TERETANA"])
        var maxSets = 1
        for x in rs { for it in x.items where it.string("type") == "gym" { maxSets = max(maxSets, Model.entries(x.r, it.string("id")).count) } }
        head = ["Datum", "Trening", "Vježba", "Plan"]
        for i in 1...maxSets { head.append("Serija \(i)") }
        head += ["Max kg", "Ponav.", "Tonaža kg"]
        sh.styled(Xlsx.header, head)
        var gymProg: [String: [(String, Double, Int, Double)]] = [:]
        var setsTotal = 0
        for x in rs {
            for it in x.items where it.string("type") == "gym" {
                let en = Model.entries(x.r, it.string("id"))
                var row: [Any?] = [x.r.string("date"), x.ses.string("title"), it.string("name"), Model.plan(it).replacingOccurrences(of: "  ·  ", with: ", ")]
                var mx = 0.0, ton = 0.0
                var reps = 0, done = 0
                for k in 0..<maxSets {
                    if k < en.count, en[k].bool("done") {
                        let e = en[k]
                        let kg = Fmt.num(e.string("kg"))
                        let rp = Int(Fmt.num(e.string("reps")))
                        row.append(Model.setText(it, e, rpe: true).replacingOccurrences(of: "  ·  ", with: ", "))
                        mx = max(mx, kg)
                        if !Model.hold(it) {
                            ton += kg * Double(rp)
                            reps += rp
                        }
                        done += 1
                    } else {
                        row.append("")
                    }
                }
                if done == 0 { continue }
                setsTotal += done
                row += [mx, reps, round2(ton)]
                sh.row(row)
                var key = it.string("name").trimmingCharacters(in: .whitespaces)
                if key.isEmpty { key = "(bez naziva)" }
                // one table per exercise, whatever the capitals
                let existing = gymProg.keys.first { $0.caseInsensitiveCompare(key) == .orderedSame } ?? key
                gymProg[existing, default: []].append((x.r.string("date"), mx, reps, ton))
            }
        }
        sh.blank()

        sh.styled(Xlsx.section, ["PROGRESIJA PO VJEŽBI"])
        sh.styled(Xlsx.header, ["Datum", "Vježba", "Max kg", "Promjena kg", "Ponav.", "Tonaža kg"])
        for k in gymProg.keys.sorted(by: { $0.caseInsensitiveCompare($1) == .orderedAscending }) {
            var prev = -1.0
            for p in gymProg[k]! {
                sh.row([p.0, k, p.1, prev < 0 ? "" : round2(p.1 - prev), p.2, round2(p.3)])
                prev = p.1
            }
        }
        sh.blank()
        sh.styled(Xlsx.section, ["PROGRESIJA PO DIONICI"])
        sh.styled(Xlsx.header, ["Datum", "Dionica", "Prosjek", "Najbolje", "Ponav."])
        for k in runProg.keys.sorted() {
            for p in runProg[k]! { sh.row([p.0, k, Xlsx.timeCell(p.1), Xlsx.timeCell(p.2), p.3]) }
        }
        sh.blank()

        // daily log
        sh.styled(Xlsx.section, ["DNEVNIK: SAN, SUPLEMENTI, UPITNIK"])
        let days = s.where(Store.daily, "athleteId", id).sorted { $0.string("date") < $1.string("date") }
        var qIds: [String] = []
        var qLabels: [String: String] = [:]
        for q in Wellness.questionnaire(s)["questions"].list where q.isObject {
            let k = q.string("id")
            if qLabels[k] == nil { qIds.append(k) }
            qLabels[k] = q.string("text")
        }
        for d in days {
            for (k, v) in d["wellnessLabels"].dict.sorted(by: { $0.key < $1.key }) where qLabels[k] == nil {
                qIds.append(k)
                qLabels[k] = v.asString
            }
        }
        head = ["Datum", "San (h)", "Proteini (mj.)", "Kreatin (g)", "Vitamini"]
        head += qIds.map { qLabels[$0] ?? $0 }
        sh.styled(Xlsx.header, head)
        var sleepSum = 0.0
        var sleepN = 0, wellN = 0
        for d in days {
            var row: [Any?] = [d.string("date")]
            if d.has("sleep") {
                row.append(d.double("sleep"))
                sleepSum += d.double("sleep")
                sleepN += 1
            } else {
                row.append("")
            }
            row.append(d.has("protein") ? d.double("protein") : "")
            row.append(d.has("creatine") ? d.double("creatine") : "")
            row.append(d["vitamins"].list.map { $0.asString }.joined(separator: ", "))
            if d.bool("wellnessDone") { wellN += 1 }
            let w = d["wellness"]
            for q in qIds {
                switch w[q] {
                case .arr(let a): row.append(a.map { $0.asString }.joined(separator: ", "))
                case .num(let n): row.append(n)
                case .null: row.append("")
                default: row.append(w[q].asString)
                }
            }
            sh.row(row)
        }
        return [name, Int(season.n), round2(season.km), round2(season.kg / 1000), sleepN == 0 ? "" : round2(sleepSum / Double(sleepN)), wellN, setsTotal]
    }

    private static func sessionsSheet(_ x: Xlsx, _ s: Store) {
        let sh = x.sheet("Treninzi")
        let groups = Groups.any(s)
        sh.setWidths([12, 12, 20, 90, 18])
        sh.styled(Xlsx.header, ["Datum", "Dan", "Naziv", "Sadržaj", groups ? "Za" : ""])
        let team = Groups.byName(s.all(Store.athletes))
        for ses in s.all(Store.sessions).sorted(by: { $0.string("date") < $1.string("date") }) {
            var b = ""
            for (i, it) in ses["items"].list.enumerated() where it.isObject {
                let p = Model.plan(it).replacingOccurrences(of: "  ·  ", with: ", ")
                b += (i > 0 ? " | " : "") + Model.title(it) + (p.isEmpty ? "" : " (" + p + ")")
                for at in team {
                    let own = Model.ownText(it, at.string("id")).replacingOccurrences(of: "  ·  ", with: ", ")
                    if !own.isEmpty { b += "; " + Fmt.shortName(at.string("name")) + ": " + own }
                }
            }
            var za = ""
            if groups {
                let gs = Groups.ofSession(s, ses)
                za = gs.isEmpty ? "Cijeli tim" : gs.map { Groups.name(s, $0) }.joined(separator: ", ")
            }
            sh.row([ses.string("date"), Fmt.dayShort(Fmt.date(ses.string("date"))), ses.string("title"), b, za])
        }
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

import SwiftUI

/// The athlete enters their own splits / sets for one session (SessionDoScreen.java).
struct SessionDoView: View {
    let sessionId: String
    /// Set when the coach's tablet logs for an athlete without a phone (Zapisnik).
    var athleteId: String? = nil
    var athleteName: String? = nil
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var result: JSON = .null
    @State private var dirty = false
    @State private var loaded = false
    @State private var rpePick: RpePick?

    struct RpePick: Identifiable {
        let itemId: String
        let index: Int
        let planned: String
        var id: String { "\(itemId)/\(index)" }
    }

    private var me: String { athleteId ?? Prefs.athleteId }
    private var myName: String { athleteName ?? Prefs.name }
    private var session: JSON? { store.doc(Store.sessions, sessionId) }

    var body: some View {
        Group {
            if let s = session {
                content(s)
            } else {
                EmptyCard(title: "Trening ne postoji", text: "Trener ga je možda obrisao.").padding(16)
                Spacer()
            }
        }
        .background(C.chalk)
        .navigationTitle(athleteName.map { Fmt.shortName($0) } ?? session?.string("title", "Trening") ?? "Trening")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .keyboardDone()
        .onAppear { load() }
        .onDisappear {
            if dirty {
                save()
                Toast.shared.show("Spremljeno")
            }
        }
        .sheet(item: $rpePick) { p in
            RpeSheet(planned: p.planned, now: result["entries"][p.itemId][p.index].string("rpe")) { v in
                result["entries"][p.itemId][p.index]["rpe"] = .str(v)
                Results.touch(&result, Results.cell(p.itemId, p.index))
                dirty = true
                rpePick = nil
            }
            .presentationDetents([.height(300)])
        }
    }

    @ViewBuilder private func content(_ s: JSON) -> some View {
        let items = s["items"].list.filter { $0.isObject }.map { Model.forAthlete($0, me) }
        let hasGym = items.contains { $0.string("type") == "gym" }
        let hasRpe = items.contains { $0.string("type") == "gym" && Fmt.num($0.string("rpe")) > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.niceRelative(s.string("date")) + (s.string("notes").isEmpty ? "" : "  ·  " + s.string("notes")))
                        .font(C.text(13)).foregroundColor(C.muted)
                    if hasGym {
                        Text(hasRpe ? "✓ = serija odrađena. Druga kilaža? Prepravi broj. Teže ili lakše? Dodirni @." : "✓ = serija odrađena. Druga kilaža? Prepravi broj.")
                            .font(C.text(12)).foregroundColor(C.muted)
                    }
                }
                if loaded {
                    ForEach(items, id: \.idKey) { it in
                        switch it.string("type") {
                        case "run": runCard(it)
                        case "gym": gymCard(it)
                        case "gps": typedRunCard(it)
                        default: header(it, accent: C.stone)
                        }
                    }
                    Field(label: "Komentar") {
                        TextField("Kako je prošlo? (nije obavezno)", text: commentBinding, axis: .vertical)
                            .lineLimit(1...5)
                            .padding(.vertical, 10)
                            .input()
                    }
                    .padding(.top, 6)
                    PillButton(title: "Spremi") {
                        save()
                        if Model.totals(session, result).done > 0 {
                            Toast.shared.show("Spremljeno. Bravo!")
                        } else {
                            Toast.shared.show("Spremljeno")
                        }
                        dismiss()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    static func rpeLabel(_ v: String) -> String { v.isEmpty ? "@–" : "@" + Fmt.n(Fmt.num(v)) }

    // MARK: data

    private func load() {
        guard let s = session else { return }
        if loaded && dirty { return }
        var r = store.doc(Store.results, Model.resultId(sessionId, me)) ?? [
            "id": .str(Model.resultId(sessionId, me)), "sessionId": .str(sessionId), "athleteId": .str(me),
            "athleteName": .str(myName), "date": .str(s.string("date")), "entries": .object(),
        ]
        if !r["entries"].isObject { r["entries"] = .object() }
        for raw in s["items"].list where raw.isObject {
            let it = Model.forAthlete(raw, me)
            let id = it.string("id")
            let type = it.string("type")
            let count = type == "run" ? max(1, Int(Fmt.num(it.string("reps"))))
                : type == "gym" ? max(1, Int(Fmt.num(it.string("sets"))))
                : type == "gps" ? 1 : 0
            if count == 0 { continue }
            var en = r["entries"][id]
            if !en.isArray { en = .array() }
            while en.count < count { en.append(.object()) }
            if type == "gym" {
                let planned = it.string("rpe")
                let askRpe = Fmt.num(planned) > 0
                for i in 0..<count {
                    var e = en[i].isObject ? en[i] : JSON.object()
                    // a set nobody has typed in or ticked yet shows the plan as it is now
                    let untouched = !e.bool("done") && !Results.edited(r, Results.cell(id, i))
                    if untouched || !e.has("kg") { e["kg"] = .str(it.string("kg")) }
                    if untouched || !e.has("reps") { e["reps"] = .str(it.string("reps")) }
                    if askRpe && (untouched || !e.has("rpe")) { e["rpe"] = .str(planned) } else if !askRpe && untouched { e.remove("rpe") }
                    en[i] = e
                }
            } else {
                for i in 0..<count where !en[i].isObject { en[i] = .object() }
            }
            r["entries"][id] = en
        }
        result = r
        loaded = true
    }

    private func save() {
        result["athleteName"] = .str(myName)
        store.put(Store.results, result)
        if let fresh = store.doc(Store.results, Model.resultId(sessionId, me)) { result = fresh }
        dirty = false
    }

    private var commentBinding: Binding<String> {
        Binding(get: { result.string(Results.comment) }, set: {
            result[Results.comment] = .str($0)
            Results.touch(&result, Results.comment)
            dirty = true
        })
    }

    private func field(_ itemId: String, _ i: Int, _ key: String) -> Binding<String> {
        Binding(get: { result["entries"][itemId][i].string(key) }, set: {
            result["entries"][itemId][i][key] = .str($0)
            Results.touch(&result, Results.cell(itemId, i))
            dirty = true
        })
    }

    // MARK: cards

    @ViewBuilder private func header(_ it: JSON, accent: Color) -> some View {
        Card { headerContent(it, accent: accent) }
    }

    @ViewBuilder private func headerContent(_ it: JSON, accent: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4, height: 18)
            Text(Model.title(it).uppercased()).font(C.display(17)).foregroundColor(C.ink)
            Spacer()
            if let key = Progress.keyFor(it) {
                NavigationLink(value: Route.series(key)) {
                    Text("Graf ›").font(C.bold(13)).foregroundColor(C.blue)
                }
                .simultaneousGesture(TapGesture().onEnded { if dirty { save() } })
            }
        }
        let plan = Model.plan(it) + (it.string("type") == "gym" && !it.string("rpe").isEmpty ? " (" + Model.rir(it.string("rpe")) + ")" : "")
        if !plan.isEmpty { Text(plan).font(C.bold(13)).foregroundColor(C.muted).padding(.top, 3) }
        let own = Model.ownText(it, me)
        if !own.isEmpty { Text("Za tebe:  " + own).font(C.bold(13)).foregroundColor(C.own).padding(.top, 3) }
        if !it.string("note").isEmpty { Text(it.string("note")).font(C.text(13)).foregroundColor(C.ink).padding(.top, 2) }
    }

    private func repNum(_ i: Int) -> some View {
        Text("\(i + 1)").font(C.display(14)).foregroundColor(C.ink)
            .frame(width: 28, height: 28)
            .background(Circle().fill(C.chalk))
            .overlay(Circle().stroke(C.stone, lineWidth: 1))
    }

    @ViewBuilder private func runCard(_ it: JSON) -> some View {
        let reps = max(1, Int(Fmt.num(it.string("reps"))))
        let target = Fmt.parseTime(it.string("target"))
        let id = it.string("id")
        Card {
            headerContent(it, accent: C.coral)
            ForEach(0..<reps, id: \.self) { i in
                let t = result["entries"][id][i].string("t")
                HStack(spacing: 10) {
                    repNum(i)
                    TimeFieldView(value: t, hint: it.string("target"), secondsOnly: target > 0 && target < 45) { v in
                        result["entries"][id][i]["t"] = .str(v)
                        Results.touch(&result, Results.cell(id, i))
                        dirty = true
                    }
                    Spacer(minLength: 4)
                    diffText(Fmt.parseTime(t), target)
                }
                .padding(.top, i == 0 ? 14 : 8)
            }
        }
    }

    @ViewBuilder private func diffText(_ t: Double, _ target: Double) -> some View {
        if t > 0 && target > 0 {
            let d = t - target
            if abs(d) < 0.005 {
                Text("točno").font(C.bold(14)).foregroundColor(C.green)
            } else {
                Text((d > 0 ? "+" : "−") + Fmt.secs(abs(d), pad: false) + " s").font(C.bold(14)).foregroundColor(d > 0 ? C.red : C.green)
            }
        }
    }

    @ViewBuilder private func gymCard(_ it: JSON) -> some View {
        let sets = max(1, Int(Fmt.num(it.string("sets"))))
        let id = it.string("id")
        let hold = Model.hold(it)
        let planned = it.string("rpe")
        let askRpe = Fmt.num(planned) > 0
        Card {
            headerContent(it, accent: C.blue)
            // order on screen: set, kg, reps, RPE, done
            HStack(spacing: 8) {
                Label12("#").frame(width: 28, alignment: .leading)
                Label12("kg").frame(maxWidth: .infinity)
                Label12(hold ? "Sek." : "Ponav.").frame(maxWidth: .infinity)
                if askRpe { Label12("RPE").frame(width: 54) }
                Label12("✓").frame(width: 44)
            }
            .padding(.top, 12)
            ForEach(0..<sets, id: \.self) { i in
                let e = result["entries"][id][i]
                let done = e.bool("done")
                HStack(spacing: 8) {
                    repNum(i).frame(width: 28, alignment: .leading)
                    TextField("kg", text: field(id, i, "kg")).keyboardType(.decimalPad).input(center: true)
                    TextField(hold ? "sek" : "pon", text: field(id, i, "reps")).keyboardType(.numberPad).input(center: true)
                    if askRpe {
                        let v = e.string("rpe")
                        let off = !v.isEmpty && Fmt.num(v) != Fmt.num(planned)
                        Button { rpePick = RpePick(itemId: id, index: i, planned: planned) } label: {
                            Text(SessionDoView.rpeLabel(v)).font(C.bold(15)).foregroundColor(off ? .white : C.ink)
                                .frame(width: 54, height: 44)
                                .background(RoundedRectangle(cornerRadius: 12).fill(off ? C.blueFill : C.chalk))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(off ? C.blueFill : C.stone, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        result["entries"][id][i]["done"] = .bool(!done)
                        Results.touch(&result, Results.cell(id, i))
                        dirty = true
                        if !done { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    } label: {
                        Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy))
                            .foregroundColor(done ? .white : C.faint)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(done ? C.green : C.chalk))
                            .scaleEffect(done ? 1.0 : 0.94)
                            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: done)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, i == 0 ? 4 : 8)
            }
        }
    }

    /// Run typed in by hand: km and time, pace against the target. A GPS run recorded on Android stays as it was.
    @ViewBuilder private func typedRunCard(_ it: JSON) -> some View {
        let id = it.string("id")
        let run = result["entries"][id][0]
        Card {
            headerContent(it, accent: C.green)
            if Model.recorded(run) {
                Text(Model.runLine(run)).font(C.bold(15)).foregroundColor(C.ink).padding(.top, 10)
            } else {
                TypedRun(km0: run.double("km"), s0: run.double("s"), target: Fmt.parseTime(it.string("pace"))) { km, s in
                    var e = result["entries"][id][0]
                    if !e.isObject { e = .object() }
                    if km > 0 { e["km"] = .num((km * 100).rounded() / 100) } else { e.remove("km") }
                    if s > 0 { e["s"] = .num(s.rounded()) } else { e.remove("s") }
                    e["manual"] = true
                    result["entries"][id][0] = e
                    Results.touch(&result, Results.cell(id, 0))
                    dirty = true
                }
                .padding(.top, 12)
            }
        }
    }
}

/// km box + time boxes, with the pace under them.
struct TypedRun: View {
    let target: Double
    let changed: (Double, Double) -> Void
    @State private var km: String
    @State private var seconds: Double

    private var pace: Double? {
        let k = Fmt.num(km)
        return k >= 0.05 && seconds > 0 ? seconds / k : nil
    }

    private func paceText(_ p: Double) -> String {
        var t = "Tempo " + Fmt.clock(p) + "/km"
        if target > 0 { t += "  ·  cilj " + Fmt.clock(target) + "/km" }
        return t
    }

    init(km0: Double, s0: Double, target: Double, changed: @escaping (Double, Double) -> Void) {
        self.target = target
        self.changed = changed
        _km = State(initialValue: km0 > 0 ? Fmt.n2(km0) : "")
        _seconds = State(initialValue: s0 > 0 ? s0 : -1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("km", text: $km).keyboardType(.decimalPad).input(center: true).frame(width: 80)
                    .onChange(of: km) { _ in changed(Fmt.num(km), seconds) }
                Text("km").font(C.bold(14)).foregroundColor(C.muted).padding(.trailing, 8)
                TimeFieldView(value: seconds > 0 ? Fmt.time(seconds) : "", hint: "", secondsOnly: false) { v in
                    seconds = Fmt.parseTime(v)
                    changed(Fmt.num(km), seconds)
                }
                Spacer(minLength: 0)
            }
            if let p = pace {
                Text(paceText(p)).font(C.bold(14)).foregroundColor(C.pace(Model.paceLevel(p, target)))
            }
        }
    }
}

/// Time entry without a colon on the number pad: a minutes box and a seconds box (TimeField.java).
/// Seconds typed under a grey target "1 : 30" put the target's minute in for real when that's closer to it.
struct TimeFieldView: View {
    let hint: String
    let secondsOnlyWanted: Bool
    let changed: (String) -> Void
    /// Only minutes typed over the grey hint: the hint's seconds count, as shown ("5" over 4:30 = 5:30).
    var keepHintSeconds = false
    @State private var min: String
    @State private var sec: String
    @State private var autoMin = false

    init(value: String, hint: String, secondsOnly: Bool, keepHintSeconds: Bool = false, changed: @escaping (String) -> Void) {
        self.hint = hint
        self.secondsOnlyWanted = secondsOnly
        self.keepHintSeconds = keepHintSeconds
        self.changed = changed
        let v = Fmt.parseTime(value)
        if v < 0 {
            _min = State(initialValue: "")
            _sec = State(initialValue: "")
        } else {
            let r = (v * 100).rounded() / 100
            let m = Int(r / 60)
            _min = State(initialValue: m > 0 ? "\(m)" : "")
            _sec = State(initialValue: Fmt.secs(r - Double(m * 60), pad: m > 0))
        }
    }

    private var hintTotal: Double {
        let v = Fmt.parseTime(hint)
        return v > 0 ? (v * 100).rounded() / 100 : 0
    }
    private var hintMin: Int { Int(hintTotal / 60) }
    private var secondsOnly: Bool { secondsOnlyWanted && min.isEmpty }

    var body: some View {
        HStack(spacing: 4) {
            if !secondsOnly {
                TextField(hintMin > 0 ? "\(hintMin)" : "min", text: $min)
                    .keyboardType(.numberPad).input(center: true).frame(width: 56)
                    .onChange(of: min) { m in
                        // the minute we filled in ourselves stays "auto" until someone types in the box
                        if !(autoMin && m == "\(hintMin)") { autoMin = false }
                        emit()
                    }
                Text(":").font(C.display(20)).foregroundColor(C.ink)
            }
            TextField(hintTotal > 0 ? Fmt.secs(hintTotal - Double(hintMin * 60), pad: hintMin > 0) : "sek", text: $sec)
                .keyboardType(.decimalPad).input(center: true).frame(width: 80)
                .onChange(of: sec) { s in
                    fillMinute(s)
                    emit()
                }
        }
        .font(C.bold(18))
    }

    private func fillMinute(_ text: String) {
        if hintMin <= 0 || secondsOnly { return }
        if !min.isEmpty && !autoMin { return }
        let s = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? -1
        let fill = s >= 0 && abs(Double(hintMin * 60) + s - hintTotal) < abs(s - hintTotal)
        autoMin = fill
        min = fill ? "\(hintMin)" : ""
    }

    private func emit() {
        let s = sec.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let m = min.trimmingCharacters(in: .whitespaces)
        if s.isEmpty && m.isEmpty { changed(""); return }
        guard let mm = m.isEmpty ? 0 : Int(m), let ss = s.isEmpty ? 0 : Double(s) else { return }
        if keepHintSeconds && s.isEmpty && hintTotal > 0 {
            changed(Fmt.time(Double(mm) * 60 + hintTotal.truncatingRemainder(dividingBy: 60)))
            return
        }
        changed(Fmt.time(Double(mm) * 60 + ss))
    }
}

/// How hard the set really was: starts at the coach's @, a tap on another number changes it.
struct RpeSheet: View {
    let planned: String
    let now: String
    let pick: (String) -> Void
    static let values = ["6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KOLIKO JE BILO TEŠKO?").font(C.display(18)).foregroundColor(C.ink)
            Text("Trener je zadao @" + Fmt.n(Fmt.num(planned)) + " (" + Model.rir(planned) + ").").font(C.text(13)).foregroundColor(C.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(RpeSheet.values, id: \.self) { v in
                    let on = !now.isEmpty && Fmt.num(now) == Fmt.num(v)
                    Button { pick(v) } label: {
                        Text(Fmt.n(Fmt.num(v))).font(C.bold(16)).foregroundColor(on ? C.onSel : C.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(on ? C.sel : C.card))
                            .overlay(Capsule().stroke(on ? C.sel : C.stone, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("10 = do otkaza, 9 = 1 u rezervi, 8 = 2 u rezervi…").font(C.text(12)).foregroundColor(C.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.chalk)
    }
}

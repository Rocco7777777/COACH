import SwiftUI

/// Coach's Zapisnik (LogbookScreen.java): during a session the coach logs everyone's reps and sets, one rep or set
/// at a time for the whole group. A teammate without a phone taps their name and fills in their own form.
/// Everything is saved as each athlete's own result (profile, Napredak, leaderboards, Excel).
struct LogbookView: View {
    let sessionId: String
    @Binding var path: NavigationPath
    @ObservedObject var store = Store.shared
    /// itemId → rep / set on screen
    @State private var step: [String: Int] = [:]
    /// athleteId → that athlete's result being edited
    @State private var docs: [String: JSON] = [:]
    @State private var dirty = Set<String>()
    @State private var autosave: Task<Void, Never>?

    private var session: JSON? { store.doc(Store.sessions, sessionId) }

    var body: some View {
        Group {
            if let s = session {
                content(s, Groups.audience(store, s))
            } else {
                VStack {
                    EmptyCard(title: "Trening ne postoji", text: "Možda je obrisan.").padding(16)
                    Spacer()
                }
            }
        }
        .background(C.chalk)
        .navigationTitle("Zapisnik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .keyboardDone()
        .onDisappear { flush() }
    }

    private func content(_ s: JSON, _ athletes: [JSON]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(s.string("title", "Trening") + "  ·  " + Fmt.niceRelative(s.string("date"))).font(C.text(13)).foregroundColor(C.muted)
                if athletes.isEmpty {
                    EmptyCard(title: "Još nema sportaša", text: "Pozovi ih kodom tima pod SPORTAŠI.")
                } else {
                    noPhone(s, athletes)
                    ForEach(s["items"].list.filter { $0.isObject }, id: \.idKey) { it in
                        switch it.string("type") {
                        case "run": runCard(it, athletes)
                        case "gym": gymCard(it, athletes)
                        case "gps": typedRunCard(it, athletes)
                        default: EmptyView()
                        }
                    }
                    Text("Sprema se samo, kod svakog upisa. Sportaš vidi rezultate na svom profilu čim mu se mobitel sinkronizira.")
                        .font(C.text(12)).foregroundColor(C.muted).padding(.top, 4)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: data

    /// The result of one athlete for this session: what's being edited here, else what's stored, else a new one.
    private func doc(_ athleteId: String, _ name: String) -> JSON {
        if let d = docs[athleteId] { return d }
        if let d = store.doc(Store.results, Model.resultId(sessionId, athleteId)) { return d }
        return ["id": .str(Model.resultId(sessionId, athleteId)), "sessionId": .str(sessionId), "athleteId": .str(athleteId),
                "athleteName": .str(name), "date": .str(session?.string("date") ?? Fmt.today()), "entries": .object()]
    }

    private func edit(_ athleteId: String, _ name: String, _ itemId: String, _ k: Int, _ change: (inout JSON) -> Void) {
        var d = doc(athleteId, name)
        if !d["entries"].isObject { d["entries"] = .object() }
        var en = d["entries"][itemId]
        if !en.isArray { en = .array() }
        while en.count <= k { en.append(.object()) }
        var e = en[k].isObject ? en[k] : JSON.object()
        change(&e)
        en[k] = e
        d["entries"][itemId] = en
        d["athleteName"] = .str(name)
        Results.touch(&d, Results.cell(itemId, k))
        docs[athleteId] = d
        dirty.insert(athleteId)
        autosave?.cancel()
        autosave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { flush() }
        }
    }

    /// Saves edited results now; the store merges them per set with what athletes typed meanwhile.
    private func flush() {
        autosave?.cancel()
        for id in dirty {
            guard let d = docs[id] else { continue }
            store.put(Store.results, d)
        }
        dirty.removeAll()
        // pick up what athletes saved from their phones
        docs.removeAll()
    }

    private static func count(_ it: JSON, _ field: String) -> Int { max(1, Int(Fmt.num(it.string(field)))) }

    /// Most reps / sets anyone has on this item (the coach can give one athlete more).
    private func most(_ it: JSON, _ field: String, _ athletes: [JSON]) -> Int {
        athletes.map { Self.count(Model.forAthlete(it, $0.string("id")), field) }.max() ?? Self.count(it, field)
    }

    private static func logged(_ type: String, _ e: JSON) -> Bool {
        if !e.isObject { return false }
        return type == "run" ? Fmt.parseTime(e.string("t")) > 0 : e.bool("done")
    }

    /// [reps and sets logged, reps and sets planned] for one athlete.
    private func filled(_ s: JSON, _ athleteId: String) -> (Int, Int) {
        let r = store.doc(Store.results, Model.resultId(sessionId, athleteId))
        var done = 0, all = 0
        for raw in s["items"].list where raw.isObject {
            let it = Model.forAthlete(raw, athleteId)
            let type = it.string("type")
            let n = type == "run" ? Self.count(it, "reps") : type == "gym" ? Self.count(it, "sets") : 0
            let en = Model.entries(r, it.string("id"))
            for k in 0..<n where k < en.count && Self.logged(type, en[k]) { done += 1 }
            all += n
        }
        return (done, all)
    }

    /// First rep / set somebody hasn't logged yet, so the Zapisnik opens where the group is.
    private func current(_ it: JSON, _ type: String, _ n: Int, _ athletes: [JSON]) -> Int {
        let itemId = it.string("id")
        if let s = step[itemId] { return min(s, n - 1) }
        let field = type == "run" ? "reps" : "sets"
        for k in 0..<n {
            for at in athletes {
                let id = at.string("id")
                if k >= Self.count(Model.forAthlete(it, id), field) { continue }
                let en = Model.entries(doc(id, at.string("name")), itemId)
                if !(k < en.count && Self.logged(type, en[k])) { return k }
            }
        }
        return n - 1
    }

    // MARK: parts

    private func noPhone(_ s: JSON, _ athletes: [JSON]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BEZ MOBITELA? DODIRNI SVOJE IME I UPIŠI SAM").font(.system(size: 11, weight: .bold)).tracking(0.9).foregroundColor(C.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(athletes, id: \.idKey) { at in
                        let n = filled(s, at.string("id"))
                        let all = n.1 > 0 && n.0 >= n.1
                        Button {
                            flush()
                            path.append(CoachRoute.logFor(sessionId, at.string("id"), at.string("name")))
                        } label: {
                            Text(Fmt.shortName(at.string("name")) + (n.1 > 0 ? "  \(n.0)/\(n.1)" : ""))
                                .font(C.bold(14)).foregroundColor(C.ink)
                                .padding(.horizontal, 12).frame(minHeight: 40)
                                .background(Capsule().fill(all ? C.greenSoft : C.card))
                                .overlay(Capsule().stroke(all ? C.greenSoft : C.stone, lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func header(_ it: JSON, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4, height: 18)
                Text(Model.title(it).uppercased()).font(C.display(17)).foregroundColor(C.ink)
            }
            let plan = Model.plan(it)
            if !plan.isEmpty { Text(plan).font(C.bold(13)).foregroundColor(C.muted) }
        }
    }

    private func stepper(_ itemId: String, _ k: Int, _ n: Int, _ word: String) -> some View {
        HStack {
            roundButton("chevron.left") { go(itemId, k - 1) }.disabled(k <= 0).opacity(k > 0 ? 1 : 0.3)
            Text("\(word) \(k + 1) / \(n)").font(C.display(15)).tracking(0.6).foregroundColor(C.ink).frame(maxWidth: .infinity)
            roundButton("chevron.right") { go(itemId, k + 1) }.disabled(k >= n - 1).opacity(k < n - 1 ? 1 : 0.3)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(C.chalk))
    }

    private func go(_ itemId: String, _ k: Int) {
        flush()
        step[itemId] = k
    }

    /// Name over a small line with every rep / set of that athlete, the one on screen in coral.
    private func who(_ name: String, _ line: Text, _ own: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Fmt.shortName(name)).font(C.bold(14)).foregroundColor(C.ink).lineLimit(1)
            line.font(.system(size: 11, weight: .semibold)).lineLimit(1)
            if !own.isEmpty { Text(own).font(.system(size: 11, weight: .semibold)).foregroundColor(C.own).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ d: JSON, _ it: JSON, _ n: Int, _ k: Int) -> Text {
        let en = Model.entries(d, it.string("id"))
        let run = it.string("type") == "run"
        let hold = Model.hold(it)
        var out = Text("")
        for i in 0..<n {
            let e = i < en.count ? en[i] : JSON.null
            let v: String
            if run { v = e.string("t").isEmpty ? "–" : e.string("t") } else { v = e.bool("done") ? e.string("kg") + "×" + e.string("reps") + (hold ? "s" : "") : "–" }
            out = out + Text((i > 0 ? "  " : "") + v).foregroundColor(i == k ? C.coral : Color(hex: 0x9CA1A5))
        }
        return out
    }

    // run reps: everyone's time for rep k

    private func runCard(_ it: JSON, _ athletes: [JSON]) -> some View {
        let itemId = it.string("id")
        let all = most(it, "reps", athletes)
        let k = current(it, "run", all, athletes)
        return Card {
            header(it, C.coral)
            stepper(itemId, k, all, "DIONICA").padding(.top, 10)
            ForEach(athletes, id: \.idKey) { at in
                let id = at.string("id"), name = at.string("name")
                let mine = Model.forAthlete(it, id)
                let n = Self.count(mine, "reps")
                if k < n {
                    let target = Fmt.parseTime(mine.string("target"))
                    let d = doc(id, name)
                    let e = Model.entries(d, itemId)
                    let t = k < e.count ? e[k].string("t") : ""
                    HStack(spacing: 6) {
                        who(name, line(d, it, n, k), Model.ownText(it, id))
                        TimeFieldView(value: t, hint: mine.string("target"), secondsOnly: target > 0 && target < 45) { v in
                            edit(id, name, itemId, k) { $0["t"] = .str(v) }
                        }
                        .id("\(id)/\(itemId)/\(k)")
                        DiffText(t: Fmt.parseTime(t), target: target).frame(width: 50, alignment: .trailing)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // gym sets: everyone's kg and reps for set k

    private func gymCard(_ it: JSON, _ athletes: [JSON]) -> some View {
        let itemId = it.string("id")
        let all = most(it, "sets", athletes)
        let k = current(it, "gym", all, athletes)
        let hold = Model.hold(it)
        return Card {
            header(it, C.blue)
            stepper(itemId, k, all, "SERIJA").padding(.top, 10)
            HStack(spacing: 6) {
                Spacer()
                Label12("kg").frame(width: 64)
                Label12(hold ? "Sek." : "Pon.").frame(width: 52)
                Label12("✓").frame(width: 44)
            }
            .padding(.top, 8)
            ForEach(athletes, id: \.idKey) { at in
                let id = at.string("id"), name = at.string("name")
                let mine = Model.forAthlete(it, id)
                if k < Self.count(mine, "sets") {
                    gymRow(it, mine, at, k).padding(.top, 8)
                }
            }
        }
    }

    private func gymRow(_ it: JSON, _ mine: JSON, _ at: JSON, _ k: Int) -> some View {
        let id = at.string("id"), name = at.string("name"), itemId = it.string("id")
        let d = doc(id, name)
        let en = Model.entries(d, itemId)
        let e = k < en.count ? en[k] : JSON.object()
        let n = Self.count(mine, "sets")
        // not typed or ticked yet: what this athlete lifted in the set before, else their plan
        var before: JSON? = k > 0 && k - 1 < en.count ? en[k - 1] : nil
        if let b = before, !b.bool("done") && !Results.edited(d, Results.cell(itemId, k - 1)) { before = nil }
        let untouched = !e.bool("done") && !Results.edited(d, Results.cell(itemId, k))
        func shown(_ key: String) -> String {
            if untouched || !e.has(key) {
                let b = before?.string(key) ?? ""
                return b.isEmpty ? mine.string(key) : b
            }
            return e.string(key)
        }
        let kg = shown("kg"), reps = shown("reps")
        let done = e.bool("done")
        return HStack(spacing: 6) {
            who(name, line(d, it, n, k), Model.ownText(it, id))
            TextField("kg", text: Binding(get: { kg }, set: { v in
                edit(id, name, itemId, k) { c in
                    if untouched { prefill(&c, kg, reps) }
                    c["kg"] = .str(v)
                }
            }))
                .keyboardType(.decimalPad).input(center: true).frame(width: 64)
            TextField(Model.hold(it) ? "sek" : "pon", text: Binding(get: { reps }, set: { v in
                edit(id, name, itemId, k) { c in
                    if untouched { prefill(&c, kg, reps) }
                    c["reps"] = .str(v)
                }
            }))
                .keyboardType(.numberPad).input(center: true).frame(width: 52)
            Button {
                edit(id, name, itemId, k) { c in
                    let on = !c.bool("done")
                    if untouched { prefill(&c, kg, reps) }
                    c["done"] = .bool(on)
                }
            } label: {
                Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy))
                    .foregroundColor(done ? .white : C.faint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(done ? C.green : C.chalk))
            }
            .buttonStyle(.plain)
        }
    }

    /// A set nobody touched yet gets what's on screen; no @ column here, so a set ticked here counts the
    /// athlete's planned @, not one left from an older plan.
    private func prefill(_ c: inout JSON, _ kg: String, _ reps: String) {
        c["kg"] = .str(kg)
        c["reps"] = .str(reps)
        c.remove("rpe")
    }

    // runs in km: typed in per athlete

    private func typedRunCard(_ it: JSON, _ athletes: [JSON]) -> some View {
        let itemId = it.string("id")
        return Card {
            header(it, C.green)
            ForEach(athletes, id: \.idKey) { at in
                let id = at.string("id"), name = at.string("name")
                let target = Fmt.parseTime(Model.forAthlete(it, id).string("pace"))
                let run = Model.entries(doc(id, name), itemId).first ?? .object()
                let own = Model.ownText(it, id)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.shortName(name) + (own.isEmpty ? "" : "   " + own)).font(C.bold(14)).foregroundColor(C.ink)
                    if Model.recorded(run) {
                        Text(Model.runLine(run)).font(C.bold(13)).foregroundColor(C.ink)
                    } else {
                        TypedRun(km0: run.double("km"), s0: run.double("s"), target: target) { km, s in
                            edit(id, name, itemId, 0) { e in
                                if km > 0 { e["km"] = .num((km * 100).rounded() / 100) } else { e.remove("km") }
                                if s > 0 { e["s"] = .num(s.rounded()) } else { e.remove("s") }
                                e["manual"] = true
                            }
                        }
                        .id(id + "/" + itemId)
                    }
                }
                .padding(.top, 10)
            }
        }
    }
}

/// "+0,4 s" red, "−0,2 s" green, "točno" against the target split.
struct DiffText: View {
    let t: Double
    let target: Double
    var body: some View {
        if t > 0 && target > 0 {
            let d = t - target
            if abs(d) < 0.005 {
                Text("točno").font(C.bold(13)).foregroundColor(C.green)
            } else {
                Text((d > 0 ? "+" : "−") + Fmt.secs(abs(d), pad: false) + " s").font(C.bold(13)).foregroundColor(d > 0 ? C.red : C.green)
            }
        }
    }
}

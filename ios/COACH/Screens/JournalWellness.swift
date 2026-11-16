import SwiftUI

// MARK: DNEVNIK

struct JournalTab: View {
    @ObservedObject var store = Store.shared
    let openWellness: () -> Void
    @State private var day = Fmt.today()
    @State private var editWellness: String?

    private var me: String { Prefs.athleteId }

    var body: some View {
        let marked = Set(store.where(Store.daily, "athleteId", me).map { $0.string("date") })
        let d = Wellness.daily(store, me, day)
        VStack(spacing: 0) {
            DateStrip(day: $day, from: -27, count: 29, marked: marked)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Fmt.niceRelative(day).uppercased()).font(C.display(22)).foregroundColor(C.carbon)
                    Card {
                        StepRow(name: "San", unit: "sati", value: d.has("sleep") ? d.double("sleep", 8) : 8, step: 0.5, lo: 0, hi: 14, suffix: " h") { save("sleep", .num($0)) }
                        Divider().padding(.vertical, 10)
                        StepRow(name: "Proteini", unit: "mjerice", value: d.double("protein"), step: 0.5, lo: 0, hi: 10, suffix: "") { save("protein", .num($0)) }
                        Divider().padding(.vertical, 10)
                        StepRow(name: "Kreatin", unit: "grama", value: d.double("creatine"), step: 1, lo: 0, hi: 30, suffix: " g") { save("creatine", .num($0)) }
                        Divider().padding(.vertical, 10)
                        Text("Vitamini i ostalo").font(C.bold(14)).foregroundColor(C.carbon)
                        let on = Set(d["vitamins"].list.map { $0.asString })
                        FlowLayout(spacing: 6) {
                            ForEach(Model.vitamins, id: \.self) { v in
                                Chip(title: on.contains(v) ? "✓ " + v : v, on: on.contains(v)) {
                                    var next = on
                                    if next.contains(v) { next.remove(v) } else { next.insert(v) }
                                    save("vitamins", .arr(Model.vitamins.filter { next.contains($0) }.map { .str($0) }))
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    Card {
                        let done = d.bool("wellnessDone")
                        HStack {
                            Label12("Jutarnji upitnik")
                            Spacer()
                            Tag(text: done ? "Ispunjeno" : "Nije ispunjeno", fg: done ? .white : C.carbon, bg: done ? C.green : C.coralSoft)
                        }
                        if done {
                            Text(Self.summary(d)).font(C.text(13)).foregroundColor(C.carbon).padding(.top, 8)
                        }
                        GhostButton(title: done ? "Uredi odgovore" : "Ispuni upitnik") { editWellness = day }
                            .padding(.top, 12)
                    }
                }
                .padding(16)
            }
        }
        .sheet(item: Binding(get: { editWellness.map { DayId(id: $0) } }, set: { editWellness = $0?.id })) { x in
            WellnessView(date: x.id) { editWellness = nil }
        }
    }

    struct DayId: Identifiable { let id: String }

    private func save(_ field: String, _ v: JSON) {
        var d = Wellness.daily(store, me, day)
        d[field] = v
        d["athleteName"] = .str(Prefs.name)
        store.put(Store.daily, d)
    }

    static func summary(_ d: JSON) -> String {
        let w = d["wellness"]
        var lines: [String] = []
        for k in w.keys.sorted() {
            let v = w[k]
            let txt = v.isArray ? v.list.map { $0.asString }.joined(separator: ", ") : v.asString
            if txt.isEmpty { continue }
            let label = d["wellnessLabels"].string(k, k)
            lines.append(label + ": " + txt)
        }
        return lines.joined(separator: "\n")
    }
}

struct StepRow: View {
    let name: String
    let unit: String
    let value: Double
    let step: Double
    let lo: Double
    let hi: Double
    let suffix: String
    let set: (Double) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(C.bold(15)).foregroundColor(C.carbon)
                Text(unit).font(C.text(12)).foregroundColor(C.muted)
            }
            Spacer()
            HStack(spacing: 0) {
                stepButton("−") { set(max(lo, value - step)) }
                Text(Fmt.n(value) + suffix).font(C.display(18)).foregroundColor(C.carbon).frame(minWidth: 70)
                stepButton("+") { set(min(hi, value + step)) }
            }
        }
    }

    private func stepButton(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(C.display(20)).foregroundColor(C.carbon)
                .frame(width: 44, height: 44)
                .background(Circle().fill(C.chalk))
                .overlay(Circle().stroke(C.stone, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}

// MARK: Jutarnji upitnik

struct WellnessView: View {
    let date: String
    let close: () -> Void
    @ObservedObject var store = Store.shared
    @State private var answers: JSON = .object()
    @State private var loaded = false

    private var questions: [JSON] { Wellness.questionnaire(store)["questions"].list.filter { $0.isObject } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DOBRO JUTRO").font(C.display(22)).foregroundColor(C.carbon).padding(.top, 6)
                    Text(Fmt.niceRelative(date) + "  ·  par klikova i gotovo").font(C.text(13)).foregroundColor(C.muted)
                    let qs = questions
                    ForEach(Array(qs.enumerated()), id: \.offset) { i, q in
                        if shown(qs, i) { question(q) }
                    }
                    PillButton(title: "Gotovo") { finish() }.padding(.top, 10)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(C.chalk)
            .navigationTitle("Jutarnji upitnik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zatvori") { close() }.foregroundColor(C.carbon) }
            }
        }
        .onAppear {
            if !loaded {
                answers = Wellness.daily(store, Prefs.athleteId, date)["wellness"]
                if !answers.isObject { answers = .object() }
                loaded = true
            }
        }
    }

    /// A question marked "only if yes" shows only when the yes/no right before it is answered DA.
    private func shown(_ qs: [JSON], _ i: Int) -> Bool {
        let q = qs[i]
        if !q.bool("onlyIfYes") || i == 0 { return true }
        let prev = qs[i - 1]
        if prev.string("type") != "yesno" { return true }
        return answers.string(prev.string("id")) == "da"
    }

    @ViewBuilder private func question(_ q: JSON) -> some View {
        let id = q.string("id")
        Card {
            Text(q.string("text")).font(C.bold(15)).foregroundColor(C.carbon)
            switch q.string("type") {
            case "scale":
                let cur = answers.int(id)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { v in
                        Button {
                            answers[id] = .num(Double(v))
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text("\(v)").font(C.display(18)).foregroundColor(cur == v ? .white : C.carbon)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Capsule().fill(cur == v ? C.scale(v) : C.chalk))
                                .overlay(Capsule().stroke(cur == v ? C.scale(v) : C.stone, lineWidth: 1))
                                .scaleEffect(cur == v ? 1.06 : 1)
                                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: cur)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
                HStack {
                    Text(q.string("low")).font(C.text(12)).foregroundColor(C.muted)
                    Spacer()
                    Text(q.string("high")).font(C.text(12)).foregroundColor(C.muted)
                }
                .padding(.top, 4)
            case "yesno":
                let cur = answers.string(id)
                HStack(spacing: 10) {
                    ForEach(["da", "ne"], id: \.self) { opt in
                        Button { answers[id] = .str(opt) } label: {
                            Text(opt.uppercased()).font(C.display(15)).foregroundColor(cur == opt ? .white : C.carbon)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Capsule().fill(cur == opt ? C.carbon : C.chalk))
                                .overlay(Capsule().stroke(cur == opt ? C.carbon : C.stone, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            case "multi":
                let opts = q["options"].list.map { $0.asString }
                let on = Set(answers[id].list.map { $0.asString })
                FlowLayout(spacing: 6) {
                    ForEach(opts, id: \.self) { o in
                        Chip(title: o, on: on.contains(o)) {
                            var next = on
                            if next.contains(o) { next.remove(o) } else { next.insert(o) }
                            answers[id] = .arr(opts.filter { next.contains($0) }.map { .str($0) })
                        }
                    }
                }
                .padding(.top, 12)
            default:
                TextField("Upiši…", text: Binding(get: { answers.string(id) }, set: { answers[id] = .str($0) }), axis: .vertical)
                    .lineLimit(1...4).padding(.vertical, 10).input()
                    .padding(.top, 10)
            }
        }
    }

    private func finish() {
        let qs = questions
        var kept = JSON.object()
        var labels = JSON.object()
        for (i, q) in qs.enumerated() {
            let id = q.string("id")
            if shown(qs, i) && answers.has(id) { kept[id] = answers[id] }
            labels[id] = .str(q.string("text"))
        }
        var d = Wellness.daily(store, Prefs.athleteId, date)
        d["wellness"] = kept
        d["wellnessLabels"] = labels
        d["wellnessDone"] = true
        d["athleteName"] = .str(Prefs.name)
        store.put(Store.daily, d)
        if date == Fmt.today() {
            Reminders.clearDelivered()
            Reminders.schedule()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Toast.shared.show("Hvala! Ugodan trening.")
        close()
    }
}

import SwiftUI

/// KOPIRAJ TRENING: the day to copy to and which gym exercises get a changed weight (SessionCopyScreen.java).
/// Tick the key exercises, type a percentage: only their kg changes, sets, reps and RPE stay.
struct CopySessionForm: View {
    let source: JSON
    let done: (JSON) -> Void
    @ObservedObject var store = Store.shared
    @State private var date: Date
    @State private var calendar = false
    @State private var percent: String
    @State private var step: Double
    @State private var ticked: Set<String>

    init(source: JSON, date: Date, done: @escaping (JSON) -> Void) {
        self.source = source
        self.done = done
        var on = SessionCopy.preticked(source)
        // the build machine's screenshot shows the feature in use
        if Shot.name == "c-copy" { on = Set(SessionCopy.scalable(source).prefix(2).map { $0.string("id") }) }
        _date = State(initialValue: date)
        _percent = State(initialValue: SessionCopy.defaultPercent)
        _step = State(initialValue: SessionCopy.step)
        _ticked = State(initialValue: on)
    }

    var body: some View {
        let items = SessionCopy.scalable(source)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sourceCard
                dayCard
                if items.isEmpty {
                    Text("Ovaj trening nema vježbi s upisanom kilažom.")
                        .font(C.text(13)).foregroundColor(C.muted).padding(.horizontal, 2)
                } else {
                    kgCard(items)
                }
                PillButton(title: "Kopiraj") { copy() }.padding(.top, 6)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(C.chalk)
        .keyboardDone()
    }

    // MARK: parts

    private var sourceCard: some View {
        let items = source["items"].list.filter { $0.isObject }.map { Model.title($0) }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        return Card {
            Label12("Kopiraš")
            Text(source.string("title", "Trening").uppercased()).font(C.display(16)).foregroundColor(C.ink).padding(.top, 4)
            Text(Fmt.nice(source.string("date"))).font(C.text(13)).foregroundColor(C.muted).padding(.top, 2)
            if !items.isEmpty { Text(items).font(C.text(13)).foregroundColor(C.muted).padding(.top, 4) }
        }
    }

    private var dayCard: some View {
        Card {
            HStack(spacing: 8) {
                Text("Na dan").font(C.bold(15)).foregroundColor(C.ink)
                Spacer(minLength: 8)
                Button { calendar.toggle() } label: {
                    Text("📅  " + Fmt.nice(Fmt.iso(date))).font(C.bold(14)).foregroundColor(C.ink)
                        .padding(.horizontal, 12).frame(height: 46)
                        .background(Capsule().stroke(C.stone, lineWidth: 1.2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if calendar {
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "hr_HR"))
                    .tint(C.coral)
                    .padding(.top, 6)
            }
        }
    }

    private func kgCard(_ items: [JSON]) -> some View {
        let p = SessionCopy.percent(percent)
        let names = athleteNames
        return Card {
            HStack(spacing: 8) {
                Text("Povećaj kilažu").font(C.bold(15)).foregroundColor(C.ink)
                Spacer(minLength: 8)
                TextField("0", text: $percent)
                    .keyboardType(.numbersAndPunctuation).submitLabel(.done).autocorrectionDisabled()
                    .input(center: true).frame(width: 84)
                Text("%").font(C.bold(16)).foregroundColor(C.ink)
            }
            Label12("Zaokruži na").padding(.top, 12)
            HStack(spacing: 6) {
                ForEach(SessionCopy.steps, id: \.self) { st in
                    Chip(title: Fmt.n(st) + " kg", on: step == st) { step = st }
                }
            }
            .padding(.top, 6)
            Text("Označi vježbe kojima se mijenja kilaža. Ponavljanja i RPE ostaju isti.")
                .font(C.text(12)).foregroundColor(C.muted).padding(.top, 12)
            ForEach(items, id: \.idKey) { it in
                Rectangle().fill(C.stone).frame(height: 1).padding(.top, 10)
                CopyTickRow(item: it, on: ticked.contains(it.string("id")), percent: p, step: step, names: names) {
                    toggle(it.string("id"))
                }
            }
        }
    }

    // MARK: data

    private var athleteNames: [String: String] {
        var m: [String: String] = [:]
        for at in store.all(Store.athletes) { m[at.string("id")] = Fmt.shortName(at.string("name")) }
        return m
    }

    private func toggle(_ id: String) {
        if ticked.contains(id) { ticked.remove(id) } else { ticked.insert(id) }
    }

    private func copy() {
        hideKeyboard()
        let n = SessionCopy.make(store, source, date: Fmt.iso(date), ticked: ticked, percent: SessionCopy.percent(percent), step: step)
        store.put(Store.sessions, n)
        SessionCopy.remember(source, ticked, step)
        done(store.doc(Store.sessions, n.string("id")) ?? n)
    }
}

/// One gym exercise that can get a changed weight: the tick, the plan with what its kg becomes,
/// and a line for every athlete who has their own kg.
struct CopyTickRow: View {
    let item: JSON
    let on: Bool
    let percent: Double
    let step: Double
    let names: [String: String]
    let tap: () -> Void

    struct Own: Identifiable {
        let id: String
        let name: String
        let kg: String
    }

    var body: some View {
        Button(action: tap) {
            HStack(alignment: .top, spacing: 12) {
                tick
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.string("name").uppercased()).font(C.display(14)).foregroundColor(C.ink)
                        .multilineTextAlignment(.leading)
                    if !planHead.isEmpty || Fmt.num(item.string("kg")) > 0 { line(planHead, item.string("kg"), own: false) }
                    ForEach(owns) { o in line(o.name, o.kg, own: true) }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tick: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(on ? C.coral : C.field)
            RoundedRectangle(cornerRadius: 7).stroke(on ? C.coral : C.stone, lineWidth: 1.5)
            if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundColor(C.night) }
        }
        .frame(width: 28, height: 28)
    }

    /// "4 × 5", "45 s" for a hold; empty when the plan has neither.
    private var planHead: String {
        let sets = item.string("sets"), reps = item.string("reps")
        if sets.isEmpty && reps.isEmpty { return "" }
        return (sets.isEmpty ? "?" : sets) + " × " + (reps.isEmpty ? "?" : reps) + (Model.hold(item) ? " s" : "")
    }

    /// Athletes with their own kg on this item, by name.
    private var owns: [Own] {
        let per = item["per"]
        var out: [Own] = []
        for id in per.keys {
            let kg = per[id].string("kg")
            if let name = names[id], Fmt.num(kg) > 0 { out.append(Own(id: id, name: name, kg: kg)) }
        }
        return out.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// "4 × 5  ·  100 kg"; ticked: "4 × 5  ·  100 → 105 kg" with the new weight in bold.
    private func line(_ head: String, _ kg: String, own: Bool) -> some View {
        let old = Fmt.num(kg) > 0 ? Model.number(kg) : ""
        let new: String? = on && percent != 0 ? SessionCopy.scaledText(kg, percent, step) : nil
        let sep = head.isEmpty || old.isEmpty ? "" : "  ·  "
        let tail = old.isEmpty ? "" : (new == nil ? old + " kg" : old + " → ")
        let color: Color = own ? C.own : C.muted
        return HStack(spacing: 0) {
            Text(head + sep + tail).font(own ? C.bold(13) : C.text(13)).foregroundColor(color)
            if let n = new { Text(Model.number(n) + " kg").font(C.bold(13)).foregroundColor(C.ink) }
        }
    }
}

/// The form on its own sheet, from "Kopiraj" on the coach's session screen.
struct CopySessionSheet: View {
    let source: JSON
    let date: Date
    let done: (JSON) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CopySessionForm(source: source, date: date, done: done)
                .sheetBar("Kopiraj trening") { dismiss() }
        }
    }
}

/// "Kopiraj stari trening" on a new, still empty session: pick a past one from the list, then the same form.
struct PickSessionSheet: View {
    /// The day being planned.
    let date: String
    let done: (JSON) -> Void
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            list
                .background(C.chalk)
                .sheetBar("Odaberi trening") { dismiss() }
                .navigationDestination(for: String.self) { id in
                    PickedSession(id: id, date: date, done: done)
                }
        }
    }

    /// Past sessions of the group the coach is looking at (as on TRENINZI), newest first.
    private var sessions: [JSON] {
        let gid = Groups.selected(store)
        let today = Fmt.today()
        return store.all(Store.sessions)
            .filter { $0.string("date") <= today && !$0["items"].list.isEmpty && Groups.forGroup(store, $0, gid) }
            .sorted { a, b in
                let da = a.string("date"), db = b.string("date")
                return da != db ? da > db : a.string("title") < b.string("title")
            }
    }

    private var list: some View {
        let all = sessions
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if all.isEmpty {
                    EmptyCard(title: "Nema treninga", text: "Još nema treninga za kopiranje.")
                }
                ForEach(all, id: \.idKey) { s in
                    NavigationLink(value: s.string("id")) { PickRow(session: s) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

/// "Kopiraj stari trening" at the top of a new, still empty session (the + DODAJ path).
struct CopyOldButton: View {
    /// The day being planned.
    let date: String
    let picked: (JSON) -> Void
    @State private var picking = false
    @State private var copied: JSON?

    var body: some View {
        GhostButton(title: "Kopiraj stari trening", color: C.blue) { picking = true }
            .sheet(isPresented: $picking, onDismiss: {
                // handed over once the sheet is gone: the editor then shows the copy and drops this button
                if let n = copied {
                    copied = nil
                    picked(n)
                }
            }) {
                PickSessionSheet(date: date) { n in
                    copied = n
                    picking = false
                }
            }
            .task {
                // screenshot mode: the list of past sessions open
                if Shot.name == "c-pick" {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    picking = true
                }
            }
    }
}

/// One past session in the list: title, day, what was in it.
struct PickRow: View {
    @ObservedObject var store = Store.shared
    let session: JSON

    var body: some View {
        let items = session["items"].list.filter { $0.isObject }.map { Model.title($0) }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        let groups = Groups.tag(store, session)
        Card(padding: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.string("title", "Trening").uppercased()).font(C.display(15)).foregroundColor(C.ink)
                Spacer(minLength: 8)
                Text(Fmt.niceRelative(session.string("date"))).font(C.bold(12)).foregroundColor(C.muted)
            }
            if !items.isEmpty {
                Text(items).font(C.text(13)).foregroundColor(C.muted).multilineTextAlignment(.leading).padding(.top, 4)
            }
            if !groups.isEmpty { Tag(text: groups, fg: C.blue, bg: C.blueSoft).padding(.top, 6) }
        }
        .contentShape(Rectangle())
    }
}

/// The form for the session picked from the list.
struct PickedSession: View {
    let id: String
    let date: String
    let done: (JSON) -> Void
    @ObservedObject var store = Store.shared

    var body: some View {
        if let s = store.doc(Store.sessions, id) {
            CopySessionForm(source: s, date: Fmt.date(date), done: done)
                .sheetBar("Kopiraj trening", close: nil)
        } else {
            VStack {
                EmptyCard(title: "Trening je obrisan", text: "").padding(16)
                Spacer()
            }
            .background(C.chalk)
        }
    }
}

extension View {
    /// The app's dark header on a sheet; "Odustani" on the sheet's first screen.
    func sheetBar(_ title: String, close: (() -> Void)?) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if close != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Odustani") { close?() }.foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(C.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

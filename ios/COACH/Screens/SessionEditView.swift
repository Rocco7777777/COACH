import SwiftUI

/// Coach builds a session: running blocks (dionice), runs in km, gym exercises and notes (SessionEditScreen.java).
struct SessionEditView: View {
    let sessionId: String?
    let date: String
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var s: JSON = .null
    @State private var dirty = false
    @State private var names: [String] = []
    @State private var askLeave = false
    @State private var pickDate = false
    @State private var perFor: PerPick?

    struct PerPick: Identifiable {
        let index: Int
        let free: [JSON]
        var id: Int { index }
    }

    var body: some View {
        ScrollView {
            if s.isObject {
                VStack(alignment: .leading, spacing: 12) {
                    if sessionId == nil && s["items"].list.isEmpty {
                        CopyOldButton(date: s.string("date")) { n in
                            // the copy is saved; the editor carries on with it, so the coach can still change it
                            s = n
                            dirty = false
                            Toast.shared.show("Kopirano na " + Fmt.nice(n.string("date")))
                        }
                    }
                    groupsCard
                    basics
                    ForEach(Array(s["items"].list.enumerated()), id: \.element.idKey) { i, _ in
                        ItemEditCard(s: $s, dirty: $dirty, index: i, names: names) { perFor = PerPick(index: i, free: $0) }
                    }
                    Text("DODAJ").font(C.display(15)).foregroundColor(C.ink).padding(.top, 10)
                    HStack(spacing: 8) {
                        addButton("Dionice", "run", C.coral, C.night)
                        addButton("Trčanje km", "gps", C.green, .white)
                    }
                    HStack(spacing: 8) {
                        addButton("Teretana", "gym", C.blueFill, .white)
                        addButton("Napomena", "note", C.card, C.ink)
                    }
                    PillButton(title: "Spremi trening") {
                        save()
                        Toast.shared.show("Trening spremljen")
                        dismiss()
                    }
                    .padding(.top, 14)
                }
                .padding(16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(C.chalk)
        .navigationTitle(sessionId == nil ? "Novi trening" : "Uredi trening")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { if dirty { askLeave = true } else { dismiss() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        Text("Natrag")
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .toolbarBackground(C.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .keyboardDone()
        .confirmationDialog("Spremiti promjene?", isPresented: $askLeave, titleVisibility: .visible) {
            Button("Spremi") { save(); dismiss() }
            Button("Odbaci", role: .destructive) { dirty = false; dismiss() }
            Button("Odustani", role: .cancel) {}
        }
        .confirmationDialog("Drugačije za koga?", isPresented: Binding(get: { perFor != nil }, set: { if !$0 { perFor = nil } }),
                            titleVisibility: .visible, presenting: perFor) { p in
            ForEach(p.free, id: \.idKey) { at in
                Button(Fmt.shortName(at.string("name"))) {
                    var per = s["items"][p.index]["per"]
                    if !per.isObject { per = .object() }
                    per[at.string("id")] = .object()
                    s["items"][p.index]["per"] = per
                    dirty = true
                }
            }
            Button("Zatvori", role: .cancel) {}
        } message: { _ in
            Text("Upiši samo ono što je drugačije. Prazno polje = kao u planu.")
        }
        .sheet(isPresented: $pickDate) { dateSheet }
        .onAppear(perform: load)
    }

    // MARK: data

    private func load() {
        if s.isObject { return }
        names = ExerciseNames.all(store)
        if let id = sessionId, let found = store.doc(Store.sessions, id) {
            s = found
        } else {
            var n: JSON = ["id": .str(Fmt.id()), "date": .str(date), "title": "", "items": .array()]
            // a new session is for the group the coach is looking at
            if Groups.all(store).count > 1 { n["groups"] = [.str(Groups.selected(store))] }
            s = n
        }
        if !s["items"].isArray { s["items"] = .array() }
    }

    private func save() {
        if s.string("title").trimmingCharacters(in: .whitespaces).isEmpty {
            let type = s["items"][0].string("type")
            s["title"] = .str(type == "gym" ? "Teretana" : type == "run" ? "Dionice" : "Trening")
        }
        // drop athletes with nothing typed, so "per" only holds real differences
        var items = s["items"].list
        for i in items.indices where items[i]["per"].isObject {
            var per = items[i]["per"]
            for k in per.keys where per[k].dict.values.allSatisfy({ $0.asString.trimmingCharacters(in: .whitespaces).isEmpty }) {
                per.remove(k)
            }
            if per.keys.isEmpty { items[i].remove("per") } else { items[i]["per"] = per }
        }
        s["items"] = .arr(items)
        Groups.tidy(store, &s)
        store.put(Store.sessions, s)
        dirty = false
    }

    private func text(_ key: String) -> Binding<String> {
        Binding(get: { s.string(key) }, set: { s[key] = .str($0); dirty = true })
    }

    // MARK: parts

    @ViewBuilder private var groupsCard: some View {
        let gs = Groups.all(store)
        if gs.count >= 2 {
            let on0 = Groups.ofSession(store, s)
            let on = on0.isEmpty ? gs.map { $0.string("id") } : on0
            Card {
                Label12("Za grupu")
                FlowLayout(spacing: 6) {
                    ForEach(gs, id: \.idKey) { g in
                        let gid = g.string("id")
                        let ticked = on.contains(gid)
                        Chip(title: (ticked ? "✓  " : "") + g.string("name"), on: ticked) { toggleGroup(gid, ticked, on, gs) }
                    }
                }
                .padding(.top, 6)
                Text(gs.count == 2 ? "Označi obje i isti trening ide objema grupama." : "Označi više grupa i isti trening ide svima njima.")
                    .font(C.text(12)).foregroundColor(C.muted).padding(.top, 6)
            }
        }
    }

    private func toggleGroup(_ gid: String, _ ticked: Bool, _ on: [String], _ gs: [JSON]) {
        if ticked && on.count == 1 {
            Toast.shared.show("Trening mora biti barem za jednu grupu")
            return
        }
        var next = on
        if ticked { next.removeAll { $0 == gid } } else { next.append(gid) }
        let arr = gs.map { $0.string("id") }.filter { next.contains($0) }
        // every group ticked = the whole team, also any group made later
        if arr.count == gs.count { s.remove("groups") } else { s["groups"] = .arr(arr.map { .str($0) }) }
        dirty = true
    }

    private var basics: some View {
        Card {
            HStack(spacing: 8) {
                Button { pickDate = true } label: {
                    Text("📅  " + Fmt.nice(s.string("date"))).font(C.bold(14)).foregroundColor(C.ink)
                        .padding(.horizontal, 12).frame(height: 46)
                        .background(Capsule().stroke(C.stone, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                TextField("Naziv, npr. Dionice", text: text("title")).input()
            }
            FlowLayout(spacing: 6) {
                ForEach(["Dionice", "Teretana", "Sprint", "Tempo", "Lagano trčanje"], id: \.self) { q in
                    Chip(title: q, on: s.string("title") == q) {
                        s["title"] = .str(q)
                        dirty = true
                    }
                }
            }
            .padding(.top, 8)
            TextField("Napomena za sve: zagrijavanje…", text: text("notes"), axis: .vertical)
                .lineLimit(1...6).padding(.vertical, 10).input()
                .padding(.top, 10)
        }
    }

    private var dateSheet: some View {
        let bind = Binding<Date>(get: { Fmt.date(s.string("date")) }, set: {
            s["date"] = .str(Fmt.iso($0))
            dirty = true
        })
        return VStack(spacing: 12) {
            DatePicker("Datum", selection: bind, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "hr_HR"))
                .tint(C.coral)
            PillButton(title: "Gotovo") { pickDate = false }
        }
        .padding(16)
        .presentationDetents([.medium, .large])
    }

    private func addButton(_ label: String, _ type: String, _ bg: Color, _ fg: Color) -> some View {
        Button {
            var it: JSON = ["id": .str(Fmt.id()), "type": .str(type)]
            switch type {
            case "run": it["distance"] = "400"; it["reps"] = "5"
            case "gps": it["km"] = "8"; it["pace"] = "4:30"
            case "gym": it["sets"] = "3"; it["reps"] = "8"
            default: break
            }
            var items = s["items"].list
            items.append(it)
            s["items"] = .arr(items)
            dirty = true
        } label: {
            Text("+ " + label.uppercased()).font(C.display(13)).foregroundColor(fg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 16).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(bg == C.card ? C.stone : bg, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// One item of the session being edited, with its "Drugačije za" rows.
struct ItemEditCard: View {
    @Binding var s: JSON
    @Binding var dirty: Bool
    let index: Int
    let names: [String]
    let pickAthlete: ([JSON]) -> Void
    @ObservedObject var store = Store.shared
    @FocusState private var nameFocus: Bool

    private var it: JSON { s["items"][index] }
    private var type: String { it.string("type") }

    private func f(_ key: String) -> Binding<String> {
        Binding(get: { s["items"][index].string(key) }, set: { s["items"][index][key] = .str($0); dirty = true })
    }

    private func set(_ key: String, _ v: String) {
        s["items"][index][key] = .str(v)
        dirty = true
    }

    var body: some View {
        Card {
            header
            switch type {
            case "run": runFields
            case "gps": gpsFields
            case "gym": gymFields
            default:
                Field(label: "Naslov") { TextField("npr. Zagrijavanje", text: f("name")).input() }.padding(.top, 12)
            }
            if !Model.perFields(type).isEmpty { PerSection(s: $s, dirty: $dirty, index: index, pickAthlete: pickAthlete) }
            TextField(type == "run" ? "Opis, npr. iz niskog starta" : type == "gps" ? "Opis, npr. ravnomjerno, zadnja 2 km brže" : "Opis / napomena",
                      text: f("note"), axis: .vertical)
                .lineLimit(1...5).padding(.vertical, 10).input()
                .padding(.top, 10)
        }
    }

    private var header: some View {
        let accent = type == "run" ? C.coral : type == "gym" ? C.blue : type == "gps" ? C.green : C.stone
        var head = type == "run" ? "Dionice" : type == "gym" ? "Teretana" : type == "gps" ? "Trčanje km" : "Napomena"
        let nm = it.string("name").trimmingCharacters(in: .whitespaces)
        if type != "run" && type != "gps" && !nm.isEmpty { head = nm }
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 4, height: 18)
            Text(head.uppercased()).font(C.display(16)).foregroundColor(C.ink).lineLimit(1)
            Spacer(minLength: 4)
            roundButton("arrow.up", bg: C.chalk, size: 38) { move(-1) }
            roundButton("arrow.down", bg: C.chalk, size: 38) { move(1) }
            roundButton("xmark", bg: C.chalk, size: 38) {
                var items = s["items"].list
                if index < items.count { items.remove(at: index) }
                s["items"] = .arr(items)
                dirty = true
            }
        }
    }

    private func move(_ dir: Int) {
        var items = s["items"].list
        let j = index + dir
        if j < 0 || j >= items.count { return }
        items.swapAt(index, j)
        s["items"] = .arr(items)
        dirty = true
    }

    @ViewBuilder private var runFields: some View {
        HStack(spacing: 12) {
            Field(label: "Dionica (m)") { TextField("400", text: f("distance")).keyboardType(.numberPad).input() }
            Field(label: "Ponavljanja") { TextField("5", text: f("reps")).keyboardType(.numberPad).input() }
        }
        .padding(.top, 12)
        FlowLayout(spacing: 6) {
            ForEach(["60", "100", "150", "200", "300", "400", "600", "800", "1000"], id: \.self) { d in
                Chip(title: d, on: it.string("distance") == d) { set("distance", d) }
            }
        }
        .padding(.top, 6)
        let m = Fmt.num(it.string("distance"))
        if m > 0 && m <= 200 {
            // hand-timed block start, flying and electronic times are different numbers: separate graphs
            Label12("Start").padding(.top, 10)
            FlowLayout(spacing: 6) {
                ForEach(Progress.starts.indices, id: \.self) { k in
                    let sv = Progress.starts[k]
                    Chip(title: Progress.startNames[k], on: it.string("start") == sv) { set("start", it.string("start") == sv ? "" : sv) }
                }
            }
            .padding(.top, 4)
        }
        HStack(alignment: .top, spacing: 12) {
            Field(label: "Prolaz (cilj)") {
                TimeFieldView(value: it.string("target"), hint: "", secondsOnly: false) { set("target", $0) }
            }
            Field(label: "Pauza") {
                TimeFieldView(value: it.string("rest"), hint: "", secondsOnly: false) { set("rest", $0) }
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder private var gpsFields: some View {
        HStack(alignment: .top, spacing: 12) {
            Field(label: "Kilometri") { TextField("8", text: f("km")).keyboardType(.decimalPad).input().frame(width: 90) }
            Field(label: "Tempo po km") {
                TimeFieldView(value: it.string("pace"), hint: "", secondsOnly: false) { set("pace", $0) }
            }
        }
        .padding(.top, 10)
        Text("Sportaš upiše koliko je otrčao i za koliko; tempo se izračuna sam.").font(C.text(11)).foregroundColor(C.muted).padding(.top, 4)
    }

    @ViewBuilder private var gymFields: some View {
        Field(label: "Vježba") {
            TextField("npr. Čučanj", text: f("name")).focused($nameFocus).input()
        }
        .padding(.top, 12)
        if nameFocus {
            let hits = ExerciseNames.match(names, it.string("name"), 4)
            if !hits.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(hits, id: \.self) { n in
                        Chip(title: n, on: false) {
                            set("name", n)
                            nameFocus = false
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        let hold = Model.hold(it)
        HStack(spacing: 8) {
            Chip(title: "Ponavljanja", on: !hold) {
                s["items"][index].remove("unit")
                dirty = true
            }
            Chip(title: "Sekunde (izometrija)", on: hold) { set("unit", "s") }
        }
        .padding(.top, 8)
        HStack(spacing: 6) {
            Field(label: "Serije") { TextField("3", text: f("sets")).keyboardType(.numberPad).input(center: true) }
            Field(label: hold ? "Sek." : "Ponav.") { TextField(hold ? "30" : "8", text: f("reps")).keyboardType(.numbersAndPunctuation).input(center: true) }
            Field(label: "Kg") { TextField("–", text: f("kg")).keyboardType(.decimalPad).input(center: true) }
            Field(label: "@ RPE") { TextField("8", text: f("rpe")).keyboardType(.decimalPad).input(center: true) }
        }
        .padding(.top, 10)
        Text("@8 = 2 ponavljanja u rezervi, @10 = do otkaza.").font(C.text(11)).foregroundColor(C.muted).padding(.top, 4)
    }
}

/// "Drugačije za": an athlete's own kg / reps / @ (gym), distance / reps / split (run) or km / pace (run in km).
/// An empty box shows the plan in grey and means "as planned"; only typed numbers are stored, in item.per[athleteId].
struct PerSection: View {
    @Binding var s: JSON
    @Binding var dirty: Bool
    let index: Int
    let pickAthlete: ([JSON]) -> Void
    @ObservedObject var store = Store.shared

    private var it: JSON { s["items"][index] }

    var body: some View {
        // the session's groups; someone moved out keeps their row so the numbers aren't lost
        var athletes = Groups.audience(store, s)
        let per = it["per"]
        for at in store.all(Store.athletes) where per.has(at.string("id")) && !athletes.contains(where: { $0.string("id") == at.string("id") }) {
            athletes.append(at)
        }
        let rows = athletes.filter { per[$0.string("id")].isObject }
        let free = athletes.filter { !per[$0.string("id")].isObject }
        return VStack(alignment: .leading, spacing: 6) {
            if !athletes.isEmpty {
                if !rows.isEmpty {
                    Rectangle().fill(C.stone).frame(height: 1).padding(.top, 10).padding(.bottom, 4)
                    Label12("Drugačije za")
                    ForEach(rows, id: \.idKey) { at in row(at) }
                }
                if !free.isEmpty {
                    Button { pickAthlete(free) } label: {
                        Text("+  Drugačije za sportaša").font(C.bold(14)).foregroundColor(C.blue).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func own(_ id: String, _ key: String) -> Binding<String> {
        Binding(get: { s["items"][index]["per"][id].string(key) }, set: { v in
            let t = v.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { s["items"][index]["per"][id].remove(key) } else { s["items"][index]["per"][id][key] = .str(t) }
            dirty = true
        })
    }

    private func box(_ id: String, _ key: String, _ kb: UIKeyboardType) -> some View {
        let plan = it.string(key)
        return TextField(plan.isEmpty ? "–" : plan, text: own(id, key))
            .keyboardType(kb)
            .font(.system(size: 16, weight: .bold)).foregroundColor(C.blue)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4).frame(minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 10).fill(C.field))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(C.stone, lineWidth: 1))
    }

    /// What an empty own box stands for: the plan, except a split under another distance (then no split).
    private func planFor(_ o: JSON, _ key: String) -> String {
        key == "target" && Model.otherDistance(it, o) ? "" : it.string(key)
    }

    private func remove(_ id: String) -> some View {
        roundButton("xmark", bg: C.chalk, size: 36) {
            s["items"][index]["per"].remove(id)
            dirty = true
        }
    }

    @ViewBuilder private func row(_ at: JSON) -> some View {
        let id = at.string("id")
        let o = it["per"][id]
        let name = Text(Fmt.shortName(at.string("name"))).font(C.bold(14)).foregroundColor(C.ink).lineLimit(1)
        switch it.string("type") {
        case "gym":
            HStack(spacing: 4) {
                name.frame(width: 64, alignment: .leading)
                box(id, "sets", .numberPad)
                box(id, "reps", .numbersAndPunctuation)
                box(id, "kg", .decimalPad)
                box(id, "rpe", .decimalPad)
                remove(id)
            }
        case "run":
            VStack(alignment: .leading, spacing: 4) {
                HStack { name; Spacer(); remove(id) }
                HStack(spacing: 4) {
                    box(id, "distance", .numberPad).frame(width: 64)
                    Text("m  ×").font(C.text(14)).foregroundColor(C.muted)
                    box(id, "reps", .numberPad).frame(width: 46)
                    let plan = planFor(o, "target")
                    TimeFieldView(value: o.string("target"), hint: plan, secondsOnly: Fmt.parseTime(plan) > 0 && Fmt.parseTime(plan) < 45,
                                  keepHintSeconds: true) { v in setOwn(id, "target", v) }
                        .id(id + "/" + plan)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack { name; Spacer(); remove(id) }
                HStack(spacing: 4) {
                    box(id, "km", .decimalPad).frame(width: 64)
                    Text("km").font(C.text(14)).foregroundColor(C.muted)
                    TimeFieldView(value: o.string("pace"), hint: planFor(o, "pace"), secondsOnly: false, keepHintSeconds: true) { v in setOwn(id, "pace", v) }
                    Text("/km").font(C.text(14)).foregroundColor(C.muted)
                }
            }
        }
    }

    private func setOwn(_ id: String, _ key: String, _ v: String) {
        if v.isEmpty { s["items"][index]["per"][id].remove(key) } else { s["items"][index]["per"][id][key] = .str(v) }
        dirty = true
    }
}

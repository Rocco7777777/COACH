import SwiftUI

// MARK: which exercises have a leaderboard

/// Coach: picks the exercises that get a leaderboard (BoardPick). Until one is switched off, every exercise has one.
struct BoardPickView: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        let all = BoardPick.candidates(store)
        let custom: Bool = BoardPick.custom(store)
        let on: Set<String> = custom ? BoardPick.on(store) : Set(all.map { $0.key })
        let shown: Int = all.filter { on.contains($0.key) }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                hero(shown, all.count)
                buttons
                if all.isEmpty {
                    EmptyCard(title: "Još nema vježbi", text: "Vježba se pojavi ovdje čim je netko iz tima upiše na treningu.").padding(.top, 6)
                }
                ForEach(all.indices, id: \.self) { i in
                    if i == 0 || all[i - 1].group != all[i].group { Label12(all[i].group).padding(.top, 10) }
                    row(all[i].key, all[i].name, all[i].n, on.contains(all[i].key))
                }
                Text(custom
                     ? "Nova vježba nema ljestvicu dok je ovdje ne uključiš. Discipline s natjecanja uvijek imaju svoju."
                     : "Sad svaka vježba ima ljestvicu, i svaka nova. Čim jednu isključiš, nova vježba čeka da je ovdje uključiš. Discipline s natjecanja uvijek imaju svoju.")
                    .font(C.text(12)).foregroundColor(C.muted).padding(.top, 10)
            }
            .padding(16)
        }
        .background(C.chalk)
        .navigationTitle("Ljestvice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func hero(_ shown: Int, _ all: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label12("Vježbe s ljestvicom", color: Color(hex: 0x8A9096))
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(shown)").font(C.display(40)).foregroundColor(.white)
                Text("od \(all)").font(C.display(18)).foregroundColor(C.coral)
            }
            Text("Sportaši se natječu samo u onome što ovdje uključiš.").font(C.text(12)).foregroundColor(C.mutedLight)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.carbon))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            GhostButton(title: "Uključi sve") { BoardPick.save(store, [], custom: false) }
            GhostButton(title: "Isključi sve") { BoardPick.save(store, [], custom: true) }
        }
        .padding(.top, 4)
    }

    private func row(_ key: String, _ name: String, _ n: Int, _ on: Bool) -> some View {
        let bind = Binding<Bool>(get: { on }, set: { v in toggle(key, v) })
        let who: String = n == 1 ? "1 sportaš, ljestvica treba barem dvoje" : "\(n) sportaša"
        return Toggle(isOn: bind) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(C.bold(15)).foregroundColor(C.ink)
                Text(who).font(C.text(12)).foregroundColor(C.muted)
            }
        }
        .tint(C.coral)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
    }

    private func toggle(_ key: String, _ v: Bool) {
        var keys: Set<String> = BoardPick.custom(store) ? BoardPick.on(store) : Set(BoardPick.candidates(store).map { $0.key })
        if v { keys.insert(key) } else { keys.remove(key) }
        BoardPick.save(store, keys, custom: true)
    }
}

// MARK: competitions

/// Who and what a new result is for; "" = picked in the sheet.
struct CompTarget: Identifiable {
    let id = UUID()
    var athlete = ""
    var discipline = ""
}

/// Coach: competition disciplines, who competes in what, and the results. Each discipline gets a leaderboard
/// and a season graph by itself.
struct CompsView: View {
    @ObservedObject var store = Store.shared
    @State private var adding = false
    @State private var result: CompTarget?
    @State private var renaming: JSON?
    @State private var deleting: JSON?
    @State private var removing: JSON?
    @State private var newName = ""

    // Small pieces: Xcode 26's type checker times out on one big body.
    var body: some View {
        let list = Comp.all(store)
        return dialogs(page(list))
    }

    private func page(_ list: [JSON]) -> some View {
        let team = Groups.byName(store.all(Store.athletes))
        let latest = Array(Comp.results(store).prefix(15))
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stavi svakom sportašu čime se bavi i upisuj rezultate s natjecanja. Svaka disciplina dobije svoju ljestvicu i graf sezone.")
                    .font(C.text(14)).foregroundColor(C.muted)
                if list.isEmpty {
                    EmptyCard(title: "Još nema disciplina", text: "Dodaj prvu, npr. 100 m ili skok u dalj, i označi tko se u njoj natječe.")
                }
                ForEach(list, id: \.idKey) { d in card(d, team) }
                newButton
                if !latest.isEmpty { results(latest) }
            }
            .padding(16)
        }
        .background(C.chalk)
        .navigationTitle("Natjecanja")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func card(_ d: JSON, _ team: [JSON]) -> some View {
        let did: String = d.string("id")
        let unit: String = d.string("unit", Comp.time)
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text(d.string("name").uppercased()).font(C.display(17)).foregroundColor(C.ink)
                Spacer()
                Text(Comp.unitName(unit)).font(C.text(12)).foregroundColor(C.muted)
            }
            Text(summary(did, unit)).font(C.text(13)).foregroundColor(C.muted).padding(.top, 2)
            Label12("Tko se natječe").padding(.top, 10)
            who(did, team).padding(.top, 6)
            actions(d).padding(.top, 10)
        }
    }

    private func summary(_ did: String, _ unit: String) -> String {
        let all: [JSON] = Comp.results(store, discipline: did)
        let n: Int = all.count
        guard let b = Comp.top(store, did) else { return "Još nema rezultata." }
        let name: String = Fmt.shortName(Comp.athleteName(store, b.string("a")))
        let word: String = n % 10 == 1 && n % 100 != 11 ? "rezultat" : "rezultata"
        let people: Int = Set(all.map { $0.string("a") }).count
        let alone: String = people < 2 ? "  ·  za ljestvicu treba rezultat još jednog sportaša" : ""
        return "Najbolje: " + name + " " + Comp.text(unit, b.double("v")) + "  ·  \(n) " + word + alone
    }

    @ViewBuilder
    private func who(_ did: String, _ team: [JSON]) -> some View {
        if team.isEmpty {
            Text("U timu još nema sportaša.").font(C.text(13)).foregroundColor(C.muted)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(team, id: \.idKey) { at in
                    let aid: String = at.string("id")
                    let on: Bool = Comp.does(store, aid, did)
                    Chip(title: Fmt.shortName(at.string("name")), on: on) { Comp.assign(store, aid, did, !on) }
                }
            }
        }
    }

    private func actions(_ d: JSON) -> some View {
        HStack(spacing: 16) {
            Button { result = CompTarget(athlete: "", discipline: d.string("id")) } label: {
                Text("+ REZULTAT").font(C.display(13)).tracking(0.8).foregroundColor(C.night)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(C.coral))
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Preimenuj") {
                newName = d.string("name")
                renaming = d
            }
            .font(C.bold(13)).foregroundColor(C.blue)
            Button("Obriši") { deleting = d }.font(C.bold(13)).foregroundColor(C.red)
        }
    }

    private var newButton: some View {
        Button { adding = true } label: {
            Text("+ NOVA DISCIPLINA").font(C.display(15)).tracking(0.9).foregroundColor(C.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().stroke(C.stone, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func results(_ latest: [JSON]) -> some View {
        Text("ZADNJI REZULTATI").font(C.display(15)).foregroundColor(C.ink).padding(.top, 14)
        Card {
            ForEach(latest.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(C.stone).frame(height: 1).padding(.vertical, 6) }
                CompResultRow(result: latest[i]) { removing = latest[i] }
            }
        }
    }

    private var renameShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
    private var deleteShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
    private var removeShown: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private func dialogs<V: View>(_ v: V) -> some View {
        let deleteTitle: String = "Obrisati disciplinu \(deleting?.string("name") ?? "")?"
        return v
            .sheet(isPresented: $adding) { NewDisciplineSheet(assignTo: "") { adding = false } }
            .sheet(item: $result) { t in CompResultSheet(target: t) { result = nil } }
            .alert("Preimenuj disciplinu", isPresented: renameShown, presenting: renaming) { d in
                TextField("Naziv", text: $newName)
                Button("Spremi") { rename(d.string("id")) }
                Button("Odustani", role: .cancel) {}
            }
            .alert(deleteTitle, isPresented: deleteShown, presenting: deleting) { d in
                Button("Obriši", role: .destructive) { Comp.delete(store, d.string("id")) }
                Button("Odustani", role: .cancel) {}
            } message: { _ in
                Text("Brišu se i svi njezini rezultati, ljestvica i graf. To se ne može vratiti.")
            }
            .alert("Obrisati rezultat?", isPresented: removeShown, presenting: removing) { r in
                Button("Obriši", role: .destructive) { Comp.deleteResult(store, r.string("a"), r.string("id")) }
                Button("Odustani", role: .cancel) {}
            }
    }

    private func rename(_ id: String) {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { Comp.rename(store, id, n) }
    }
}

/// One competition result: who and what, date and meet, the result, and ✕ to delete it.
struct CompResultRow: View {
    @ObservedObject var store = Store.shared
    let result: JSON
    var showAthlete = true
    let remove: () -> Void

    var body: some View {
        let d: JSON? = Comp.get(store, result.string("d"))
        let unit: String = d?.string("unit", Comp.time) ?? Comp.time
        let what: String = d?.string("name") ?? "Disciplina"
        let name: String = Fmt.shortName(Comp.athleteName(store, result.string("a")))
        let title: String = showAthlete ? name + "  ·  " + what : what
        let meet: String = result.string("meet")
        let sub: String = Comp.day(result.string("date")) + (meet.isEmpty ? "" : "  ·  " + meet)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(C.bold(14)).foregroundColor(C.ink).lineLimit(1)
                Text(sub).font(C.text(12)).foregroundColor(C.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Comp.text(unit, result.double("v"))).font(C.display(15)).foregroundColor(C.ink)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(C.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Coach: a new discipline, one of the usual ones or typed in.
struct NewDisciplineSheet: View {
    /// The athlete who gets it right away; "" = nobody yet.
    let assignTo: String
    let close: () -> Void
    @ObservedObject var store = Store.shared
    @State private var name = ""
    @State private var unit = Comp.time
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Field(label: "Naziv discipline") {
                        TextField("npr. 100 m", text: $name).input()
                    }
                    Label12("Česte discipline").padding(.top, 4)
                    presets
                    Label12("Što se mjeri").padding(.top, 4)
                    units
                    Text(hint).font(C.text(12)).foregroundColor(C.muted)
                    if !error.isEmpty { Text(error).font(C.bold(13)).foregroundColor(C.red) }
                    PillButton(title: "Dodaj disciplinu") { save() }.padding(.top, 8)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(C.chalk)
            .navigationTitle("Nova disciplina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zatvori") { close() }.foregroundColor(C.ink) }
            }
        }
    }

    private var presets: some View {
        let have: Set<String> = Set(Comp.all(store).map { $0.string("name").lowercased() })
        let free: [(String, String)] = Comp.presets.filter { !have.contains($0.0.lowercased()) }
        return FlowLayout(spacing: 6) {
            ForEach(free.indices, id: \.self) { i in
                Chip(title: free[i].0, on: name == free[i].0) {
                    name = free[i].0
                    unit = free[i].1
                }
            }
        }
    }

    private var units: some View {
        HStack(spacing: 6) {
            ForEach(Comp.units.indices, id: \.self) { i in
                Chip(title: Comp.unitNames[i], on: unit == Comp.units[i]) { unit = Comp.units[i] }
            }
        }
    }

    private var hint: String {
        if unit == Comp.time { return "Vrijeme: manje je bolje (trčanje, prepone, hodanje)." }
        if unit == Comp.length { return "Metri: više je bolje (skokovi i bacanja)." }
        return "Bodovi: više je bolje (višeboj)."
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { error = "Upiši naziv ili dodirni jednu od čestih disciplina."; return }
        let id: String = Comp.add(store, n, unit)
        if !assignTo.isEmpty { Comp.assign(store, assignTo, id, true) }
        close()
    }
}

/// Coach: one result from a competition, or a personal best from before (with the date it was set).
struct CompResultSheet: View {
    let target: CompTarget
    let close: () -> Void
    @ObservedObject var store = Store.shared
    @State private var athlete = ""
    @State private var discipline = ""
    @State private var date = Date()
    @State private var h = ""
    @State private var m = ""
    @State private var sec = ""
    @State private var number = ""
    @State private var meet = ""
    @State private var error = ""
    @State private var saved = 0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    athletePart
                    disciplinePart
                    valuePart
                    datePart
                    meetPart
                    if !error.isEmpty { Text(error).font(C.bold(13)).foregroundColor(C.red) }
                    PillButton(title: "Spremi") { if save() { close() } }.padding(.top, 4)
                    GhostButton(title: "Spremi i upiši još jedan") { save() }
                    if saved > 0 { Text("Spremljeno rezultata: \(saved)").font(C.bold(13)).foregroundColor(C.green) }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(C.chalk)
            .navigationTitle("Rezultat s natjecanja")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zatvori") { close() }.foregroundColor(C.ink) }
            }
            .keyboardDone()
        }
        .onAppear { load() }
    }

    private func load() {
        if loaded { return }
        loaded = true
        athlete = target.athlete
        discipline = target.discipline
        if discipline.isEmpty && !athlete.isEmpty, let first = Comp.of(store, athlete).first { discipline = first.string("id") }
        let all = Comp.all(store)
        if discipline.isEmpty && all.count == 1 { discipline = all[0].string("id") }
    }

    /// The team, whoever competes in the chosen discipline first.
    private var people: [JSON] {
        let all = Groups.byName(store.all(Store.athletes))
        if discipline.isEmpty { return all }
        let yes: [JSON] = all.filter { Comp.does(store, $0.string("id"), discipline) }
        let no: [JSON] = all.filter { !Comp.does(store, $0.string("id"), discipline) }
        return yes + no
    }

    /// Every discipline, the athlete's own first.
    private var disciplines: [JSON] {
        let all = Comp.all(store)
        if athlete.isEmpty { return all }
        let mine: Set<String> = Set(Comp.ids(store, athlete))
        let yes: [JSON] = all.filter { mine.contains($0.string("id")) }
        let no: [JSON] = all.filter { !mine.contains($0.string("id")) }
        return yes + no
    }

    @ViewBuilder private var athletePart: some View {
        if target.athlete.isEmpty {
            let team = people
            Field(label: "Sportaš") {
                FlowLayout(spacing: 6) {
                    ForEach(team, id: \.idKey) { at in
                        let aid: String = at.string("id")
                        Chip(title: Fmt.shortName(at.string("name")), on: athlete == aid) { athlete = aid }
                    }
                }
            }
        } else {
            Text(Comp.athleteName(store, target.athlete).uppercased()).font(C.display(20)).foregroundColor(C.ink)
        }
    }

    @ViewBuilder private var disciplinePart: some View {
        if target.discipline.isEmpty {
            let list = disciplines
            Field(label: "Disciplina") {
                FlowLayout(spacing: 6) {
                    ForEach(list, id: \.idKey) { d in
                        let did: String = d.string("id")
                        Chip(title: d.string("name"), on: discipline == did) { discipline = did }
                    }
                }
            }
        } else {
            Text((Comp.get(store, target.discipline)?.string("name") ?? "Disciplina").uppercased())
                .font(C.display(20)).foregroundColor(C.ink)
        }
    }

    private var unit: String { Comp.get(store, discipline)?.string("unit", Comp.time) ?? Comp.time }

    @ViewBuilder private var valuePart: some View {
        let u: String = unit
        if u == Comp.time {
            Field(label: "Vrijeme: sati, minute, sekunde") {
                HStack(spacing: 6) {
                    TextField("h", text: $h).keyboardType(.numberPad).input(center: true).frame(width: 54)
                    Text(":").font(C.display(20)).foregroundColor(C.ink)
                    TextField("min", text: $m).keyboardType(.numberPad).input(center: true).frame(width: 66)
                    Text(":").font(C.display(20)).foregroundColor(C.ink)
                    TextField("sek", text: $sec).keyboardType(.decimalPad).input(center: true).frame(width: 100)
                    Spacer(minLength: 0)
                }
            }
        } else if u == Comp.length {
            Field(label: "Metri") {
                TextField("npr. 7,45", text: $number).keyboardType(.decimalPad).input()
            }
        } else {
            Field(label: "Bodovi") {
                TextField("npr. 7256", text: $number).keyboardType(.numberPad).input()
            }
        }
        Text(preview(u)).font(C.bold(14)).foregroundColor(C.blue)
    }

    private var datePart: some View {
        Card {
            DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
                Text("Datum").font(C.bold(15)).foregroundColor(C.ink)
            }
            .environment(\.locale, Locale(identifier: "hr_HR"))
            .tint(C.coral)
        }
    }

    @ViewBuilder private var meetPart: some View {
        let recent: [(String, String)] = Comp.meets(store, 4)
        Field(label: "Natjecanje (ne mora)") {
            TextField("npr. Prvenstvo Hrvatske", text: $meet).input()
        }
        if !recent.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(recent.indices, id: \.self) { i in
                    Chip(title: recent[i].0, on: meet == recent[i].0) {
                        meet = recent[i].0
                        date = Fmt.date(recent[i].1)
                    }
                }
            }
        }
    }

    /// Seconds, metres or points as typed; nil when there's nothing usable.
    private func value(_ u: String) -> Double? {
        if u != Comp.time { return Comp.parse(number) }
        let hh: Double = Fmt.num(h)
        let mm: Double = Fmt.num(m)
        let ss: Double = Fmt.num(sec)
        let v: Double = hh * 3600 + mm * 60 + ss
        return v > 0 ? (v * 100).rounded() / 100 : nil
    }

    private func preview(_ u: String) -> String {
        if let v = value(u) { return "= " + Comp.text(u, v) }
        return u == Comp.time ? "Za sprint upiši samo sekunde, npr. 10,84." : "Upiši rezultat."
    }

    /// true when it was saved; the fields empty for the next one.
    @discardableResult
    private func save() -> Bool {
        if athlete.isEmpty { error = "Odaberi sportaša."; return false }
        guard let d = Comp.get(store, discipline) else { error = "Odaberi disciplinu."; return false }
        guard let v = value(d.string("unit", Comp.time)) else { error = "Upiši rezultat."; return false }
        Comp.addResult(store, athlete, discipline, Fmt.iso(date), v, meet)
        error = ""
        saved += 1
        h = ""
        m = ""
        sec = ""
        number = ""
        if target.athlete.isEmpty { athlete = "" }
        return true
    }
}

/// Coach, on one athlete's page: what they compete in, their graphs and results, and adding one.
struct CompSection: View {
    let athleteId: String
    @Binding var path: NavigationPath
    @ObservedObject var store = Store.shared
    @State private var result: CompTarget?
    @State private var adding = false
    @State private var removing: JSON?

    var body: some View {
        let all = Comp.all(store)
        let series = Comp.series(store, athleteId)
        let latest = Array(Comp.results(store, athlete: athleteId).prefix(5))
        return dialogs(VStack(alignment: .leading, spacing: 8) {
            Text("NATJECANJA").font(C.display(15)).foregroundColor(C.ink).padding(.top, 12)
            picker(all)
            ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                Button { path.append(CoachRoute.series(athleteId, s.key)) } label: { SeriesRow(series: s) }.buttonStyle(.plain)
            }
            if !all.isEmpty {
                PillButton(title: "+ Rezultat s natjecanja") { result = CompTarget(athlete: athleteId, discipline: "") }
            }
            if !latest.isEmpty { results(latest) }
        })
    }

    private func picker(_ all: [JSON]) -> some View {
        Card {
            Label12("Čime se bavi")
            FlowLayout(spacing: 6) {
                ForEach(all, id: \.idKey) { d in
                    let did: String = d.string("id")
                    let on: Bool = Comp.does(store, athleteId, did)
                    Chip(title: d.string("name"), on: on) { Comp.assign(store, athleteId, did, !on) }
                }
                Chip(title: "+ Disciplina", on: false) { adding = true }
            }
            .padding(.top, 8)
            if all.isEmpty {
                Text("Dodaj disciplinu u kojoj se natječe, npr. 100 m ili skok u dalj.")
                    .font(C.text(13)).foregroundColor(C.muted).padding(.top, 8)
            }
        }
    }

    private func results(_ latest: [JSON]) -> some View {
        Card {
            ForEach(latest.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(C.stone).frame(height: 1).padding(.vertical, 6) }
                CompResultRow(result: latest[i], showAthlete: false) { removing = latest[i] }
            }
        }
    }

    private var removeShown: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private func dialogs<V: View>(_ v: V) -> some View {
        v
            .sheet(item: $result) { t in CompResultSheet(target: t) { result = nil } }
            .sheet(isPresented: $adding) { NewDisciplineSheet(assignTo: athleteId) { adding = false } }
            .alert("Obrisati rezultat?", isPresented: removeShown, presenting: removing) { r in
                Button("Obriši", role: .destructive) { Comp.deleteResult(store, r.string("a"), r.string("id")) }
                Button("Odustani", role: .cancel) {}
            }
    }
}

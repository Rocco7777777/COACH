import SwiftUI

// MARK: one athlete

/// Coach: one athlete's season, attendance, progress, runs and the last two weeks of sleep, supplements and wellness.
struct AthleteDetailView: View {
    let athleteId: String
    @Binding var path: NavigationPath
    @ObservedObject var store = Store.shared
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let at = store.doc(Store.athletes, athleteId)
        let season = Model.season(store, athleteId)
        let series = Progress.build(store, athleteId)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StatTile(value: Fmt.n((season.km * 10).rounded() / 10), label: "km", bg: C.carbon, fg: .white)
                    StatTile(value: Fmt.n2((season.kg / 10).rounded() / 100), label: "tona", bg: C.coral, fg: C.carbon)
                    StatTile(value: "\(Int(season.n))", label: "treninga", bg: C.white, fg: C.carbon)
                }
                attendance
                Text("NAPREDAK PO VJEŽBI").font(C.display(15)).foregroundColor(C.carbon).padding(.top, 12)
                if series.isEmpty {
                    EmptyCard(title: "Još nema grafova", text: "Graf se pojavi čim upiše prvu vježbu ili dionicu.")
                }
                ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                    if i == 0 || series[i - 1].group != s.group { Label12(s.group).padding(.top, 6) }
                    Button { path.append(CoachRoute.series(athleteId, s.key)) } label: { SeriesRow(series: s) }.buttonStyle(.plain)
                }
                runs
                Text("ZADNJA 2 TJEDNA").font(C.display(15)).foregroundColor(C.carbon).padding(.top, 14)
                ForEach(0..<14, id: \.self) { i in DayCard(athleteId: athleteId, day: Fmt.addDays(Date(), -i)) }
                GhostButton(title: "Preimenuj") {
                    newName = at?.string("name") ?? ""
                    renaming = true
                }
                .padding(.top, 14)
            }
            .padding(16)
        }
        .background(C.chalk)
        .navigationTitle(at?.string("name") ?? "Sportaš")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Preimenuj", isPresented: $renaming) {
            TextField("Ime i prezime", text: $newName).textInputAutocapitalization(.words)
            Button("Spremi") { rename() }
            Button("Odustani", role: .cancel) {}
        }
    }

    private var attendance: some View {
        let today = Fmt.today()
        let m = Attendance.tally(store, athleteId, Attendance.from(30), today)
        let all = Attendance.tally(store, athleteId, nil, today)
        let g = Groups.name(store, Groups.of(store, athleteId))
        return Button {
            let gid = Groups.of(store, athleteId)
            if !gid.isEmpty { Groups.select(gid) }
            path.append(CoachRoute.attendance)
        } label: {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label12("Dolasci · 30 dana" + (g.isEmpty ? "" : " · " + g))
                        Text(m.total == 0 ? "Još nema treninga za brojanje."
                             : "\(m.yes) od \(m.total) treninga" + (all.total > m.total ? "  ·  ukupno \(all.yes)/\(all.total)" : ""))
                            .font(C.text(13)).foregroundColor(C.muted)
                    }
                    Spacer()
                    if m.pct >= 0 { Text("\(m.pct) %").font(C.display(22)).foregroundColor(Attendance.color(m.pct)) }
                }
                if all.total > 0 { AttendanceDots(tally: all).padding(.top, 8) }
            }
        }
        .buttonStyle(.plain)
    }

    /// Latest runs in km of this athlete.
    @ViewBuilder private var runs: some View {
        let list = latestRuns(6)
        if !list.isEmpty {
            Text("TRČANJA").font(C.display(15)).foregroundColor(C.carbon).padding(.top, 14)
            Card {
                ForEach(list.indices, id: \.self) { i in
                    let ses = list[i].0, it = list[i].1, run = list[i].2
                    let pace = run.double("s") / max(0.01, run.double("km"))
                    let d = Fmt.date(ses.string("date"))
                    if i > 0 { Rectangle().fill(C.stone).frame(height: 1).padding(.vertical, 6) }
                    VStack(alignment: .leading, spacing: 2) {
                        Label12(Fmt.dayShort(d) + " " + Fmt.dm(d) + "  ·  cilj " + Model.title(it) + (it.string("pace").isEmpty ? "" : " @ " + it.string("pace")))
                        Text(Model.runLine(run)).font(C.bold(14)).foregroundColor(C.pace(Model.paceLevel(pace, Fmt.parseTime(it.string("pace")))))
                    }
                }
            }
        }
    }

    private func latestRuns(_ max: Int) -> [(JSON, JSON, JSON)] {
        var out: [(JSON, JSON, JSON)] = []
        for r in store.where(Store.results, "athleteId", athleteId).sorted(by: { $0.string("date") > $1.string("date") }) {
            guard let ses = store.doc(Store.sessions, r.string("sessionId")) else { continue }
            for raw in ses["items"].list where raw.isObject && out.count < max {
                let it = Model.forAthlete(raw, athleteId)
                if it.string("type") != "gps" { continue }
                if let run = Model.run(r, it.string("id")) { out.append((ses, it, run)) }
            }
            if out.count >= max { break }
        }
        return out
    }

    private func rename() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return }
        Task { @MainActor in
            do { try await store.renameAthlete(athleteId, n) } catch { Toast.shared.show("Nije uspjelo: " + error.localizedDescription) }
        }
    }
}

/// One day of an athlete: sleep, supplements, vitamins, questionnaire.
struct DayCard: View {
    @ObservedObject var store = Store.shared
    let athleteId: String
    let day: Date

    var body: some View {
        let d = store.doc(Store.daily, Model.dailyId(athleteId, Fmt.iso(day)))
        let w = d?.bool("wellnessDone") ?? false
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text((Fmt.dayShort(day) + " " + Fmt.dm(day)).uppercased()).font(C.display(14)).foregroundColor(C.carbon)
                Spacer()
                Tag(text: w ? "Upitnik ✓" : "Upitnik –", fg: w ? .white : C.carbon, bg: w ? C.green : C.chalk)
            }
            if let d = d {
                Text(line(d)).font(C.text(13)).foregroundColor(C.muted)
                if w {
                    let f = CoachText.flags(d)
                    if !f.isEmpty { Text(f).font(C.bold(13)).foregroundColor(C.red).padding(.top, 2) }
                    Text(JournalTab.summary(d)).font(C.text(13)).foregroundColor(C.carbon).padding(.top, 2)
                }
            } else {
                Text("Ništa upisano").font(C.text(13)).foregroundColor(Color(hex: 0x9CA1A5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
    }

    private func line(_ d: JSON) -> String {
        var b = "San " + (d.has("sleep") ? Fmt.n(d.double("sleep")) + " h" : "–")
        b += "  ·  Protein " + Fmt.n(d.double("protein")) + " mj.  ·  Kreatin " + Fmt.n(d.double("creatine")) + " g"
        let v = d["vitamins"].list.map { $0.asString }
        if !v.isEmpty { b += "\n" + v.joined(separator: ", ") }
        return b
    }
}

// MARK: Tim

/// Coach: the team's join code, the invite to send, and who is in the team.
struct TeamView: View {
    @ObservedObject var store = Store.shared
    @State private var busy = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var askCode = false
    @State private var removing: JSON?

    var body: some View {
        let all = Groups.byName(store.all(Store.athletes))
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero
                Text("U TIMU (\(all.count))").font(C.display(15)).foregroundColor(C.carbon).padding(.top, 8)
                Card {
                    if all.isEmpty { Text("Još nitko. Pošalji poziv gore.").font(C.text(14)).foregroundColor(C.muted) }
                    ForEach(all.indices, id: \.self) { i in
                        if i > 0 { Rectangle().fill(C.stone).frame(height: 1).padding(.vertical, 6) }
                        HStack {
                            Text(all[i].string("name")).font(C.bold(15)).foregroundColor(C.carbon)
                            Spacer()
                            Button { if store.demo { Toast.shared.show("U demo verziji nitko ne izlazi iz tima.") } else { removing = all[i] } } label: {
                                Text("Makni").font(C.text(13)).foregroundColor(C.muted).padding(.vertical, 8).padding(.leading, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(C.chalk)
        .navigationTitle("Tim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Ime tima", isPresented: $renaming) {
            TextField("Ime tima", text: $newName).textInputAutocapitalization(.words)
            Button("Spremi") { renameTeam() }
            Button("Odustani", role: .cancel) {}
        }
        .alert("Novi kod?", isPresented: $askCode) {
            Button("Novi kod") { newCode() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Stari kod prestaje vrijediti. Tko je već u timu, ostaje u timu.")
        }
        .alert("Makni " + (removing?.string("name") ?? "") + "?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Makni", role: .destructive) { if let r = removing { remove(r) } }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Više neće vidjeti treninge tima. Vratiti se može s kodom tima.")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Team.name.uppercased()).font(C.display(20)).foregroundColor(.white)
                Spacer()
                roundButton("pencil", fg: C.mutedLight, bg: C.carbon2, size: 40) {
                    if store.demo { Toast.shared.show("U demo verziji tim se ne preimenuje."); return }
                    newName = Team.name
                    renaming = true
                }
            }
            Label12("Kod za pridruživanje", color: Color(hex: 0x8A9096)).padding(.top, 14)
            Text(Team.code.isEmpty ? "······" : Team.spaced(Team.code)).font(C.display(44)).tracking(3).foregroundColor(C.coral)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 2)
            Text("Sportaš ga upiše kod registracije (Novi račun, Sportaš) i odmah je u tvom timu.")
                .font(C.text(13)).foregroundColor(C.mutedLight).padding(.top, 6)
            ShareLink(item: Team.inviteText) {
                Text("POŠALJI POZIV").font(C.display(16)).foregroundColor(C.carbon)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(C.coral))
            }
            .padding(.top, 14)
            HStack(spacing: 8) {
                lightButton("Kopiraj kod") {
                    UIPasteboard.general.string = Team.code
                    Toast.shared.show("Kod kopiran")
                }
                lightButton(busy ? "…" : "Novi kod") {
                    if store.demo { Toast.shared.show("U demo verziji kod je izmišljen."); return }
                    askCode = true
                }
            }
            .padding(.top, 8)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.carbon))
    }

    private func lightButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(C.bold(15)).foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Capsule().stroke(Color(hex: 0x4A5056), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func renameTeam() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if n.count < 2 { return }
        Task { @MainActor in
            do { try await store.renameTeam(n) } catch { Toast.shared.show(error.localizedDescription) }
        }
    }

    private func newCode() {
        busy = true
        Task { @MainActor in
            do { try await store.newJoinCode() } catch { Toast.shared.show(error.localizedDescription) }
            busy = false
        }
    }

    private func remove(_ at: JSON) {
        Task { @MainActor in
            do { try await store.removeAthlete(at.string("id")) } catch { Toast.shared.show(error.localizedDescription) }
        }
    }
}

// MARK: Grupe

/// Coach: groups of the team. New athletes wait under "Novi, bez grupe"; a tap on a name moves it.
struct GroupsView: View {
    @ObservedObject var store = Store.shared
    @State private var creating = false
    @State private var newName = ""
    @State private var moving: JSON?
    @State private var renaming: JSON?
    @State private var deleting: JSON?

    var body: some View {
        let groups = Groups.all(store)
        let free = Groups.unassigned(store)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if groups.isEmpty {
                    EmptyCard(title: "Još nema grupa", text: "Napravi prvu grupu i svi sadašnji sportaši idu u nju. Zatim napravi drugu i prebaci one koji treniraju s njom. Svaka grupa ima svoje treninge, dolaske i ljestvice.")
                }
                if !free.isEmpty {
                    heading("Novi, bez grupe", "\(free.count)").padding(.top, 10)
                    ForEach(free, id: \.idKey) { at in
                        Card {
                            Text(at.string("name")).font(C.bold(16)).foregroundColor(C.carbon)
                            Text("Gdje trenira? Dok nije u grupi, vidi treninge svih grupa.").font(C.text(13)).foregroundColor(C.muted)
                            FlowLayout(spacing: 6) {
                                ForEach(groups, id: \.idKey) { g in
                                    Chip(title: g.string("name"), on: false) { Groups.assign(store, at.string("id"), g.string("id")) }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                ForEach(groups, id: \.idKey) { g in groupCard(g) }
                Button {
                    newName = ""
                    creating = true
                } label: {
                    Text("+ NOVA GRUPA").font(C.display(15)).tracking(0.9).foregroundColor(C.blue)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().stroke(C.stone, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                Text("Prije druge grupe neka svi s Androidom ažuriraju COACH na 2.5.0. Starije verzije ne znaju za grupe i pokazuju sve treninge.")
                    .font(C.text(12)).foregroundColor(C.muted).padding(.top, 6)
            }
            .padding(16)
        }
        .background(C.chalk)
        .navigationTitle("Grupe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Nova grupa", isPresented: $creating) {
            TextField("npr. Sprinteri", text: $newName).textInputAutocapitalization(.words)
            Button("Napravi") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { Groups.select(Groups.create(store, n)) }
            }
            Button("Odustani", role: .cancel) {}
        } message: {
            if groups.isEmpty { Text("Svi sadašnji sportaši idu u ovu grupu. Zatim napravi drugu i prebaci one koji treniraju s njom.") }
        }
        .alert("Preimenuj grupu", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Naziv grupe", text: $newName)
            Button("Spremi") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if let g = renaming, !n.isEmpty { Groups.rename(store, g.string("id"), n) }
            }
            Button("Odustani", role: .cancel) {}
        }
        .alert("Obrisati grupu " + (deleting?.string("name") ?? "") + "?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Obriši", role: .destructive) { if let g = deleting { Groups.delete(store, g.string("id")) } }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Sportaši iz nje idu pod \"bez grupe\", a njeni treninzi postaju treninzi cijelog tima. Rezultati ostaju.")
        }
        .confirmationDialog(moving?.string("name") ?? "", isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }),
                            titleVisibility: .visible, presenting: moving) { at in
            let now = Groups.of(store, at.string("id"))
            ForEach(groups, id: \.idKey) { g in
                Button((g.string("id") == now ? "✓ " : "") + g.string("name")) { Groups.assign(store, at.string("id"), g.string("id")) }
            }
            Button((now.isEmpty ? "✓ " : "") + "Bez grupe") { Groups.assign(store, at.string("id"), "") }
            Button("Zatvori", role: .cancel) {}
        }
    }

    private func heading(_ left: String, _ right: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(left.uppercased()).font(C.display(15)).foregroundColor(C.carbon)
            Spacer()
            Text(right).font(C.bold(13)).foregroundColor(C.muted)
        }
    }

    private func groupCard(_ g: JSON) -> some View {
        let members = Groups.members(store, g.string("id"))
        return VStack(alignment: .leading, spacing: 8) {
            heading(g.string("name"), "\(members.count) " + (members.count == 1 ? "sportaš" : "sportaša")).padding(.top, 12)
            Card {
                if members.isEmpty {
                    Text("Nitko još. Dodirni sportaša u drugoj grupi da ga prebaciš ovamo.").font(C.text(13)).foregroundColor(C.muted)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(members, id: \.idKey) { at in
                            Button { moving = at } label: {
                                HStack(spacing: 7) {
                                    Initials(name: at.string("name"), size: 30)
                                    Text(Fmt.shortName(at.string("name"))).font(C.bold(14)).foregroundColor(C.carbon)
                                }
                                .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
                                .background(Capsule().fill(C.chalk))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Dodirni sportaša da ga prebaciš u drugu grupu.").font(C.text(12)).foregroundColor(C.muted).padding(.top, 8)
                }
                HStack(spacing: 16) {
                    Spacer()
                    Button("Preimenuj") {
                        newName = g.string("name")
                        renaming = g
                    }
                    .font(C.bold(13)).foregroundColor(C.blue)
                    Button("Obriši") { deleting = g }.font(C.bold(13)).foregroundColor(C.red)
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: Dolasci

/// Coach: attendance of every athlete in the chosen group over 30 days, 90 days or everything.
struct AttendanceView: View {
    @Binding var path: NavigationPath
    @ObservedObject var store = Store.shared
    @State private var period = 0
    private let days = [30, 90, 0]
    private let names = ["30 dana", "90 dana", "Sve"]

    var body: some View {
        let gid = Groups.selected(store)
        let team = gid.isEmpty ? Groups.byName(store.all(Store.athletes)) : Groups.members(store, gid)
        // athletes in no group train with every group: listed under each, after the group
        let free = Groups.unassigned(store)
        let everyone = team + free
        let ts = Attendance.tallies(store, everyone, Attendance.from(days[period]), Fmt.today())
        let yes = ts.prefix(team.count).reduce(0) { $0 + $1.yes }
        let all = ts.prefix(team.count).reduce(0) { $0 + $1.total }
        VStack(spacing: 0) {
            GroupSwitcher(path: $path)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in Chip(title: names[i], on: i == period) { period = i } }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label12("Dolasci" + (gid.isEmpty ? "" : " · " + Groups.name(store, gid)) + " · " + names[period], color: Color(hex: 0x8A9096))
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(all == 0 ? "–" : "\(Int((Double(yes) * 100 / Double(all)).rounded())) %").font(C.display(40)).foregroundColor(.white)
                            Text("prosjek ekipe").font(C.text(14)).foregroundColor(Color(hex: 0x8A9096))
                        }
                        Text("Tko upiše rezultat, broji se da je došao. Ispravak: otvori trening i dodirni ime pod DOLAZAK.")
                            .font(C.text(12)).foregroundColor(C.mutedLight)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(C.carbon))
                    .padding(.top, 4)
                    if everyone.isEmpty {
                        EmptyCard(title: "Nema sportaša", text: gid.isEmpty ? "Pozovi ih kodom tima." : "U ovoj grupi još nema nikoga.").padding(.top, 4)
                    }
                    ForEach(everyone.indices, id: \.self) { i in
                        if i == team.count { Text("BEZ GRUPE").font(C.display(15)).foregroundColor(C.carbon).padding(.top, 10) }
                        row(everyone[i], ts[i])
                    }
                }
                .padding(16)
            }
        }
        .background(C.chalk)
        .navigationTitle("Dolasci")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func row(_ at: JSON, _ t: Attendance.Tally) -> some View {
        Button { path.append(CoachRoute.athlete(at.string("id"))) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(at.string("name")).font(C.bold(15)).foregroundColor(C.carbon)
                    Spacer()
                    if t.pct >= 0 {
                        Text("\(t.yes) / \(t.total)   ").font(C.text(13)).foregroundColor(C.muted)
                        Text("\(t.pct) %").font(C.display(18)).foregroundColor(Attendance.color(t.pct))
                    } else {
                        Text("još ništa").font(C.text(13)).foregroundColor(C.muted)
                    }
                }
                if t.total > 0 { AttendanceDots(tally: t) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Jutarnji upitnik

/// Coach composes the morning questionnaire (QuestionnaireEditScreen.java).
struct QuestionnaireEditView: View {
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var q: JSON = .null
    @State private var dirty = false
    @State private var optText: [String: String] = [:]
    @State private var askLeave = false
    private let types = ["scale", "yesno", "multi", "text"]
    private let typeNames = ["Ocjena 1–5", "Da / Ne", "Više izbora", "Tekst"]

    var body: some View {
        // until the coach changes something, follow what the server has (right after login that's still arriving)
        let shown = dirty || q.isObject ? q : Wellness.questionnaire(store)
        let qs = shown["questions"].list
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sportaši ga dobiju svako jutro. Kod ocjena neka 5 uvijek bude najbolje stanje, onda ti aplikacija crvenim označi loše dane.")
                    .font(C.text(14)).foregroundColor(C.muted)
                ForEach(qs.indices, id: \.self) { i in card(qs, i) }
                GhostButton(title: "+ Dodaj pitanje") {
                    begin()
                    var list = q["questions"].list
                    list.append(Model.scale("q_" + Fmt.id(), "", "Loše", "Odlično"))
                    q["questions"] = .arr(list)
                }
                .padding(.top, 4)
                PillButton(title: "Spremi upitnik") {
                    save()
                    Toast.shared.show("Upitnik spremljen")
                    dismiss()
                }
                GhostButton(title: "Vrati zadana pitanja") {
                    q = Model.defaultQuestionnaire()
                    optText = [:]
                    dirty = true
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(C.chalk)
        .navigationTitle("Jutarnji upitnik")
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
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog("Spremiti upitnik?", isPresented: $askLeave, titleVisibility: .visible) {
            Button("Spremi") { save(); dismiss() }
            Button("Odbaci", role: .destructive) { dirty = false; dismiss() }
            Button("Odustani", role: .cancel) {}
        }
    }

    /// First change: copy what's shown into the draft.
    private func begin() {
        if !dirty {
            q = Wellness.questionnaire(store)
            dirty = true
        }
        if !q["questions"].isArray { q["questions"] = .array() }
    }

    private func save() {
        begin()
        q["questions"] = .arr(q["questions"].list.filter { $0.isObject && !$0.string("text").trimmingCharacters(in: .whitespaces).isEmpty })
        q["id"] = "questionnaire"
        store.put(Store.config, q)
        dirty = false
    }

    private func f(_ i: Int, _ key: String) -> Binding<String> {
        Binding(get: { (dirty ? q : Wellness.questionnaire(store))["questions"][i].string(key) }, set: {
            begin()
            q["questions"][i][key] = .str($0)
        })
    }

    private func move(_ i: Int, _ dir: Int) {
        begin()
        var list = q["questions"].list
        let j = i + dir
        if j < 0 || j >= list.count { return }
        list.swapAt(i, j)
        q["questions"] = .arr(list)
    }

    private func card(_ qs: [JSON], _ i: Int) -> some View {
        let item = qs[i]
        let type = item.string("type")
        let qid = item.string("id")
        return Card {
            HStack(spacing: 6) {
                Text("PITANJE \(i + 1)").font(C.display(15)).foregroundColor(C.carbon)
                Spacer()
                roundButton("arrow.up", bg: C.chalk, size: 36) { move(i, -1) }
                roundButton("arrow.down", bg: C.chalk, size: 36) { move(i, 1) }
                roundButton("xmark", bg: C.chalk, size: 36) {
                    begin()
                    var list = q["questions"].list
                    if i < list.count { list.remove(at: i) }
                    q["questions"] = .arr(list)
                }
            }
            TextField("npr. Jesi li upaljen?", text: f(i, "text"), axis: .vertical).lineLimit(1...3).padding(.vertical, 10).input().padding(.top, 10)
            FlowLayout(spacing: 6) {
                ForEach(types.indices, id: \.self) { k in
                    Chip(title: typeNames[k], on: types[k] == type) {
                        begin()
                        q["questions"][i]["type"] = .str(types[k])
                        if types[k] == "multi" && !q["questions"][i]["options"].isArray { q["questions"][i]["options"] = .array() }
                    }
                }
            }
            .padding(.top, 4)
            if type == "scale" {
                HStack(spacing: 10) {
                    Field(label: "1 znači") { TextField("Loše", text: f(i, "low")).input() }
                    Field(label: "5 znači") { TextField("Odlično", text: f(i, "high")).input() }
                }
                .padding(.top, 12)
            } else if type == "multi" {
                Field(label: "Ponuđeno (odvoji zarezom)") {
                    TextField("Listovi, Leđa, Koljena", text: Binding(get: {
                        optText[qid] ?? item["options"].list.map { $0.asString }.joined(separator: ", ")
                    }, set: { v in
                        begin()
                        optText[qid] = v
                        let opts = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        q["questions"][i]["options"] = .arr(opts.map { .str($0) })
                    })).input()
                }
                .padding(.top, 12)
            }
            if i > 0 && qs[i - 1].string("type") == "yesno" {
                let on = item.bool("onlyIfYes")
                Chip(title: (on ? "✓ " : "") + "Prikaži samo ako je prethodno DA", on: on) {
                    begin()
                    q["questions"][i]["onlyIfYes"] = .bool(!on)
                }
                .padding(.top, 12)
            }
        }
    }
}

import SwiftUI

/// Coach view of one session: the plan, attendance and every athlete's entries (SessionCoachScreen.java).
struct SessionCoachView: View {
    let sessionId: String
    @Binding var path: NavigationPath
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copying = false
    @State private var copyDate = Date()
    @State private var askDelete = false

    private var session: JSON? { store.doc(Store.sessions, sessionId) }

    var body: some View {
        Group {
            if let s = session {
                content(s)
            } else {
                VStack {
                    EmptyCard(title: "Trening je obrisan", text: "").padding(16)
                    Spacer()
                }
            }
        }
        .background(C.chalk)
        .navigationTitle(session?.string("title", "Trening") ?? "Trening")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { path.append(CoachRoute.editSession(sessionId)) } label: {
                    Text("UREDI").font(C.bold(13)).foregroundColor(C.carbon)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(C.coral))
                }
            }
        }
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog("Obrisati trening?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Obriši", role: .destructive) { delete() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Brišu se i upisani rezultati sportaša za ovaj trening.")
        }
        .sheet(isPresented: $copying) { copySheet }
    }

    private func content(_ s: JSON) -> some View {
        let team = Groups.audience(store, s)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(Fmt.niceRelative(s.string("date"))).font(C.text(13)).foregroundColor(C.muted)
                PlanCard(session: s, team: team)
                PillButton(title: "✎  Zapisnik") { path.append(CoachRoute.logbook(sessionId)) }.padding(.top, 4)
                HStack(spacing: 8) {
                    GhostButton(title: "Kopiraj") {
                        copyDate = Fmt.addDays(Fmt.date(s.string("date")), 7)
                        copying = true
                    }
                    GhostButton(title: "Obriši", color: C.red) { askDelete = true }
                }
                if s.string("date") <= Fmt.today() && !team.isEmpty {
                    AttendanceCard(session: s, audience: team).padding(.top, 8)
                }
                Text("REZULTATI").font(C.display(15)).foregroundColor(C.carbon).padding(.top, 16)
                ForEach(team, id: \.idKey) { at in
                    ResultCard(session: s, athlete: at, result: store.doc(Store.results, Model.resultId(sessionId, at.string("id"))))
                }
            }
            .padding(16)
        }
    }

    private var copySheet: some View {
        VStack(spacing: 12) {
            Text("KOPIRAJ NA DAN").font(C.display(17)).foregroundColor(C.carbon)
            DatePicker("Datum", selection: $copyDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "hr_HR"))
                .tint(C.coral)
            PillButton(title: "Kopiraj") {
                copy()
                copying = false
            }
        }
        .padding(16)
        .presentationDetents([.large])
    }

    private func copy() {
        guard var n = session else { return }
        n["id"] = .str(Fmt.id())
        n["date"] = .str(Fmt.iso(copyDate))
        Groups.tidy(store, &n) // deleted groups dropped, all groups = whole team
        store.put(Store.sessions, n)
        Toast.shared.show("Kopirano na " + Fmt.nice(n.string("date")))
    }

    private func delete() {
        for r in store.where(Store.results, "sessionId", sessionId) { store.delete(Store.results, r.string("id")) }
        store.delete(Store.sessions, sessionId)
        Attendance.forget(store, sessionId)
        dismiss()
    }
}

/// The dark plan card: groups, notes, every item with its plan and the athletes' own numbers.
struct PlanCard: View {
    @ObservedObject var store = Store.shared
    let session: JSON
    let team: [JSON]

    var body: some View {
        let og = Groups.ofSession(store, session)
        var groups = og.isEmpty ? "" : Groups.tag(store, session)
        if groups.isEmpty && og.count == 1 { groups = Groups.name(store, og[0]) }
        return VStack(alignment: .leading, spacing: 10) {
            if !groups.isEmpty { Label12("Za: " + groups, color: Color(hex: 0x8A9096)) }
            if !session.string("notes").isEmpty {
                Text(session.string("notes")).font(C.text(14)).foregroundColor(C.mutedLight)
            }
            ForEach(session["items"].list.filter { $0.isObject }, id: \.idKey) { it in item(it) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.carbon))
    }

    private func item(_ it: JSON) -> some View {
        let type = it.string("type")
        let p = Model.plan(it)
        let owns = team.compactMap { at -> String? in
            let o = Model.ownText(it, at.string("id"))
            return o.isEmpty ? nil : Fmt.shortName(at.string("name")) + ":  " + o
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(Model.title(it).uppercased()).font(C.display(16))
                .foregroundColor(type == "run" ? C.coral : type == "gps" ? C.green : .white)
            if !p.isEmpty { Text(p).font(C.text(13)).foregroundColor(C.mutedLight) }
            ForEach(owns, id: \.self) { Text($0).font(C.bold(13)).foregroundColor(Color(hex: 0xFF8A80)) }
            if !it.string("note").isEmpty { Text(it.string("note")).font(C.text(13)).foregroundColor(Color(hex: 0x8A9096)) }
        }
    }
}

/// DOLAZAK: green = came, red = didn't. A logged result marks it by itself; a tap overrides, a long press undoes.
struct AttendanceCard: View {
    @ObservedObject var store = Store.shared
    let session: JSON
    let audience: [JSON]

    var body: some View {
        // whoever the session is for now, plus anyone it still counts for (a mark, or their group on that day)
        let all = Groups.byName(store.all(Store.athletes))
        let every = Attendance.forSession(store, session, all, Fmt.today())
        let ids = Set(audience.map { $0.string("id") })
        let rows = all.indices.filter { every[$0] != Attendance.unset || ids.contains(all[$0].string("id")) }.map { (all[$0], every[$0]) }
        let yes = rows.filter { $0.1 == Attendance.yes }.count
        let counted = rows.filter { $0.1 != Attendance.unset }.count
        return Card {
            HStack {
                Text("DOLAZAK").font(C.display(15)).foregroundColor(C.carbon)
                Spacer()
                Text("\(yes)/\(counted)").font(C.display(16)).foregroundColor(yes > 0 ? C.green : C.muted)
            }
            FlowLayout(spacing: 6) {
                ForEach(rows.indices, id: \.self) { i in chip(rows[i].0, rows[i].1) }
            }
            .padding(.top, 8)
            Text("Tko upiše rezultat, označen je sam. Dodir mijenja, dugi dodir vraća na automatski.")
                .font(C.text(12)).foregroundColor(C.muted).padding(.top, 8)
        }
    }

    private func chip(_ at: JSON, _ st: Int) -> some View {
        let aid = at.string("id"), sid = session.string("id")
        let fg: Color = st == Attendance.yes ? .white : st == Attendance.no ? C.red : C.carbon
        let border: Color = st == Attendance.yes ? C.green : st == Attendance.no ? C.red : C.stone
        return Text((st == Attendance.yes ? "✓  " : st == Attendance.no ? "✕  " : "") + Fmt.shortName(at.string("name")))
            .font(C.bold(14)).foregroundColor(fg)
            .padding(.horizontal, 12).frame(minHeight: 38)
            .background(Capsule().fill(st == Attendance.yes ? C.green : C.white))
            .overlay(Capsule().stroke(border, lineWidth: 1.2))
            .contentShape(Capsule())
            .onTapGesture { Attendance.set(store, sid, aid, st != Attendance.yes) }
            .onLongPressGesture {
                Attendance.set(store, sid, aid, nil)
                Toast.shared.show("Vraćeno na automatski")
            }
    }
}

/// One athlete's entries for the session; gym sets read like the plan: sets × reps · kg · @RPE.
struct ResultCard: View {
    let session: JSON
    let athlete: JSON
    let result: JSON?

    var body: some View {
        let t = Model.totals(session, result)
        let sum = (t.km > 0 ? Fmt.n2(t.km) + " km" : "") + (t.km > 0 && t.kg > 0 ? " · " : "") + (t.kg > 0 ? Fmt.n(t.kg) + " kg" : "")
        Card {
            HStack(alignment: .top) {
                Text(athlete.string("name")).font(C.bold(15)).foregroundColor(C.carbon)
                Spacer()
                if t.done > 0 {
                    Tag(text: sum.isEmpty ? "Upisano" : sum, fg: .white, bg: C.green)
                } else {
                    Tag(text: "Nije upisao", fg: C.carbon, bg: C.chalk)
                }
            }
            if let r = result {
                ForEach(session["items"].list.filter { $0.isObject }, id: \.idKey) { raw in
                    entry(Model.forAthlete(raw, athlete.string("id")), r)
                }
                if !r.string("comment").isEmpty {
                    Text("„" + r.string("comment") + "“").font(C.text(14)).foregroundColor(C.muted).padding(.top, 10)
                }
            }
        }
    }

    @ViewBuilder private func entry(_ it: JSON, _ r: JSON) -> some View {
        let en = Model.entries(r, it.string("id"))
        let type = it.string("type")
        if !en.isEmpty && type != "note" {
            switch type {
            case "gps":
                if let run = Model.run(r, it.string("id")) { gpsLine(it, run).padding(.top, 10) }
            case "run":
                runLine(it, en).padding(.top, 10)
            default:
                let lines = Model.setLines(it, en, rpe: !it.string("rpe").isEmpty)
                VStack(alignment: .leading, spacing: 2) {
                    Label12(Model.title(it))
                    if lines.isEmpty { Text("–").font(C.bold(14)).foregroundColor(C.carbon) }
                    ForEach(lines, id: \.self) { Text($0).font(C.bold(14)).foregroundColor(C.carbon) }
                }
                .padding(.top, 10)
            }
        }
    }

    private func runLine(_ it: JSON, _ en: [JSON]) -> some View {
        let target = Fmt.parseTime(it.string("target"))
        let times = en.map { $0.string("t") }
        let vals = times.map { Fmt.parseTime($0) }.filter { $0 > 0 }
        return VStack(alignment: .leading, spacing: 2) {
            Label12(Model.title(it) + (target > 0 ? "  ·  cilj " + it.string("target") : ""))
            Text(times.map { $0.isEmpty ? "–" : $0 }.joined(separator: "   ")).font(C.bold(en.count > 5 ? 13 : 14)).foregroundColor(C.carbon)
            if !vals.isEmpty {
                Text("prosjek " + Fmt.time(vals.reduce(0, +) / Double(vals.count))).font(C.text(12)).foregroundColor(C.muted)
            }
        }
    }

    private func gpsLine(_ it: JSON, _ run: JSON) -> some View {
        let km = run.double("km")
        let pace = km > 0.05 ? run.double("s") / km : -1
        let tp = Fmt.parseTime(it.string("pace"))
        let splits = run["splits"].list.map { Fmt.clock($0.doubleValue()) }
        return VStack(alignment: .leading, spacing: 2) {
            Label12("Trčanje " + Model.title(it) + (it.string("pace").isEmpty ? "" : "  ·  cilj " + it.string("pace") + "/km"))
            Text(Model.runLine(run)).font(C.bold(14)).foregroundColor(tp > 0 && pace > 0 ? C.pace(Model.paceLevel(pace, tp)) : C.carbon)
            if !splits.isEmpty { Text("po km: " + splits.joined(separator: "  ")).font(C.text(12)).foregroundColor(C.muted) }
        }
    }
}

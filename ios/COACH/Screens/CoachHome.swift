import SwiftUI

enum CoachRoute: Hashable {
    case session(String)
    case newSession(String)
    case editSession(String)
    case logbook(String)
    case logFor(String, String, String)
    case athlete(String)
    case series(String, String)
    case team, groups, attendance, questionnaire, settings, boards, comps
}

/// Coach app: TRENINZI / SPORTAŠI / LJESTVICE / VIŠE (CoachHome.java).
struct CoachHome: View {
    @ObservedObject var store = Store.shared
    @State private var tab = 0
    @State private var path = NavigationPath()
    @State private var week = Fmt.monday(Date())

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if tab < 3 { GroupSwitcher(path: $path) }
                Group {
                    switch tab {
                    case 0: CoachPlanTab(path: $path, week: $week)
                    case 1: AthletesTab(path: $path)
                    case 2: BoardTab(onEdit: { path.append(CoachRoute.boards) })
                    default: MoreTab(path: $path)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                TabBar(titles: ["TRENINZI", "SPORTAŠI", "LJESTVICE", "VIŠE"], selected: $tab)
            }
            .background(C.chalk)
            .toolbar {
                ToolbarItem(placement: .principal) { HeaderTitle() }
                if store.demo && !Shot.store {
                    ToolbarItem(placement: .navigationBarLeading) { DemoSwitch() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: CoachRoute.settings) {
                        Image(systemName: "gearshape.fill").foregroundColor(.white)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(C.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: CoachRoute.self) { r in CoachDestination(route: r, path: $path) }
        }
        .onAppear { applyShot() }
    }

    private func applyShot() {
        guard let s = Shot.name else { return }
        let today = store.all(Store.sessions).filter { $0.string("date") == Fmt.today() }.sorted { $0.string("title") < $1.string("title") }.first
        switch s {
        case "c-athletes": tab = 1
        case "c-board": tab = 2
        case "c-more": tab = 3
        case "c-session": if let t = today { path.append(CoachRoute.session(t.string("id"))) }
        case "c-log": if let t = today { path.append(CoachRoute.logbook(t.string("id"))) }
        case "c-edit":
            let gym = store.all(Store.sessions).filter { $0.string("date") >= Fmt.today() && $0["items"].list.contains { $0.string("type") == "gym" } }
                .sorted { $0.string("date") < $1.string("date") }.first
            if let g = gym { path.append(CoachRoute.editSession(g.string("id"))) }
        case "c-copy":
            // the last gym session where athletes have their own kg, so the form shows both kinds of rows
            let past = store.all(Store.sessions).filter { $0.string("date") < Fmt.today() }.sorted { $0.string("date") > $1.string("date") }
            let own = past.first { $0["items"].list.contains { $0["per"].isObject && SessionCopy.hasKg($0) } }
            if let g = own ?? past.first(where: { !SessionCopy.scalable($0).isEmpty }) { path.append(CoachRoute.session(g.string("id"))) }
        case "c-pick", "c-new": path.append(CoachRoute.newSession(Fmt.iso(Fmt.addDays(Date(), 1))))
        case "c-athlete":
            if let a = Groups.byName(store.all(Store.athletes)).first { tab = 1; path.append(CoachRoute.athlete(a.string("id"))) }
        case "c-boards": tab = 3; path.append(CoachRoute.boards)
        case "c-comps": tab = 3; path.append(CoachRoute.comps)
        case "c-comp":
            if let s = Comp.series(store, Demo.me).first { tab = 1; path.append(CoachRoute.series(Demo.me, s.key)) }
        case "c-settings": path.append(CoachRoute.settings)
        default: break
        }
    }
}

struct CoachDestination: View {
    let route: CoachRoute
    @Binding var path: NavigationPath

    var body: some View {
        switch route {
        case .session(let id): SessionCoachView(sessionId: id, path: $path)
        case .newSession(let date): SessionEditView(sessionId: nil, date: date)
        case .editSession(let id): SessionEditView(sessionId: id, date: Fmt.today())
        case .logbook(let id): LogbookView(sessionId: id, path: $path)
        case .logFor(let sid, let aid, let name): SessionDoView(sessionId: sid, athleteId: aid, athleteName: name)
        case .athlete(let id): AthleteDetailView(athleteId: id, path: $path)
        case .series(let aid, let key): SeriesView(athleteId: aid, key: key)
        case .team: TeamView()
        case .groups: GroupsView()
        case .attendance: AttendanceView(path: $path)
        case .questionnaire: QuestionnaireEditView()
        case .settings: SettingsView()
        case .boards: BoardPickView()
        case .comps: CompsView()
        }
    }
}

/// Demo only: look at the same made-up team as its coach or as an athlete.
struct DemoSwitch: View {
    var body: some View {
        Button { Demo.switchRole() } label: {
            Text(Prefs.isCoach ? "TRENER ⇄" : "SPORTAŠ ⇄").font(.system(size: 11, weight: .heavy)).foregroundColor(C.night)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(C.coral))
        }
    }
}

/// Coach's chosen group under the header: "● SPRINTERI 5 | SKAKAČI 3 | +". Nothing when there are no groups.
struct GroupSwitcher: View {
    @ObservedObject var store = Store.shared
    @Binding var path: NavigationPath

    var body: some View {
        let gs = Groups.all(store)
        if !gs.isEmpty {
            let sel = Groups.selected(store)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(gs, id: \.idKey) { g in
                        chip(g, on: g.string("id") == sel)
                    }
                    Button { path.append(CoachRoute.groups) } label: {
                        Text("+").font(C.bold(20)).foregroundColor(C.blue)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(C.card))
                            .overlay(Circle().stroke(C.stone, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            }
        }
    }

    private func chip(_ g: JSON, on: Bool) -> some View {
        Button {
            Groups.select(g.string("id"))
            store.changed()
        } label: {
            HStack(spacing: 6) {
                if on { Circle().fill(C.coral).frame(width: 8, height: 8) }
                Text(g.string("name").uppercased()).font(C.display(14)).foregroundColor(on ? C.onSel : C.ink)
                Text("\(Groups.members(store, g.string("id")).count)").font(C.bold(13)).foregroundColor(on ? C.onSelDim : C.muted)
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Capsule().fill(on ? C.sel : C.card))
            .overlay(Capsule().stroke(on ? C.sel : C.stone, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: TRENINZI

struct CoachPlanTab: View {
    @ObservedObject var store = Store.shared
    @Binding var path: NavigationPath
    @Binding var week: Date

    var body: some View {
        let gid = Groups.selected(store)
        let sessions = store.all(Store.sessions).filter { Groups.forGroup(store, $0, gid) }.sorted { $0.string("title") < $1.string("title") }
        VStack(spacing: 0) {
            weekNav
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let d = Fmt.addDays(week, i)
                        let iso = Fmt.iso(d)
                        dayHeader(d, iso).padding(.top, i == 0 ? 4 : 14)
                        let mine = sessions.filter { $0.string("date") == iso }
                        if mine.isEmpty {
                            Text("Odmor / nije upisano").font(C.text(13)).foregroundColor(Color(hex: 0x9CA1A5)).padding(.leading, 2)
                        }
                        ForEach(mine, id: \.idKey) { s in
                            CoachSessionCard(session: s, path: $path)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
    }

    private var weekNav: some View {
        let thisWeek = Fmt.iso(week) == Fmt.iso(Fmt.monday(Date()))
        return HStack {
            roundButton("chevron.left") { week = Fmt.addDays(week, -7) }
            Button { week = Fmt.monday(Date()) } label: {
                VStack(spacing: 1) {
                    Text(Fmt.dm(week) + " – " + Fmt.dm(Fmt.addDays(week, 6))).font(C.display(16)).foregroundColor(C.ink)
                    Label12(thisWeek ? "Ovaj tjedan" : "Tjedan")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            roundButton("chevron.right") { week = Fmt.addDays(week, 7) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func dayHeader(_ d: Date, _ iso: String) -> some View {
        HStack {
            Text((Fmt.dayLong(d) + " " + Fmt.dm(d)).uppercased()).font(C.display(14))
                .foregroundColor(iso == Fmt.today() ? C.coral : C.ink)
            Spacer()
            Button { path.append(CoachRoute.newSession(iso)) } label: {
                Text("+ DODAJ").font(C.bold(13)).foregroundColor(C.blue).padding(.vertical, 6).padding(.leading, 10)
            }
            .buttonStyle(.plain)
        }
    }
}

func roundButton(_ icon: String, fg: Color = C.ink, bg: Color = C.card, size: CGFloat = 44, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundColor(fg)
            .frame(width: size, height: size)
            .background(Circle().fill(bg))
            .overlay(Circle().stroke(bg == C.card ? C.stone : .clear, lineWidth: 1))
    }
    .buttonStyle(.plain)
}

struct CoachSessionCard: View {
    @ObservedObject var store = Store.shared
    let session: JSON
    @Binding var path: NavigationPath

    var body: some View {
        let team = Groups.audience(store, session)
        let done = team.filter { Attendance.logged(store, session, $0.string("id")) }.count
        let items = session["items"].list.filter { $0.isObject }.map { Model.title($0) }.joined(separator: "  ·  ")
        let groups = Groups.tag(store, session)
        let own = Model.ownNames(session, team)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(session.string("title", "Trening").uppercased()).font(C.display(15)).foregroundColor(C.ink)
                Spacer()
                Tag(text: "\(done)/\(team.count) upisalo", fg: done > 0 ? .white : C.ink, bg: done > 0 ? C.green : C.chalk)
            }
            if !items.isEmpty { Text(items).font(C.text(13)).foregroundColor(C.muted).padding(.top, 4) }
            if !groups.isEmpty { Tag(text: groups, fg: C.blue, bg: C.blueSoft).padding(.top, 6) }
            if !own.isEmpty { Text("Drugačije za: " + own).font(C.bold(12)).foregroundColor(C.own).padding(.top, 3) }
            if session.string("date") == Fmt.today() {
                HStack {
                    Spacer()
                    Button { path.append(CoachRoute.logbook(session.string("id"))) } label: {
                        Text("✎  ZAPISNIK").font(C.display(13)).tracking(0.8).foregroundColor(C.night)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(C.coral))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { path.append(CoachRoute.session(session.string("id"))) }
    }
}

// MARK: SPORTAŠI

struct AthletesTab: View {
    @ObservedObject var store = Store.shared
    @Binding var path: NavigationPath

    var body: some View {
        let free = Groups.unassigned(store)
        let gid = Groups.selected(store)
        let all = gid.isEmpty ? Groups.byName(store.all(Store.athletes)) : Groups.members(store, gid)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TeamStrip(path: $path)
                if !free.isEmpty {
                    MenuCard(title: "\(free.count) bez grupe", sub: "Stavi u grupu: " + free.map { Fmt.shortName($0.string("name")) }.joined(separator: ", "),
                             bg: C.coral, fg: C.night) { path.append(CoachRoute.groups) }
                }
                if !all.isEmpty { AttendanceRow(team: all) { path.append(CoachRoute.attendance) } }
                Text(("Danas, " + Fmt.dm(Date())).uppercased()).font(C.display(20)).foregroundColor(C.ink).padding(.top, 4)
                ForEach(all, id: \.idKey) { at in
                    AthleteTodayCard(athlete: at).onTapGesture { path.append(CoachRoute.athlete(at.string("id"))) }
                }
                if all.isEmpty {
                    if gid.isEmpty {
                        EmptyCard(title: "Još nema sportaša", text: "Pošalji im poziv gore. Kad se registriraju s kodom tima, pojavit će se ovdje.")
                    } else {
                        EmptyCard(title: "Grupa je prazna", text: "Pod VIŠE, Grupe prebaci sportaše u ovu grupu.")
                    }
                }
                if !free.isEmpty {
                    Text("BEZ GRUPE").font(C.display(15)).foregroundColor(C.ink).padding(.top, 10)
                    ForEach(free, id: \.idKey) { at in
                        AthleteTodayCard(athlete: at).onTapGesture { path.append(CoachRoute.athlete(at.string("id"))) }
                    }
                }
            }
            .padding(16)
        }
    }
}

/// Today's sleep, supplements and questionnaire flags of one athlete.
struct AthleteTodayCard: View {
    @ObservedObject var store = Store.shared
    let athlete: JSON

    var body: some View {
        let d = store.doc(Store.daily, Model.dailyId(athlete.string("id"), Fmt.today()))
        let w = d?.bool("wellnessDone") ?? false
        let flags = w ? CoachText.flags(d!) : ""
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Initials(name: athlete.string("name"), size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(athlete.string("name")).font(C.bold(15)).foregroundColor(C.ink)
                    Text(line(d)).font(C.text(12)).foregroundColor(C.muted)
                }
                Spacer(minLength: 4)
                Tag(text: w ? "Upitnik ✓" : "Upitnik –", fg: w ? .white : C.ink, bg: w ? C.green : C.coralSoft)
            }
            if !flags.isEmpty { Text(flags).font(C.bold(13)).foregroundColor(C.red) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func line(_ d: JSON?) -> String {
        guard let d = d else { return "Danas još ništa upisano" }
        return (d.has("sleep") ? "San " + Fmt.n(d.double("sleep")) + " h" : "San –")
            + "  ·  Protein " + Fmt.n(d.double("protein")) + "  ·  Kreatin " + Fmt.n(d.double("creatine")) + " g"
    }
}

struct Initials: View {
    let name: String
    var size: CGFloat = 36
    var body: some View {
        Text(Fmt.initials(name)).font(C.display(size * 0.4)).foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(C.carbon))
    }
}

enum CoachText {
    /// Red flags from a day's wellness: soreness and low scores.
    static func flags(_ d: JSON) -> String {
        let w = d["wellness"], labels = d["wellnessLabels"]
        var out: [String] = []
        for k in w.keys.sorted() {
            let label = labels.has(k) ? labels.string(k) : k
            switch w[k] {
            case .num(let v) where v <= 2 && v.rounded() == v:
                out.append(short(label) + " \(Int(v))/5")
            case .arr(let a) where !a.isEmpty:
                out.append("Upala: " + a.map { $0.asString }.joined(separator: ", "))
            default: break
            }
        }
        return out.joined(separator: "  ·  ")
    }

    private static func short(_ q: String) -> String {
        let s = q.replacingOccurrences(of: "?", with: "")
        return s.count > 26 ? String(s.prefix(25)) + "…" : s
    }
}

/// "DOLASCI · ZADNJIH 30 DANA  86 %"; opens the Dolasci list.
struct AttendanceRow: View {
    @ObservedObject var store = Store.shared
    let team: [JSON]
    let open: () -> Void

    var body: some View {
        let ts = Attendance.tallies(store, team, Attendance.from(30), Fmt.today())
        let yes = ts.reduce(0) { $0 + $1.yes }, all = ts.reduce(0) { $0 + $1.total }
        let pct = all == 0 ? -1 : Int((Double(yes) * 100 / Double(all)).rounded())
        Button(action: open) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label12("Dolasci · zadnjih 30 dana")
                    Text(all == 0 ? "Broji se kad upišu rezultate." : "\(yes) od \(all) treninga").font(C.text(13)).foregroundColor(C.muted)
                }
                Spacer()
                if pct >= 0 { Text("\(pct) %").font(C.display(22)).foregroundColor(Attendance.color(pct)) }
                Text("  →").font(C.display(20)).foregroundColor(C.ink)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Dark strip with the team code and an invite button; opens Tim.
struct TeamStrip: View {
    @Binding var path: NavigationPath

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label12("Kod tima", color: Color(hex: 0x8A9096))
                Text(Team.code.isEmpty ? "······" : Team.spaced(Team.code)).font(C.display(24)).foregroundColor(.white)
            }
            Spacer()
            ShareLink(item: Team.inviteText) {
                Text("POZOVI").font(C.display(14)).foregroundColor(C.night)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(Capsule().fill(C.coral))
            }
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.carbon))
        .contentShape(Rectangle())
        .onTapGesture { path.append(CoachRoute.team) }
    }
}

@MainActor
enum Team {
    static var code: String { Prefs.demoMode ? Demo.code : Prefs.joinCode }
    static var name: String { Prefs.demoMode ? Demo.teamName : (Prefs.teamName.isEmpty ? "Moj tim" : Prefs.teamName) }
    static func spaced(_ c: String) -> String { c.count == 6 ? String(c.prefix(3)) + " " + String(c.suffix(3)) : c }

    /// The message the coach sends in WhatsApp/Viber/SMS.
    static var inviteText: String {
        "Pozivam te u tim " + name + " u aplikaciji COACH.\n\n"
            + "1) Instaliraj COACH (Android: Google Play, iPhone: link ti šaljem posebno).\n"
            + "2) Otvori ga: Novi račun, Sportaš, kod tima: " + code
    }
}

// MARK: VIŠE

struct MoreTab: View {
    @ObservedObject var store = Store.shared
    @Binding var path: NavigationPath
    @State private var exportFile: ExportFile?
    @State private var exporting = false

    struct ExportFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MenuCard(title: "Tim i pozivnice", sub: "Kod tima, poziv za sportaše i tko je u timu.", bg: C.coral, fg: C.night) { path.append(CoachRoute.team) }
                MenuCard(title: "Grupe", sub: Groups.any(store) ? "Tko je u kojoj grupi. Novi sportaši čekaju ovdje."
                         : "Više grupa sportaša: svaka svoji treninzi, dolasci i ljestvice.", bg: C.card, fg: C.ink) { path.append(CoachRoute.groups) }
                MenuCard(title: "Natjecanja", sub: "Čime se tko bavi i rezultati s natjecanja. Svaka disciplina ima svoju ljestvicu i graf sezone.",
                         bg: C.card, fg: C.ink) { path.append(CoachRoute.comps) }
                MenuCard(title: "Ljestvice", sub: BoardPick.custom(store) ? "Ljestvicu imaju samo vježbe koje si odabrao. Promijeni odabir."
                         : "Odaberi koje vježbe imaju ljestvicu. Sad je ima svaka.", bg: C.card, fg: C.ink) { path.append(CoachRoute.boards) }
                MenuCard(title: "Dolasci", sub: "Tko je koliko puta došao na trening: 30 dana, 90 dana ili sve.", bg: C.card, fg: C.ink) { path.append(CoachRoute.attendance) }
                MenuCard(title: "Jutarnji upitnik", sub: "Sastavi pitanja koja sportaši dobivaju svako jutro.", bg: C.card, fg: C.ink) { path.append(CoachRoute.questionnaire) }
                MenuCard(title: exporting ? "Izrađujem Excel…" : "Izvoz u Excel", sub: "Svaki sportaš svoja kartica: progresija po vježbi, prolazi, km i tone za sezonu.",
                         bg: C.carbon, fg: .white) { export() }
            }
            .padding(16)
        }
        .sheet(item: $exportFile) { f in ShareSheet(items: [f.url]) }
    }

    private func export() {
        if exporting { return }
        exporting = true
        Task { @MainActor in
            do {
                exportFile = ExportFile(url: try Export.file(store))
            } catch {
                Toast.shared.show("Greška: " + error.localizedDescription)
            }
            exporting = false
        }
    }
}

struct MenuCard: View {
    let title: String
    let sub: String
    let bg: Color
    let fg: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title.uppercased()).font(C.display(16)).foregroundColor(fg).multilineTextAlignment(.leading)
                    Spacer()
                    Text("→").font(C.display(22)).foregroundColor(fg == .white ? C.coral : fg)
                }
                Text(sub).font(C.text(13)).foregroundColor(fg == .white ? C.mutedLight : (bg == C.coral ? C.night : C.muted))
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(bg == C.card ? C.stone : bg, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

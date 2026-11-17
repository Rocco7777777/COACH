import SwiftUI

enum Route: Hashable {
    case session(String)
    case series(String)
    case settings
}

/// Athlete app: TRENING / DNEVNIK / NAPREDAK / LJESTVICE.
struct AthleteHome: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var nav = Nav.shared
    @State private var tab = 0
    @State private var path = NavigationPath()
    @State private var wellness = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case 0: TrainingTab(path: $path, openWellness: { wellness = true })
                    case 1: JournalTab(openWellness: { wellness = true })
                    case 2: ProgressTab(path: $path)
                    default: BoardTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                TabBar(titles: ["TRENING", "DNEVNIK", "NAPREDAK", "LJESTVICE"], selected: $tab)
            }
            .background(C.chalk)
            .toolbar {
                ToolbarItem(placement: .principal) { HeaderTitle() }
                if store.demo && !Shot.store {
                    ToolbarItem(placement: .navigationBarLeading) { DemoSwitch() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Image(systemName: "gearshape.fill").foregroundColor(.white)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(C.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .session(let id): SessionDoView(sessionId: id)
                case .series(let key): SeriesView(athleteId: Prefs.athleteId, key: key)
                case .settings: SettingsView()
                }
            }
        }
        .sheet(isPresented: $wellness) {
            WellnessView(date: Fmt.today()) { wellness = false }
        }
        .onAppear {
            applyShot()
            maybeWellness()
        }
        .onChange(of: nav.openWellness) { v in
            if v {
                wellness = true
                nav.openWellness = false
            }
        }
    }

    /// Morning questionnaire opens by itself until it's filled in for today (not in the demo).
    private func maybeWellness() {
        if store.demo || Shot.name != nil { return }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 4 && !Wellness.done(store, Prefs.athleteId, Fmt.today()) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { wellness = true }
        }
    }

    private func applyShot() {
        guard let s = Shot.name else { return }
        switch s {
        case "journal": tab = 1
        case "progress": tab = 2
        case "board": tab = 3
        case "wellness": wellness = true
        case "settings": path.append(Route.settings)
        case "session", "gym", "run":
            let mine = Groups.visible(store, Prefs.athleteId, store.all(Store.sessions))
            let want = s == "gym" ? "gym" : s == "run" ? "run" : ""
            let today = Fmt.today()
            let pick = mine.filter { want.isEmpty ? $0.string("date") == today : ($0.string("date") <= today && $0["items"].list.contains { $0.string("type") == want }) }
                .sorted { $0.string("date") > $1.string("date") }.first
            if let p = pick { path.append(Route.session(p.string("id"))) }
        case "track":
            // the latest session with reps that already has my splits
            let me = Prefs.athleteId
            let today = Fmt.today()
            let past = Groups.visible(store, me, store.all(Store.sessions)).filter { $0.string("date") < today }
            let pick = past.filter { ses in
                ses["items"].list.contains { $0.string("type") == "run" } && store.doc(Store.results, Model.resultId(ses.string("id"), me)) != nil
            }
            .sorted { $0.string("date") > $1.string("date") }.first
            if let p = pick { path.append(Route.session(p.string("id"))) }
        case "series":
            let all = Progress.build(store, Prefs.athleteId)
            if let first = all.first(where: { $0.kind == Progress.gym }) ?? all.first { tab = 2; path.append(Route.series(first.key)) }
        case "comp":
            if let first = Progress.build(store, Prefs.athleteId).first(where: { $0.kind == Progress.comp }) {
                tab = 2
                path.append(Route.series(first.key))
            }
        default: break
        }
    }
}

struct HeaderTitle: View {
    var body: some View {
        HStack(spacing: 8) {
            TrackLogo(size: 18)
            Text("COACH").font(C.display(19)).foregroundColor(.white)
            if Prefs.demoMode && !Shot.store {
                Tag(text: "DEMO", fg: C.night, bg: C.coral)
            } else if Prefs.isCoach {
                Tag(text: "TRENER", fg: C.night, bg: C.coral)
            }
        }
    }
}

struct TabBar: View {
    let titles: [String]
    @Binding var selected: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                Button {
                    selected = i
                } label: {
                    VStack(spacing: 6) {
                        Capsule().fill(selected == i ? C.coral : .clear).frame(width: 28, height: 4)
                        Text(titles[i]).font(C.display(11)).foregroundColor(selected == i ? C.ink : C.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
        .background(C.card.ignoresSafeArea(edges: .bottom))
        .overlay(Rectangle().fill(C.stone).frame(height: 1), alignment: .top)
    }
}

/// Horizontal strip of days with a dot where something is planned or logged.
struct DateStrip: View {
    @Binding var day: String
    let from: Int
    let count: Int
    let marked: Set<String>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { i in
                        let d = Fmt.addDays(Date(), from + i)
                        let iso = Fmt.iso(d)
                        let on = iso == day
                        let isToday = iso == Fmt.today()
                        Button { day = iso } label: {
                            VStack(spacing: 3) {
                                Text(Fmt.dayShort(d).uppercased()).font(.system(size: 10, weight: .bold)).foregroundColor(on ? C.onSelDim : C.muted)
                                Text("\(Fmt.cal.component(.day, from: d))").font(C.display(18)).foregroundColor(on ? C.onSel : C.ink)
                                Circle().fill(marked.contains(iso) ? (on ? C.coral : C.coral) : .clear).frame(width: 5, height: 5)
                            }
                            .frame(width: 44, height: 62)
                            .background(RoundedRectangle(cornerRadius: 12).fill(on ? C.sel : C.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isToday && !on ? C.coral : (on ? C.sel : C.stone), lineWidth: isToday && !on ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .id(iso)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo(day, anchor: .center) }
        }
        .background(C.chalk)
    }
}

// MARK: TRENING

struct TrainingTab: View {
    @ObservedObject var store = Store.shared
    @Binding var path: NavigationPath
    let openWellness: () -> Void
    @State private var day = Fmt.today()

    private var me: String { Prefs.athleteId }

    var body: some View {
        let sessions = Groups.visible(store, me, store.all(Store.sessions))
        let today = sessions.filter { $0.string("date") == day }.sorted { $0.string("title") < $1.string("title") }
        VStack(spacing: 0) {
            DateStrip(day: $day, from: -14, count: 35, marked: Set(sessions.map { $0.string("date") }))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bok \(Fmt.firstName(Prefs.name)),").font(C.text(13)).foregroundColor(C.muted)
                        Text(Fmt.niceRelative(day).uppercased()).font(C.display(22)).foregroundColor(C.ink)
                    }
                    WeekCard(sessions: sessions)
                    if day == Fmt.today() && !Wellness.done(store, me, Fmt.today()) {
                        Button(action: openWellness) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("JUTARNJI UPITNIK").font(C.display(15)).foregroundColor(C.night)
                                    Text("30 sekundi. San, upala, raspoloženje.").font(C.text(12)).foregroundColor(C.night)
                                }
                                Spacer()
                                Text("→").font(C.display(24)).foregroundColor(C.night)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(C.coral))
                        }
                        .buttonStyle(.plain)
                    }
                    if today.isEmpty {
                        EmptyCard(title: "Nema treninga", text: "Trener još nije upisao trening za ovaj dan.")
                    }
                    ForEach(today, id: \.idKey) { s in
                        Button { path.append(Route.session(s.string("id"))) } label: { SessionCard(session: s) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .refreshable { await store.sync() }
        }
    }
}

extension JSON {
    /// For ForEach over docs.
    var idKey: String { string("id") }
}

/// "This week": one lap of the track per planned session done.
struct WeekCard: View {
    @ObservedObject var store = Store.shared
    let sessions: [JSON]

    var body: some View {
        let mon = Fmt.iso(Fmt.monday(Date())), sun = Fmt.iso(Fmt.addDays(Fmt.monday(Date()), 6))
        var planned = 0, done = 0
        var km = 0.0, kg = 0.0
        for s in sessions where s.string("date") >= mon && s.string("date") <= sun {
            planned += 1
            let t = Model.totals(s, store.doc(Store.results, Model.resultId(s.string("id"), Prefs.athleteId)))
            if t.done > 0 { done += 1 }
            km += t.km
            kg += t.kg
        }
        let sub = planned == 0 ? "Još nema treninga ovaj tjedan"
            : done == planned ? "Sve odrađeno. Svaka čast!"
            : "\(planned - done)" + (planned - done == 1 ? " trening do kraja tjedna" : " treninga do kraja tjedna")
        return HStack(spacing: 14) {
            TrackProgress(progress: planned == 0 ? 0 : Double(done) / Double(planned))
                .frame(width: 50, height: 68)
            VStack(alignment: .leading, spacing: 3) {
                Label12("Ovaj tjedan", color: C.mutedLight)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("\(done)").font(C.display(34)).foregroundColor(.white)
                    Text(" / \(planned)").font(C.display(18)).foregroundColor(C.coral)
                }
                Text(sub).font(C.text(12)).foregroundColor(C.mutedLight)
                if km > 0 || kg > 0 {
                    Text([km > 0 ? Fmt.n2(km) + " km" : "", kg > 0 ? Fmt.n(kg / 1000) + " t" : ""].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(C.bold(12)).foregroundColor(C.coral)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(C.carbon))
    }
}

/// A running track that fills with coral as the week's sessions get done.
struct TrackProgress: View {
    let progress: Double
    @State private var shown = 0.0

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let inset = CGFloat(i) * 7
                    let shape = RoundedRectangle(cornerRadius: (w - inset * 2) / 2)
                    shape.stroke(C.carbon2, lineWidth: 4)
                        .frame(width: w - inset * 2, height: h - inset * 2)
                    shape.trim(from: 0, to: shown)
                        .stroke(C.coral, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: w - inset * 2, height: h - inset * 2)
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.25)) { shown = progress } }
        .onChange(of: progress) { p in withAnimation(.easeOut(duration: 0.6)) { shown = p } }
    }
}

struct SessionCard: View {
    @ObservedObject var store = Store.shared
    let session: JSON

    var body: some View {
        let me = Prefs.athleteId
        let t = Model.totals(session, store.doc(Store.results, Model.resultId(session.string("id"), me)))
        Card {
            HStack {
                Text(session.string("title", "Trening").uppercased()).font(C.display(17)).foregroundColor(C.ink)
                Spacer()
                if t.done > 0 { Tag(text: "Upisano ✓", fg: .white, bg: C.green) } else { Tag(text: "Za upisati", fg: C.ink, bg: C.coralSoft) }
            }
            ForEach(Array(session["items"].list.enumerated()), id: \.offset) { i, raw in
                let it = Model.forAthlete(raw, me)
                let mine = Model.own(it, me) != nil
                HStack(spacing: 10) {
                    Circle().fill(dotColor(it.string("type"))).frame(width: 8, height: 8)
                    Text(Model.title(it)).font(C.bold(14)).foregroundColor(mine ? C.own : C.ink)
                    Text(Model.plan(it)).font(C.text(12)).foregroundColor(mine ? C.own : C.muted).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.top, i == 0 ? 10 : 6)
            }
            if !session.string("notes").isEmpty {
                Text(session.string("notes")).font(C.text(13)).foregroundColor(C.muted).padding(.top, 10)
            }
            if t.done > 0 {
                let sum = [t.km > 0 ? Fmt.n2(t.km) + " km" : "", t.kg > 0 ? Fmt.n(t.kg) + " kg ukupno" : ""].filter { !$0.isEmpty }.joined(separator: "  ·  ")
                if !sum.isEmpty { Text(sum).font(C.bold(13)).foregroundColor(C.green).padding(.top, 10) }
            }
        }
    }

    func dotColor(_ type: String) -> Color {
        switch type {
        case "run": return C.coral
        case "gym": return C.blue
        case "gps": return C.green
        default: return C.stone
        }
    }
}

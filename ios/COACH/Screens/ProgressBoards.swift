import SwiftUI
import Charts

// MARK: NAPREDAK

struct ProgressTab: View {
    @ObservedObject var store = Store.shared
    @Binding var path: NavigationPath

    var body: some View {
        let me = Prefs.athleteId
        let season = seasonTotals(me)
        let all = Progress.build(store, me)
        let comps: [Progress.Series] = all.filter { $0.kind == Progress.comp }
        let series: [Progress.Series] = all.filter { $0.kind != Progress.comp }
        // disciplines the coach gave me that have no result yet
        let waiting: [JSON] = Comp.of(store, me).filter { d in !comps.contains { $0.key == Comp.key(d.string("id")) } }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("SEZONA").font(C.display(22)).foregroundColor(C.ink)
                HStack(spacing: 12) {
                    StatTile(value: Fmt.n((season.km * 10).rounded() / 10), label: "km pretrčano", bg: C.carbon, fg: .white)
                    StatTile(value: Fmt.n2((season.kg / 10).rounded() / 100), label: "tona podignuto", bg: C.coral, fg: C.night)
                }
                HStack(spacing: 12) {
                    StatTile(value: "\(Int(season.n))", label: "treninga", bg: C.card, fg: C.ink)
                    StatTile(value: sleep7(me), label: "san, zadnjih 7 dana", bg: C.blueFill, fg: .white)
                }
                if !comps.isEmpty || !waiting.isEmpty { mine(comps, waiting) }
                Text("PO VJEŽBI").font(C.display(15)).foregroundColor(C.ink).padding(.top, 14)
                if series.isEmpty {
                    EmptyCard(title: "Još nema grafova", text: "Graf se pojavi čim upišeš prvu vježbu ili dionicu.")
                }
                ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                    if i == 0 || series[i - 1].group != s.group {
                        Label12(s.group).padding(.top, 8)
                    }
                    Button { path.append(Route.series(s.key)) } label: { SeriesRow(series: s) }.buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    /// What I compete in: a graph of the season per discipline, results come from the coach.
    @ViewBuilder
    private func mine(_ comps: [Progress.Series], _ waiting: [JSON]) -> some View {
        Text("MOJE DISCIPLINE").font(C.display(15)).foregroundColor(C.ink).padding(.top, 14)
        ForEach(Array(comps.enumerated()), id: \.offset) { _, s in
            Button { path.append(Route.series(s.key)) } label: { SeriesRow(series: s) }.buttonStyle(.plain)
        }
        ForEach(waiting, id: \.idKey) { d in
            HStack {
                Text(d.string("name")).font(C.bold(15)).foregroundColor(C.ink)
                Spacer()
                Text("još nema rezultata").font(C.text(12)).foregroundColor(C.muted)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
        }
        Text("Rezultate s natjecanja upisuje trener.").font(C.text(12)).foregroundColor(C.muted)
    }

    private func seasonTotals(_ me: String) -> (km: Double, kg: Double, n: Double) {
        var km = 0.0, kg = 0.0, n = 0.0
        for r in store.where(Store.results, "athleteId", me) {
            let t = Model.totals(store.doc(Store.sessions, r.string("sessionId")), r)
            km += t.km
            kg += t.kg
            if t.done > 0 { n += 1 }
        }
        return (km, kg, n)
    }

    private func sleep7(_ me: String) -> String {
        var sum = 0.0, n = 0.0
        for i in 0..<7 {
            if let d = store.doc(Store.daily, Model.dailyId(me, Fmt.iso(Fmt.addDays(Date(), -i)))), d.has("sleep") {
                sum += d.double("sleep")
                n += 1
            }
        }
        return n == 0 ? "–" : Fmt.n(sum / n) + " h"
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let bg: Color
    let fg: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(C.display(28)).foregroundColor(fg).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(C.text(12)).foregroundColor(fg.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(bg == C.card ? C.stone : .clear, lineWidth: 1))
    }
}

struct SeriesRow: View {
    let series: Progress.Series
    var body: some View {
        let comp: Bool = series.kind == Progress.comp
        let d: (now: Double, change: Double, full: Bool, day: Int)? = comp ? nil : Progress.delta(series)
        let pts: [Progress.Pt] = Progress.view(series, comp ? Progress.rAll : Progress.r1g, top: false)
        let sub: String = subText(comp, d)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(series.name).font(C.bold(15)).foregroundColor(C.ink).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(C.text(12)).foregroundColor(C.muted).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Sparkline(values: pts.map { $0.tr }, lower: series.lower).frame(width: 70, height: 28)
            if let d = d, abs(d.change) > 0.0001 {
                Text(Progress.deltaText(series, d.change)).font(C.bold(13))
                    .foregroundColor(Progress.good(series, d.change) ? C.green : C.coral)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(C.faint)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
    }

    /// Exercises: the trend now. Competitions: personal best and the best of this season.
    private func subText(_ comp: Bool, _ d: (now: Double, change: Double, full: Bool, day: Int)?) -> String {
        if comp { return Comp.rowText(series) }
        guard let d = d else { return "" }
        return series.fmt(d.now) + Boards.unit(series) + "  ·  " + series.metric
    }
}

struct Sparkline: View {
    let values: [Double]
    let lower: Bool
    var body: some View {
        GeometryReader { g in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 1e-9)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = g.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        var y = CGFloat((v - lo) / span)
                        if !lower { y = 1 - y }
                        let pt = CGPoint(x: x, y: 2 + y * (g.size.height - 4))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(C.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// One exercise over time: trend line, every session as a dot, records in coral.
struct SeriesView: View {
    let athleteId: String
    let key: String
    @ObservedObject var store = Store.shared
    @State private var range = Progress.r1g
    @State private var top = false

    var body: some View {
        let s = Progress.build(store, athleteId).first { $0.key == key }
        ScrollView {
            if let s = s {
                page(s, Progress.view(s, range, top: top))
            } else {
                EmptyCard(title: "Nema podataka", text: "Za ovu vježbu još nema upisa.").padding(16)
            }
        }
        .background(C.chalk)
        .navigationTitle("Napredak")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { widen(s) }
    }

    /// Nothing in the last year (an old record typed in, an exercise dropped long ago): open on everything.
    private func widen(_ s: Progress.Series?) {
        guard let s = s, range == Progress.r1g, !s.pts.isEmpty else { return }
        if Progress.view(s, Progress.r1g, top: false).isEmpty { range = Progress.rAll }
    }

    // Small pieces: Xcode 26's type checker times out on one big body.
    private func page(_ s: Progress.Series, _ pts: [Progress.Pt]) -> some View {
        let comp: Bool = s.kind == Progress.comp
        let shown: [Progress.Pt] = Array(pts.reversed().prefix(comp ? 40 : 12))
        return VStack(alignment: .leading, spacing: 12) {
            if comp { compHero(s) } else { hero(s, pts) }
            chips(s)
            Card {
                if pts.isEmpty {
                    Text(comp ? "Nema rezultata u ovom razdoblju." : "Nema upisa u ovom razdoblju.").font(C.text(14)).foregroundColor(C.muted)
                } else {
                    chart(s, pts).frame(height: 220)
                }
            }
            if s.kind == Progress.gym {
                Text("Procijenjeni 1RM računa se iz najboljeg seta dana po RPE tablici: 1 ponavljanje @10 je točno ta kila, a svako ponavljanje u rezervi diže procjenu. Set bez RPE računa se kao @10. Velika brojka gore je trend zadnjih pet treninga.")
                    .font(C.text(12)).foregroundColor(C.muted)
            }
            Text(comp ? "REZULTATI" : "ZADNJI UPISI").font(C.display(14)).foregroundColor(C.ink).padding(.top, 6)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, p in
                entry(s, p)
                Divider()
            }
        }
        .padding(16)
    }

    private func hero(_ s: Progress.Series, _ pts: [Progress.Pt]) -> some View {
        let d = Progress.delta(s)
        let good: Bool = d.map { Progress.good(s, $0.change) } ?? true
        let change: String = d.map { Progress.deltaText(s, $0.change) + ($0.full ? " u godinu dana" : " od " + Progress.date($0.day)) } ?? ""
        return Card(padding: 16, background: C.carbon, border: nil) {
            Label12(s.group, color: C.mutedLight)
            Text(s.name.uppercased()).font(C.display(22)).foregroundColor(.white).padding(.top, 4)
            if let last = pts.last {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(s.fmt(last.tr)).font(C.display(38)).foregroundColor(.white)
                    Text(unitLine(s)).font(C.text(13)).foregroundColor(C.mutedLight)
                }
                .padding(.top, 6)
            }
            if !change.isEmpty {
                Text(change).font(C.bold(13)).foregroundColor(good ? Color(hex: 0x3DDC97) : C.coral).padding(.top, 2)
            }
        }
    }

    /// A discipline: the personal best big, the best of this calendar year under it.
    private func compHero(_ s: Progress.Series) -> some View {
        let best: Progress.Pt? = s.best
        let year: Int = Comp.thisYear()
        let sb: Progress.Pt? = Comp.seasonBest(s, year)
        let big: String = best.map { Comp.fmt(s.cunit, $0.v) } ?? "–"
        let unit: String = best.map { Comp.suffix(s.cunit, $0.v).trimmingCharacters(in: .whitespaces) } ?? ""
        let when: String = best.map { Progress.date($0.day) } ?? ""
        let label: String = (unit.isEmpty ? "" : unit + "  ·  ") + "osobni rekord, " + when
        let season: String = sb.map { "Sezona \(year): " + Comp.text(s.cunit, $0.v) + ", " + Progress.date($0.day) } ?? "Sezona \(year): još bez rezultata"
        return Card(padding: 16, background: C.carbon, border: nil) {
            Label12(s.group, color: C.mutedLight)
            Text(s.name.uppercased()).font(C.display(22)).foregroundColor(.white).padding(.top, 4)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(big).font(C.display(38)).foregroundColor(.white)
                Text(label).font(C.text(13)).foregroundColor(C.mutedLight)
            }
            .padding(.top, 6)
            Text(season).font(C.bold(13)).foregroundColor(sb == nil ? C.mutedLight : Color(hex: 0x3DDC97)).padding(.top, 2)
        }
    }

    private func chips(_ s: Progress.Series) -> some View {
        HStack(spacing: 8) {
            Chip(title: "3 mj", on: range == Progress.r3m) { range = Progress.r3m }
            Chip(title: "1 god", on: range == Progress.r1g) { range = Progress.r1g }
            Chip(title: "Sve", on: range == Progress.rAll) { range = Progress.rAll }
            Spacer()
            if s.kind == Progress.gym {
                Chip(title: "Najteži set", on: top, onColor: C.blueFill) { top.toggle() }
            }
        }
    }

    /// One line of the list: the date, the set or result, for the gym what it estimates, and REKORD.
    private func entry(_ s: Progress.Series, _ p: Progress.Pt) -> some View {
        let est: String = s.kind == Progress.gym && !top ? "= " + s.fmt(p.v) + " kg" : ""
        return HStack(spacing: 8) {
            Text(Progress.date(p.day)).font(C.bold(13)).foregroundColor(C.ink).frame(width: 86, alignment: .leading)
            Text(p.set).font(C.text(13)).foregroundColor(C.muted).lineLimit(1)
            Spacer(minLength: 0)
            if !est.isEmpty { Text(est).font(C.bold(13)).foregroundColor(C.ink).lineLimit(1).fixedSize() }
            if p.pr { Tag(text: "REKORD", fg: .white, bg: C.coral) }
        }
        .padding(.vertical, 4)
    }

    private func chart(_ s: Progress.Series, _ pts: [Progress.Pt]) -> some View {
        // lower is better (times, pace): plot negated so faster sits higher
        let sign: Double = s.lower ? -1 : 1
        let vals = pts.map { $0.v * sign } + pts.map { $0.tr * sign }
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let pad = max((hi - lo) * 0.12, s.kind == Progress.gym ? 2 : 0.05)
        return Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Dan", day(p.day)), y: .value("Trend", p.tr * sign))
                    .foregroundStyle(C.blue)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("Dan", day(p.day)), y: .value("Rezultat", p.v * sign))
                    .foregroundStyle(p.pr ? C.coral : C.ink.opacity(0.35))
                    .symbolSize(p.pr ? 60 : 22)
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 30))
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(C.stone)
                AxisValueLabel { if let d = v.as(Double.self) { Text(s.fmt(abs(d))).font(C.text(10)) } }
            }
        }
    }

    private func unitLine(_ s: Progress.Series) -> String {
        let metric: String = top ? "najteži set" : s.metric
        return Boards.unit(s).trimmingCharacters(in: .whitespaces) + "  ·  " + metric + ", trend"
    }

    private func day(_ d: Int) -> Date { Date(timeIntervalSince1970: Double(d) * 86400 + 43200) }
}

// MARK: LJESTVICE

struct BoardTab: View {
    /// Coach only: opens the list where the exercises with a leaderboard are picked.
    var onEdit: (() -> Void)? = nil
    @ObservedObject var store = Store.shared
    @AppStorage("boardProg") private var prog = true
    @State private var loading = false
    @State private var error: String?
    @State private var open: BoardId?

    struct BoardId: Identifiable { let id: String }

    var body: some View {
        let boards = Boards.forTeam(store, prog: prog)
        let mine = boards.compactMap { $0.mine }
        let coach = Prefs.isCoach
        let gname = Groups.name(store, coach ? Groups.selected(store) : Groups.of(store, Prefs.athleteId))
        let hasComp: Bool = boards.contains { $0.series.kind == Progress.comp }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label12(gname.isEmpty ? "Ljestvice" : "Ljestvice · " + gname, color: Color(hex: 0xA9AFB3))
                        if coach {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text("\(boards.count)").font(C.display(40)).foregroundColor(.white)
                                Text(gname.isEmpty ? "ljestvica u timu" : "ljestvica u grupi").font(C.text(14)).foregroundColor(Color(hex: 0xA9AFB3))
                            }
                            Text("Dodirni ljestvicu za postolje i cijeli poredak.").font(C.text(12)).foregroundColor(Color(hex: 0xA9AFB3))
                        } else if mine.isEmpty {
                            Text("JOŠ NISI NA LJESTVICI").font(C.display(20)).foregroundColor(.white).padding(.top, 4)
                            Text(prog ? "Za Napredak trebaju barem dva upisa iste vježbe." : "Upiši rezultate na treningu.")
                                .font(C.text(12)).foregroundColor(Color(hex: 0xA9AFB3))
                        } else {
                            let avg = Double(mine.map { $0.place }.reduce(0, +)) / Double(mine.count)
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(Fmt.n((avg * 10).rounded() / 10) + ".").font(C.display(40)).foregroundColor(.white)
                                Text("prosječno mjesto").font(C.text(14)).foregroundColor(Color(hex: 0xA9AFB3))
                            }
                            movesText(mine).font(C.bold(13))
                        }
                    }
                    Spacer()
                    TrackLogo(size: 44)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(C.carbon))

                HStack(spacing: 8) {
                    Chip(title: "Napredak", on: prog) { prog = true }
                    Chip(title: "Najbolji rezultat", on: !prog) { prog = false }
                }
                .padding(.top, 2)
                if let edit = onEdit { pickRow(edit) }

                if loading && boards.isEmpty {
                    Text("Učitavam rezultate tima…").font(C.text(14)).foregroundColor(C.muted).padding(.top, 12)
                } else if let e = error, boards.isEmpty {
                    Text(e).font(C.bold(14)).foregroundColor(C.red).padding(.top, 12)
                } else if boards.isEmpty {
                    EmptyCard(title: "Još nema ljestvica", text: emptyText(coach)).padding(.top, 8)
                } else {
                    ForEach(Array(boards.enumerated()), id: \.offset) { i, b in
                        if i == 0 || boards[i - 1].series.group != b.series.group {
                            Text(b.series.group.uppercased()).font(C.display(13)).tracking(1).foregroundColor(C.ink).padding(.top, 10)
                        }
                        Button { open = BoardId(id: b.key) } label: { BoardRow(board: b, prog: prog) }.buttonStyle(.plain)
                    }
                    Text(footnote(coach, hasComp)).font(C.text(12)).foregroundColor(C.muted).padding(.top, 10)
                }
            }
            .padding(16)
        }
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .onAppear { shotPodium() }
        .sheet(item: $open) { o in
            if let b = boards.first(where: { $0.key == o.id }) {
                BoardDetail(board: b, prog: prog)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Screenshot mode "podium": the first board opens by itself.
    private func shotPodium() {
        guard Shot.name == "podium", open == nil else { return }
        if let b = Boards.forTeam(store, prog: prog).first { open = BoardId(id: b.key) }
    }

    /// Coach: "which exercises have a board" with a way in to change it.
    private func pickRow(_ edit: @escaping () -> Void) -> some View {
        let text: String = BoardPick.custom(store) ? "Ljestvicu imaju vježbe koje si odabrao." : "Ljestvicu ima svaka vježba."
        return Button(action: edit) {
            HStack(spacing: 8) {
                Text(text).font(C.text(13)).foregroundColor(C.muted)
                Spacer(minLength: 4)
                Text("ODABERI VJEŽBE").font(C.bold(12)).foregroundColor(C.blue)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func emptyText(_ coach: Bool) -> String {
        if BoardPick.custom(store) {
            return coach
                ? "Vježbe koje si uključio još nemaju dovoljno upisa. Druge uključiš preko ODABERI VJEŽBE."
                : "Koje vježbe imaju ljestvicu bira trener. Za uključene još nema dovoljno upisa."
        }
        return prog
            ? "Ljestvica se pojavi kad barem dvoje iz tima ima po dva upisa iste vježbe ili dionice."
            : "Ljestvica se pojavi kad barem dvoje iz tima upiše istu vježbu ili dionicu."
    }

    private func footnote(_ coach: Bool, _ comps: Bool) -> String {
        var t: String = prog
            ? "Napredak: koliko si bolji nego prije 12 mjeseci (ili od prvog upisa), u postocima."
            : "Najbolji rezultat u zadnjih 12 mjeseci. Teretana: procijenjeni 1RM."
        if comps { t += " Natjecanja: poredak po osobnom rekordu, u oba prikaza." }
        t += prog
            ? " Strelica: pomak na ljestvici u zadnjih 7 dana, ako si taj tjedan radio tu disciplinu."
            : " Strelica: pomak na ljestvici u zadnjih 7 dana."
        if !coach && BoardPick.custom(store) { t += " Koje vježbe imaju ljestvicu bira trener." }
        return t
    }

    private func movesText(_ mine: [Boards.Row]) -> Text {
        let up = mine.filter { $0.move > 0 }.count
        let down = mine.filter { $0.move < 0 }.count
        let same = mine.count - up - down
        let word: String = mine.count % 10 == 1 && mine.count % 100 != 11 ? "ljestvici" : "ljestvica"
        let grey = Color(hex: 0xA9AFB3)
        let a = Text("▲ \(up)").foregroundColor(Color(hex: 0x3DDC97))
        let b = Text("   ▼ \(down)").foregroundColor(C.coral)
        let c = Text("   = \(same)   u \(mine.count) \(word), 7 dana").foregroundColor(grey)
        return a + b + c
    }

    private func load(force: Bool) async {
        if store.demo || Prefs.isCoach || loading { return }
        if !force, let at = store.boardAt, Date().timeIntervalSince(at) < 120 { return }
        loading = true
        do { try await store.loadBoard(); error = nil } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct BoardRow: View {
    let board: Boards.Board
    let prog: Bool
    var body: some View {
        let mine = board.mine, lead = board.rows[0]
        let coach = Prefs.isCoach
        let medal: Bool = (mine?.place ?? 9) <= 3
        HStack(spacing: 10) {
            if coach {
                // the coach has no place of their own: the leader's initials
                Text(Fmt.initials(lead.name)).font(C.display(14)).foregroundColor(.white)
                    .frame(width: 40, height: 46)
                    .background(RoundedRectangle(cornerRadius: 10).fill(C.carbon))
            } else {
                Text(mine.map { "\($0.place)" } ?? "–").font(C.display(20)).foregroundColor(medal ? C.night : C.ink)
                    .frame(width: 40, height: 46)
                    .background(RoundedRectangle(cornerRadius: 10).fill(medal ? C.coral : C.chip))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(board.name).font(C.bold(15)).foregroundColor(C.ink).lineLimit(1)
                Text(mine?.place == 1 ? "vodiš, \(board.rows.count) na ljestvici" : "vodi " + Fmt.shortName(lead.name) + " · " + Boards.value(board, lead, prog))
                    .font(C.text(12)).foregroundColor(C.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if coach {
                Text("\(board.rows.count) sport.").font(C.text(12)).foregroundColor(C.muted)
            } else if let m = mine {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Boards.value(board, m, prog)).font(C.bold(14)).foregroundColor(C.ink)
                    Text(m.move > 0 ? "▲ \(m.move)" : m.move < 0 ? "▼ \(-m.move)" : "=")
                        .font(C.bold(12)).foregroundColor(m.move > 0 ? C.green : m.move < 0 ? C.coral : Color(hex: 0xA9AFB3))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
    }
}

/// Podium for 1-2-3 and the whole order.
struct BoardDetail: View {
    let board: Boards.Board
    let prog: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label12(board.series.group)
                Text(board.name.uppercased()).font(C.display(22)).foregroundColor(C.ink)
                Text(subtitle).font(C.text(13)).foregroundColor(C.muted)
                HStack(alignment: .bottom, spacing: 8) {
                    podium(1, height: 70)
                    podium(0, height: 100)
                    podium(2, height: 50)
                }
                .padding(.vertical, 10)
                ForEach(Array(board.rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 10) {
                        Text("\(r.place).").font(C.display(16)).foregroundColor(r.me ? C.coral : C.ink).frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name + (r.me ? " (ti)" : "")).font(C.bold(15)).foregroundColor(C.ink)
                            if !r.sub.isEmpty { Text(r.sub).font(C.text(12)).foregroundColor(C.muted) }
                        }
                        Spacer()
                        Text(Boards.value(board, r, prog)).font(C.bold(15)).foregroundColor(C.ink)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(r.me ? C.coralSoft : C.card))
                }
            }
            .padding(20)
        }
        .background(C.chalk)
    }

    private var subtitle: String {
        if board.series.kind == Progress.comp { return "Osobni rekordi s natjecanja" }
        return prog ? "Napredak u zadnjih 12 mjeseci" : "Najbolji rezultat u zadnjih 12 mjeseci"
    }

    @ViewBuilder private func podium(_ i: Int, height: CGFloat) -> some View {
        if i < board.rows.count {
            let r = board.rows[i]
            VStack(spacing: 6) {
                Text(Fmt.initials(r.name)).font(C.display(16)).foregroundColor(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(r.me ? C.coral : C.carbon))
                Text(Fmt.shortName(r.name)).font(C.bold(12)).foregroundColor(C.ink).lineLimit(1)
                Text(Boards.value(board, r, prog)).font(C.text(11)).foregroundColor(C.muted).lineLimit(1)
                Text("\(i + 1)").font(C.display(24)).foregroundColor(i == 0 ? C.night : .white)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(RoundedRectangle(cornerRadius: 10).fill(i == 0 ? C.coral : C.carbon2))
            }
            .frame(maxWidth: .infinity)
        } else {
            Spacer().frame(maxWidth: .infinity)
        }
    }
}

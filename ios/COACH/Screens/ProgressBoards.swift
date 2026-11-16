import SwiftUI
import Charts

// MARK: NAPREDAK

struct ProgressTab: View {
    @ObservedObject var store = Store.shared
    @Binding var path: NavigationPath

    var body: some View {
        let me = Prefs.athleteId
        let season = seasonTotals(me)
        let series = Progress.build(store, me)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("SEZONA").font(C.display(22)).foregroundColor(C.carbon)
                HStack(spacing: 12) {
                    StatTile(value: Fmt.n((season.km * 10).rounded() / 10), label: "km pretrčano", bg: C.carbon, fg: .white)
                    StatTile(value: Fmt.n2((season.kg / 10).rounded() / 100), label: "tona podignuto", bg: C.coral, fg: C.carbon)
                }
                HStack(spacing: 12) {
                    StatTile(value: "\(Int(season.n))", label: "treninga", bg: C.white, fg: C.carbon)
                    StatTile(value: sleep7(me), label: "san, zadnjih 7 dana", bg: C.blue, fg: .white)
                }
                Text("PO VJEŽBI").font(C.display(15)).foregroundColor(C.carbon).padding(.top, 14)
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
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(bg == C.white ? C.stone : .clear, lineWidth: 1))
    }
}

struct SeriesRow: View {
    let series: Progress.Series
    var body: some View {
        let d = Progress.delta(series)
        let pts = Progress.view(series, Progress.r1g, top: false)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(series.name).font(C.bold(15)).foregroundColor(C.carbon).lineLimit(1)
                if let d = d {
                    Text(series.fmt(d.now) + Boards.unit(series) + "  ·  " + series.metric).font(C.text(12)).foregroundColor(C.muted)
                }
            }
            Spacer(minLength: 4)
            Sparkline(values: pts.map { $0.tr }, lower: series.lower).frame(width: 70, height: 28)
            if let d = d, abs(d.change) > 0.0001 {
                Text(Progress.deltaText(series, d.change)).font(C.bold(13))
                    .foregroundColor(Progress.good(series, d.change) ? C.green : C.coral)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(C.mutedLight)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.stone, lineWidth: 1))
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
                let pts = Progress.view(s, range, top: top)
                VStack(alignment: .leading, spacing: 12) {
                    Card(padding: 16, background: C.carbon, border: nil) {
                        Label12(s.group, color: C.mutedLight)
                        Text(s.name.uppercased()).font(C.display(22)).foregroundColor(.white).padding(.top, 4)
                        if let last = pts.last {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(s.fmt(last.tr)).font(C.display(38)).foregroundColor(.white)
                                Text(unitLine(s))
                                    .font(C.text(13)).foregroundColor(C.mutedLight)
                            }
                            .padding(.top, 6)
                        }
                        if let d = Progress.delta(s) {
                            Text(Progress.deltaText(s, d.change) + (d.full ? " u godinu dana" : " od " + Progress.date(d.day)))
                                .font(C.bold(13)).foregroundColor(Progress.good(s, d.change) ? Color(hex: 0x3DDC97) : C.coral).padding(.top, 2)
                        }
                    }
                    HStack(spacing: 8) {
                        Chip(title: "3 mj", on: range == Progress.r3m) { range = Progress.r3m }
                        Chip(title: "1 god", on: range == Progress.r1g) { range = Progress.r1g }
                        Chip(title: "Sve", on: range == Progress.rAll) { range = Progress.rAll }
                        Spacer()
                        if s.kind == Progress.gym {
                            Chip(title: "Najteži set", on: top, onColor: C.blue) { top.toggle() }
                        }
                    }
                    Card {
                        if pts.isEmpty {
                            Text("Nema upisa u ovom razdoblju.").font(C.text(14)).foregroundColor(C.muted)
                        } else {
                            chart(s, pts).frame(height: 220)
                        }
                    }
                    Text("ZADNJI UPISI").font(C.display(14)).foregroundColor(C.carbon).padding(.top, 6)
                    ForEach(Array(pts.reversed().prefix(12).enumerated()), id: \.offset) { _, p in
                        HStack {
                            Text(Progress.date(p.day)).font(C.bold(13)).foregroundColor(C.carbon).frame(width: 96, alignment: .leading)
                            Text(p.set).font(C.text(13)).foregroundColor(C.muted).lineLimit(1)
                            Spacer()
                            if p.pr { Tag(text: "REKORD", fg: .white, bg: C.coral) }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(16)
            } else {
                EmptyCard(title: "Nema podataka", text: "Za ovu vježbu još nema upisa.").padding(16)
            }
        }
        .background(C.chalk)
        .navigationTitle("Napredak")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                    .foregroundStyle(p.pr ? C.coral : C.carbon.opacity(0.35))
                    .symbolSize(p.pr ? 60 : 22)
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(C.stone)
                AxisValueLabel { if let d = v.as(Double.self) { Text(s.fmt(abs(d))).font(C.text(10)) } }
            }
        }
    }

    private func unitLine(_ s: Progress.Series) -> String {
        let metric: String = top ? "najteži set" : s.metric
        return Boards.unit(s).trimmingCharacters(in: .whitespaces) + "  ·  " + metric
    }

    private func day(_ d: Int) -> Date { Date(timeIntervalSince1970: Double(d) * 86400 + 43200) }
}

// MARK: LJESTVICE

struct BoardTab: View {
    @ObservedObject var store = Store.shared
    @AppStorage("boardProg") private var prog = true
    @State private var loading = false
    @State private var error: String?
    @State private var open: BoardId?

    struct BoardId: Identifiable { let id: String }

    var body: some View {
        let boards = Boards.forTeam(store, prog: prog)
        let mine = boards.compactMap { $0.mine }
        let gname = Groups.name(store, Groups.of(store, Prefs.athleteId))
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label12(gname.isEmpty ? "Ljestvice" : "Ljestvice · " + gname, color: Color(hex: 0xA9AFB3))
                        if mine.isEmpty {
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

                if loading && boards.isEmpty {
                    Text("Učitavam rezultate tima…").font(C.text(14)).foregroundColor(C.muted).padding(.top, 12)
                } else if let e = error, boards.isEmpty {
                    Text(e).font(C.bold(14)).foregroundColor(C.red).padding(.top, 12)
                } else if boards.isEmpty {
                    EmptyCard(title: "Još nema ljestvica", text: prog
                              ? "Ljestvica se pojavi kad barem dvoje iz tima ima po dva upisa iste vježbe ili dionice."
                              : "Ljestvica se pojavi kad barem dvoje iz tima upiše istu vježbu ili dionicu.")
                        .padding(.top, 8)
                } else {
                    ForEach(Array(boards.enumerated()), id: \.offset) { i, b in
                        if i == 0 || boards[i - 1].series.group != b.series.group {
                            Text(b.series.group.uppercased()).font(C.display(13)).tracking(1).foregroundColor(C.carbon).padding(.top, 10)
                        }
                        Button { open = BoardId(id: b.key) } label: { BoardRow(board: b, prog: prog) }.buttonStyle(.plain)
                    }
                    Text(prog
                         ? "Napredak: koliko si bolji nego prije 12 mjeseci (ili od prvog upisa), u postocima. Strelica: pomak na ljestvici u zadnjih 7 dana, ako si taj tjedan radio tu disciplinu."
                         : "Najbolji rezultat u zadnjih 12 mjeseci. Teretana: procijenjeni 1RM. Strelica: pomak na ljestvici u zadnjih 7 dana.")
                        .font(C.text(12)).foregroundColor(C.muted).padding(.top, 10)
                }
            }
            .padding(16)
        }
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .sheet(item: $open) { o in
            if let b = boards.first(where: { $0.key == o.id }) {
                BoardDetail(board: b, prog: prog)
                    .presentationDetents([.medium, .large])
            }
        }
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
        if store.demo || loading { return }
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
        HStack(spacing: 10) {
            Text(mine.map { "\($0.place)" } ?? "–").font(C.display(20)).foregroundColor(C.carbon)
                .frame(width: 40, height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(mine != nil && mine!.place <= 3 ? C.coral : Color(hex: 0xEDEFEE)))
            VStack(alignment: .leading, spacing: 2) {
                Text(board.name).font(C.bold(15)).foregroundColor(C.carbon).lineLimit(1)
                Text(mine?.place == 1 ? "vodiš, \(board.rows.count) na ljestvici" : "vodi " + Fmt.shortName(lead.name) + " · " + Boards.value(board, lead, prog))
                    .font(C.text(12)).foregroundColor(C.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let m = mine {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Boards.value(board, m, prog)).font(C.bold(14)).foregroundColor(C.carbon)
                    Text(m.move > 0 ? "▲ \(m.move)" : m.move < 0 ? "▼ \(-m.move)" : "=")
                        .font(C.bold(12)).foregroundColor(m.move > 0 ? C.green : m.move < 0 ? C.coral : Color(hex: 0xA9AFB3))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.white))
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
                Text(board.name.uppercased()).font(C.display(22)).foregroundColor(C.carbon)
                Text(prog ? "Napredak u zadnjih 12 mjeseci" : "Najbolji rezultat u zadnjih 12 mjeseci").font(C.text(13)).foregroundColor(C.muted)
                HStack(alignment: .bottom, spacing: 8) {
                    podium(1, height: 70)
                    podium(0, height: 100)
                    podium(2, height: 50)
                }
                .padding(.vertical, 10)
                ForEach(Array(board.rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 10) {
                        Text("\(r.place).").font(C.display(16)).foregroundColor(r.me ? C.coral : C.carbon).frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name + (r.me ? " (ti)" : "")).font(C.bold(15)).foregroundColor(C.carbon)
                            if !r.sub.isEmpty { Text(r.sub).font(C.text(12)).foregroundColor(C.muted) }
                        }
                        Spacer()
                        Text(Boards.value(board, r, prog)).font(C.bold(15)).foregroundColor(C.carbon)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(r.me ? C.coralSoft : C.white))
                }
            }
            .padding(20)
        }
        .background(C.chalk)
    }

    @ViewBuilder private func podium(_ i: Int, height: CGFloat) -> some View {
        if i < board.rows.count {
            let r = board.rows[i]
            VStack(spacing: 6) {
                Text(Fmt.initials(r.name)).font(C.display(16)).foregroundColor(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(r.me ? C.coral : C.carbon))
                Text(Fmt.shortName(r.name)).font(C.bold(12)).foregroundColor(C.carbon).lineLimit(1)
                Text(Boards.value(board, r, prog)).font(C.text(11)).foregroundColor(C.muted).lineLimit(1)
                Text("\(i + 1)").font(C.display(24)).foregroundColor(i == 0 ? C.carbon : .white)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(RoundedRectangle(cornerRadius: 10).fill(i == 0 ? C.coral : C.carbon2))
            }
            .frame(maxWidth: .infinity)
        } else {
            Spacer().frame(maxWidth: .infinity)
        }
    }
}

import Foundation

/// Formatting for times, dates and numbers (Croatian). Same rules as Fmt.java.
enum Fmt {
    static let daysShort = ["Pon", "Uto", "Sri", "Čet", "Pet", "Sub", "Ned"]
    static let daysLong = ["Ponedjeljak", "Utorak", "Srijeda", "Četvrtak", "Petak", "Subota", "Nedjelja"]

    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }()

    static func id() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
    }

    static func initials(_ n: String) -> String {
        var out = ""
        for p in n.split(whereSeparator: { $0 == " " || $0 == "\t" }) where out.count < 2 {
            if let c = p.first { out.append(Character(c.uppercased())) }
        }
        return out
    }

    // MARK: dates (ISO yyyy-MM-dd, local)

    static func iso(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func today() -> String { iso(Date()) }

    static func date(_ iso: String) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        if p.count == 3, let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) { return d }
        return startOfDay(Date())
    }

    static func startOfDay(_ d: Date) -> Date {
        cal.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d
    }

    static func addDays(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }

    /// Monday of the week of d.
    static func monday(_ d: Date) -> Date { addDays(startOfDay(d), -weekdayIndex(d)) }

    /// 0 = Monday … 6 = Sunday
    static func weekdayIndex(_ d: Date) -> Int { (cal.component(.weekday, from: d) + 5) % 7 }

    static func dayShort(_ d: Date) -> String { daysShort[weekdayIndex(d)] }
    static func dayLong(_ d: Date) -> String { daysLong[weekdayIndex(d)] }

    static func dm(_ d: Date) -> String {
        "\(cal.component(.day, from: d)).\(cal.component(.month, from: d))."
    }

    static func nice(_ iso: String) -> String {
        let d = date(iso)
        return dayLong(d) + ", " + dm(d)
    }

    static func niceRelative(_ iso: String) -> String {
        let t = today()
        let d = date(iso)
        if iso == t { return "Danas, " + dm(d) }
        if iso == Fmt.iso(addDays(Date(), 1)) { return "Sutra, " + dm(d) }
        if iso == Fmt.iso(addDays(Date(), -1)) { return "Jučer, " + dm(d) }
        return nice(iso)
    }

    // MARK: times

    /// 90 -> "1:30", 62.45 -> "1:02.45", 12.3 -> "12.3".
    static func time(_ seconds: Double) -> String {
        if seconds < 0 { return "" }
        let v = (seconds * 100).rounded() / 100
        let m = Int(v / 60)
        let s = v - Double(m * 60)
        if m == 0 { return secs(s, pad: false) }
        return "\(m):" + secs(s, pad: true)
    }

    /// Whole seconds as a stopwatch: 2170 -> "36:10", 4325 -> "1:12:05".
    static func clock(_ seconds: Double) -> String {
        if seconds < 0 { return "–" }
        let s = Int64(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, ss = s % 60
        let sec = (ss < 10 ? "0" : "") + String(ss)
        if h > 0 { return "\(h):" + (m < 10 ? "0" : "") + "\(m):" + sec }
        return "\(m):" + sec
    }

    static func secs(_ s: Double, pad: Bool) -> String {
        let hund = Int64((s * 100).rounded())
        let whole = hund / 100, frac = hund % 100
        let w = pad && whole < 10 ? "0\(whole)" : "\(whole)"
        if frac == 0 { return w }
        var f = frac < 10 ? "0\(frac)" : "\(frac)"
        if f.hasSuffix("0") { f = String(f.prefix(1)) }
        return w + "." + f
    }

    /// Accepts "1:30", "1:02.45", "62,4", "12.3". Returns -1 when empty or invalid.
    static func parseTime(_ raw: String?) -> Double {
        guard var t = raw else { return -1 }
        t = t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return -1 }
        if let i = t.firstIndex(of: ":") {
            let ms = String(t[t.startIndex..<i])
            let ss = String(t[t.index(after: i)...])
            guard let m = ms.isEmpty ? 0 : Int(ms) else { return -1 }
            guard let s = ss.isEmpty ? 0 : Double(ss) else { return -1 }
            return Double(m) * 60 + s
        }
        return Double(t) ?? -1
    }

    static func num(_ raw: String?) -> Double {
        guard var s = raw else { return 0 }
        s = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if s.isEmpty { return 0 }
        if let d = Double(s), d.isFinite { return d }
        // "8-10" style ranges: take the first number
        var b = ""
        for ch in s {
            if ch.isNumber || ch == "." { b.append(ch) } else if !b.isEmpty { break }
        }
        return Double(b) ?? 0
    }

    /// 12.0 -> "12", 12.5 -> "12,5".
    static func n(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.001 { return String(Int64(v.rounded())) }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Always two decimals: 8.0 -> "8,00".
    static func km(_ v: Double) -> String {
        String(format: "%.2f", (v * 100 + 1e-6).rounded(.down) / 100).replacingOccurrences(of: ".", with: ",")
    }

    static func n2(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.001 { return String(Int64(v.rounded())) }
        return String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func firstName(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let i = n.firstIndex(of: " ") { return String(n[..<i]) }
        return n
    }

    /// "Ivan Kovač" -> "Ivan K."
    static func shortName(_ name: String) -> String {
        let p = name.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if p.count < 2 { return name.trimmingCharacters(in: .whitespaces) }
        return "\(p[0]) \(p[p.count - 1].prefix(1))."
    }
}

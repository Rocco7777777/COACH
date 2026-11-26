import Foundation

/// Copying a session to another day, with the kg of the gym exercises the coach ticks changed by a percentage
/// (SessionCopy.java). The copy is an ordinary session document: nothing new is stored.
@MainActor
enum SessionCopy {
    /// What a changed weight is rounded to, in kg. The coach picks one; the phone remembers it.
    static let steps: [Double] = [0.5, 1, 2.5]
    static let defaultStep = 2.5
    static let defaultPercent = "5"

    /// "5", "7,5", "-10" → the percentage, kept within -50…+100. Empty or not a number = 0.
    static func percent(_ typed: String) -> Double {
        var t = typed.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("+") { t.removeFirst() }
        guard let p = Double(t), p.isFinite else { return 0 }
        return min(100, max(-50, p))
    }

    /// kg × (1 + p/100) rounded to the step, halves up. Same operations in the same order as the Android app,
    /// so both phones write the same number. nil when there is no weight above zero to change.
    static func scale(_ kg: Double, _ percent: Double, _ step: Double) -> Double? {
        guard kg > 0, step > 0 else { return nil }
        let v = (kg * (1 + percent / 100) / step).rounded() * step
        return v > 0 ? v : nil
    }

    /// A weight the way the editor stores it: "105", "102.5" (dot, no trailing zero).
    static func text(_ kg: Double) -> String {
        let t = (kg * 100).rounded() / 100
        if t == t.rounded() { return String(Int64(t)) }
        var s = String(format: "%.2f", t)
        if s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// The stored kg after the change; nil when the field is empty, zero or not a number (it stays as it is).
    static func scaledText(_ kg: String, _ percent: Double, _ step: Double) -> String? {
        guard let v = scale(Fmt.num(kg), percent, step) else { return nil }
        return text(v)
    }

    /// A gym item with a weight somewhere: in the plan or in an athlete's own numbers.
    static func hasKg(_ item: JSON) -> Bool {
        guard item.isObject, item.string("type") == "gym" else { return false }
        if Fmt.num(item.string("kg")) > 0 { return true }
        return item["per"].dict.values.contains { Fmt.num($0.string("kg")) > 0 }
    }

    /// The items the coach can tick.
    static func scalable(_ session: JSON) -> [JSON] {
        session["items"].list.filter { hasKg($0) }
    }

    /// One item with the plan's kg and every athlete's own kg changed. Sets, reps and RPE are never touched.
    static func scaled(_ item: JSON, _ percent: Double, _ step: Double) -> JSON {
        var it = item
        if let v = scaledText(it.string("kg"), percent, step) { it["kg"] = .str(v) }
        var per = it["per"]
        if per.isObject {
            for k in per.keys {
                if let v = scaledText(per[k].string("kg"), percent, step) { per[k]["kg"] = .str(v) }
            }
            it["per"] = per
        }
        return it
    }

    /// The copy on another day: a new id, the same items (their ids too), only groups that still exist, and the
    /// ticked items' kg changed. Results and attendance belong to the source and are not copied.
    static func make(_ store: Store, _ source: JSON, date: String, ticked: Set<String>, percent: Double, step: Double) -> JSON {
        var n = source
        n["id"] = .str(Fmt.id())
        n["date"] = .str(date)
        if percent != 0 && !ticked.isEmpty {
            var items = n["items"].list
            for i in items.indices where hasKg(items[i]) && ticked.contains(items[i].string("id")) {
                items[i] = scaled(items[i], percent, step)
            }
            n["items"] = .arr(items)
        }
        Groups.tidy(store, &n) // deleted groups dropped, all groups = whole team
        return n
    }

    // MARK: what the phone remembers

    /// The rounding step chosen last time.
    static var step: Double {
        let s = Prefs.copyStep
        return steps.contains(s) ? s : defaultStep
    }

    /// Items to tick when the screen opens: the exercises ticked the last time they were offered.
    static func preticked(_ session: JSON) -> Set<String> {
        let known = Set(Prefs.copyTicked)
        if known.isEmpty { return [] }
        return Set(scalable(session).filter { known.contains(ExerciseNames.fold($0.string("name"))) }.map { $0.string("id") })
    }

    /// Keeps the choice for next time: the names offered now are forgotten, the ticked ones stored again.
    /// Exercises that were not in this session stay as they were.
    static func remember(_ session: JSON, _ ticked: Set<String>, _ step: Double) {
        var known = Set(Prefs.copyTicked)
        let items = scalable(session)
        for it in items { known.remove(ExerciseNames.fold(it.string("name"))) }
        for it in items where ticked.contains(it.string("id")) {
            let name = ExerciseNames.fold(it.string("name"))
            if !name.isEmpty { known.insert(name) }
        }
        Prefs.copyTicked = known.sorted()
        Prefs.copyStep = step
    }
}

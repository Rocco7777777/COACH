import Foundation

/// Gym exercise names already used (in sessions and old records), offered while typing a new one (ExerciseNames.java).
/// One spelling per graph key (the most used one), most used first. Picking a suggestion keeps the name identical,
/// so the progress graph and the leaderboard don't split into "Čučanj" and "cucanj".
@MainActor
enum ExerciseNames {
    static func all(_ s: Store) -> [String] {
        var count: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        func add(_ name: String) {
            let n = name.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if n.isEmpty { return }
            let k = Progress.gymKey(n)
            count[k, default: 0] += 1
            spellings[k, default: [:]][n, default: 0] += 1
        }
        for ses in s.all(Store.sessions) {
            for it in ses["items"].list where it.string("type") == "gym" { add(it.string("name")) }
        }
        for r in s.all(Store.results) {
            for o in r["records"].list where o.string("kind") == "gym" { add(o.string("name")) }
        }
        let keys = count.keys.sorted { a, b in
            let c = count[b]! - count[a]!
            return c != 0 ? c < 0 : a < b
        }
        return keys.compactMap { k in
            spellings[k]?.max { x, y in x.value != y.value ? x.value < y.value : x.key > y.key }?.key
        }
    }

    /// Lower case without diacritics: "Čučanj" and "cucanj" match, đ matches d.
    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "đ", with: "d")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Up to max names containing what was typed; names starting with it (or with a word of it) come first.
    static func match(_ names: [String], _ typed: String, _ max: Int) -> [String] {
        let q = fold(typed)
        if q.isEmpty { return [] }
        let key = Progress.gymKey(typed)
        var same: [String] = [], first: [String] = [], rest: [String] = []
        for n in names {
            let f = fold(n)
            if Progress.gymKey(n) == key || !f.contains(q) { continue }
            if f == q { same.append(n) } else if f.hasPrefix(q) || f.contains(" " + q) { first.append(n) } else { rest.append(n) }
        }
        return Array((same + first + rest).prefix(max))
    }
}

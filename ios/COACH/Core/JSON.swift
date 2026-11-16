import Foundation

/// A JSON value that keeps every field it was given, so documents written by the Android app
/// survive a round trip through the iPhone untouched (unknown fields included).
/// Accessors follow org.json's optString / optDouble / optBoolean so ported logic reads the same.
enum JSON: Equatable {
    case null
    case bool(Bool)
    case num(Double)
    case str(String)
    case arr([JSON])
    case obj([String: JSON])

    static func object() -> JSON { .obj([:]) }
    static func array() -> JSON { .arr([]) }

    // MARK: parsing / writing

    init(data: Data) throws {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        self = JSON(any: any)
    }

    init(string: String) throws {
        try self.init(data: Data(string.utf8))
    }

    init(any: Any?) {
        guard let v = any, !(v is NSNull) else { self = .null; return }
        if let n = v as? NSNumber, !(v is String) {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .num(n.doubleValue) }
        } else if let s = v as? String {
            self = .str(s)
        } else if let a = v as? [Any] {
            self = .arr(a.map { JSON(any: $0) })
        } else if let o = v as? [String: Any] {
            var m: [String: JSON] = [:]
            for (k, x) in o { m[k] = JSON(any: x) }
            self = .obj(m)
        } else {
            self = .null
        }
    }

    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .num(let d):
            if d.rounded() == d && abs(d) < 9.0e15 { return Int64(d) }
            return d
        case .str(let s): return s
        case .arr(let a): return a.map { $0.any }
        case .obj(let o): return o.mapValues { $0.any }
        }
    }

    func data() -> Data {
        switch self {
        case .obj, .arr:
            return (try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])) ?? Data("null".utf8)
        default:
            return (try? JSONSerialization.data(withJSONObject: [any], options: [])).map { d in
                // strip the wrapping [ ]
                Data(d.dropFirst().dropLast())
            } ?? Data("null".utf8)
        }
    }

    var text: String { String(data: data(), encoding: .utf8) ?? "null" }

    // MARK: access

    subscript(key: String) -> JSON {
        get {
            if case .obj(let o) = self { return o[key] ?? .null }
            return .null
        }
        set {
            var o: [String: JSON]
            if case .obj(let m) = self { o = m } else { o = [:] }
            o[key] = newValue
            self = .obj(o)
        }
    }

    subscript(index: Int) -> JSON {
        get {
            if case .arr(let a) = self, index >= 0, index < a.count { return a[index] }
            return .null
        }
        set {
            var a: [JSON]
            if case .arr(let m) = self { a = m } else { a = [] }
            while a.count <= index { a.append(.null) }
            a[index] = newValue
            self = .arr(a)
        }
    }

    var isNull: Bool { if case .null = self { return true }; return false }
    var isObject: Bool { if case .obj = self { return true }; return false }
    var isArray: Bool { if case .arr = self { return true }; return false }

    func has(_ key: String) -> Bool {
        if case .obj(let o) = self { return o[key] != nil }
        return false
    }

    mutating func remove(_ key: String) {
        if case .obj(var o) = self {
            o.removeValue(forKey: key)
            self = .obj(o)
        }
    }

    mutating func append(_ v: JSON) {
        var a: [JSON]
        if case .arr(let m) = self { a = m } else { a = [] }
        a.append(v)
        self = .arr(a)
    }

    var keys: [String] {
        if case .obj(let o) = self { return Array(o.keys) }
        return []
    }

    var dict: [String: JSON] {
        if case .obj(let o) = self { return o }
        return [:]
    }

    /// Array elements, [] for anything else.
    var list: [JSON] {
        if case .arr(let a) = self { return a }
        return []
    }

    var count: Int { list.count }

    /// org.json optString: numbers as written ("100", "2.5"), booleans as "true"/"false", "" otherwise.
    var asString: String {
        switch self {
        case .str(let s): return s
        case .num(let d): return JSON.numberText(d)
        case .bool(let b): return b ? "true" : "false"
        default: return ""
        }
    }

    func string(_ key: String, _ def: String = "") -> String {
        let v = self[key]
        if v.isNull { return def }
        if case .obj = v { return v.text }
        if case .arr = v { return v.text }
        return v.asString
    }

    /// org.json optDouble: numbers, or strings that parse; def otherwise.
    func double(_ key: String, _ def: Double = 0) -> Double { self[key].doubleValue(def) }

    func doubleValue(_ def: Double = 0) -> Double {
        switch self {
        case .num(let d): return d
        case .str(let s): return Double(s.trimmingCharacters(in: .whitespaces)) ?? def
        default: return def
        }
    }

    func int(_ key: String, _ def: Int = 0) -> Int {
        let d = self[key].doubleValue(Double(def))
        return d.isFinite ? Int(d) : def
    }

    func long(_ key: String) -> Int64 {
        let d = self[key].doubleValue(0)
        return d.isFinite ? Int64(d) : 0
    }

    func bool(_ key: String) -> Bool {
        switch self[key] {
        case .bool(let b): return b
        case .str(let s): return s.lowercased() == "true"
        default: return false
        }
    }

    static func numberText(_ d: Double) -> String {
        if d.rounded() == d && abs(d) < 9.0e15 { return String(Int64(d)) }
        return String(d)
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(stringLiteral value: String) { self = .str(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .num(value) }
    init(integerLiteral value: Int) { self = .num(Double(value)) }
    init(arrayLiteral elements: JSON...) { self = .arr(elements) }
    init(dictionaryLiteral elements: (String, JSON)...) {
        var o: [String: JSON] = [:]
        for (k, v) in elements { o[k] = v }
        self = .obj(o)
    }
}

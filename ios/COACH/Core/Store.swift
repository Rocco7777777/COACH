import Foundation
import SwiftUI

struct AuthError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

struct HttpError: LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

/// Offline-first document store (Store.java). Every write lands in a local JSON file first and is
/// queued in an outbox; the outbox goes to the shared Supabase table "docs" (team_id, coll, id, data)
/// whenever the network allows. Reads always come from the local copy.
@MainActor
final class Store: ObservableObject {
    static let athletes = "athletes"
    static let sessions = "sessions"
    static let results = "results"
    static let daily = "daily"
    static let config = "config"

    static let shared = Store()

    /// Bumped on every local change, so screens redraw.
    @Published private(set) var version = 0
    /// Bumped when the account, its role or team changes (the root view picks the screen again).
    @Published private(set) var sessionVersion = 0

    private let dir: URL
    private var cache: [String: [String: JSON]] = [:]
    private var outbox: [JSON] = []
    private var pushing = false
    private var syncing = false
    private let url = Prefs.serverUrl
    private let key = Prefs.serverKey
    var lastError: String?
    var lastSync: Date?
    var teamError: String?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("store", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let j = try? JSON(data: Data(contentsOf: dir.appendingPathComponent("_outbox.json"))) { outbox = j.list }
    }

    var demo: Bool { Prefs.demoMode }

    var loggedIn: Bool {
        if demo { return !Prefs.athleteId.isEmpty }
        return !Prefs.refreshToken.isEmpty && !Prefs.athleteId.isEmpty
    }

    /// Talks to Supabase. Never while showing the demo.
    var sharedOn: Bool { !demo }

    var pending: Int { outbox.count }

    func changed() { version &+= 1 }

    func sessionChanged() {
        sessionVersion &+= 1
        version &+= 1
    }

    // MARK: auth

    func signIn(email: String, password: String) async throws -> JSON {
        let body: JSON = ["email": .str(email.trimmingCharacters(in: .whitespaces)), "password": .str(password)]
        let r = try await authCall("/auth/v1/token?grant_type=password", body)
        saveSession(r, email.trimmingCharacters(in: .whitespaces))
        return try await loadProfile()
    }

    /// Returns the profile, or nil when the email must be confirmed first.
    func signUp(email: String, password: String, name: String, joinCode: String, teamName: String) async throws -> JSON? {
        var meta: JSON = ["name": .str(name.trimmingCharacters(in: .whitespaces))]
        if !joinCode.isEmpty { meta["join_code"] = .str(joinCode) } else if !teamName.isEmpty { meta["team_name"] = .str(teamName.trimmingCharacters(in: .whitespaces)) }
        let body: JSON = ["email": .str(email.trimmingCharacters(in: .whitespaces)), "password": .str(password), "data": meta]
        let r = try await authCall("/auth/v1/signup", body)
        if r.string("access_token").isEmpty { return nil }
        saveSession(r, email.trimmingCharacters(in: .whitespaces))
        return try await loadProfile()
    }

    private func saveSession(_ r: JSON, _ email: String) {
        let user = r["user"]
        let exp = Date().timeIntervalSince1970 * 1000 + r.double("expires_in", 3600) * 1000
        Prefs.setSession(id: user.isObject ? user.string("id") : Prefs.athleteId, email: email,
                         access: r.string("access_token"), refresh: r.string("refresh_token"), expiry: exp)
    }

    static let oldDb = "Baza još nije nadograđena. Trener mora u Supabase pokrenuti novi supabase.sql."

    @discardableResult
    func loadProfile() async throws -> JSON {
        let uid = Prefs.athleteId
        let a: JSON
        do {
            a = try JSON(string: try await http("GET", "/rest/v1/profiles?select=id,name,role,team_id&id=eq." + enc(uid), nil))
        } catch let e as HttpError {
            if e.message.contains("team_id") { throw AuthError(Store.oldDb) }
            throw e
        }
        guard a.count > 0 else { throw AuthError("Profil nije pronađen. Je li pokrenut supabase.sql?") }
        let p = a[0]
        Prefs.setProfile(name: p.string("name"), role: p.string("role", "athlete"))
        let team = p["team_id"].isNull ? "" : p.string("team_id")
        let old = Prefs.teamId
        if old != team {
            if !old.isEmpty { clearData() }
            Prefs.setTeamId(team)
            Prefs.setTeam(name: "", coach: "", code: "")
        }
        return p
    }

    func ensureTeam() async throws {
        if Prefs.teamId.isEmpty {
            let code = Prefs.pendingCode, team = Prefs.pendingTeam
            if !code.isEmpty { _ = try await rpc("join_team", ["p_code": .str(code)]) }
            else if !team.isEmpty { _ = try await rpc("create_team", ["p_name": .str(team)]) }
            else { return }
            try await loadProfile()
        }
        if !Prefs.teamId.isEmpty {
            Prefs.pendingCode = ""
            Prefs.pendingTeam = ""
            teamError = nil
            try await loadTeam()
        }
    }

    func loadTeam() async throws {
        let r = try await rpc("team_info", .object()).trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty || r == "null" { return }
        let t = try JSON(string: r)
        Prefs.setTeam(name: t.string("name"), coach: t["coach"].isNull ? "" : t.string("coach"), code: t["code"].isNull ? "" : t.string("code"))
    }

    func joinTeam(_ code: String) async throws {
        Prefs.pendingCode = code
        Prefs.pendingTeam = ""
        if !Prefs.teamId.isEmpty {
            _ = try await rpc("join_team", ["p_code": .str(code)])
            try await loadProfile()
        }
        try await ensureTeam()
    }

    func createTeam(_ name: String) async throws {
        Prefs.pendingCode = ""
        Prefs.pendingTeam = name
        try await ensureTeam()
    }

    func deleteAccount() async throws {
        _ = try await rpc("delete_my_account", .object())
    }

    // MARK: leaderboards

    private var board: [JSON]?
    private(set) var boardAt: Date?

    func boardResults() -> [JSON] {
        if board == nil {
            board = ((try? JSON(data: Data(contentsOf: dir.appendingPathComponent("_board.json")))) ?? .array()).list.filter { $0.isObject }
        }
        return board ?? []
    }

    func loadBoard() async throws {
        if demo { return }
        let r = try await rpc("team_board", .object()).trimmingCharacters(in: .whitespacesAndNewlines)
        let a = (r.isEmpty || r == "null") ? JSON.array() : try JSON(string: r)
        board = a.list.filter { $0.isObject }
        boardAt = Date()
        write("_board.json", a.data())
        changed()
    }

    private func rpc(_ fn: String, _ args: JSON) async throws -> String {
        do {
            return try await http("POST", "/rest/v1/rpc/" + fn, args.text)
        } catch let e as HttpError {
            if let brace = e.message.firstIndex(of: "{"), let j = try? JSON(string: String(e.message[brace...])) {
                let msg = j.string("message")
                if j.string("code") == "PGRST202" || msg.contains("Could not find the function") { throw AuthError(Store.oldDb) }
                if !msg.isEmpty { throw AuthError(msg) }
            }
            throw e
        } catch let e as URLError {
            _ = e
            throw AuthError("Nema interneta.")
        }
    }

    private func authCall(_ path: String, _ body: JSON) async throws -> JSON {
        var req = URLRequest(url: URL(string: url + path)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data()
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthError("Nema interneta.")
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 400 {
            var msg = ""
            if let e = try? JSON(data: data) {
                for k in ["msg", "error_description", "message", "error"] where msg.isEmpty { msg = e.string(k) }
            }
            let low = msg.lowercased()
            if low.contains("invalid login") { throw AuthError("Krivi email ili lozinka.") }
            if low.contains("not confirmed") { throw AuthError("Email još nije potvrđen. Otvori link iz maila pa se prijavi.") }
            if low.contains("already registered") || low.contains("already been registered") { throw AuthError("Taj email već ima račun. Prijavi se.") }
            if low.contains("password") { throw AuthError("Lozinka mora imati barem 6 znakova.") }
            if low.contains("rate limit") { throw AuthError("Previše pokušaja. Pričekaj par minuta pa probaj opet.") }
            if path.contains("refresh_token") { throw HttpError(code: 401, message: "Prijava je istekla. Prijavi se ponovno.") }
            throw AuthError(msg.isEmpty ? "Greška \(code)" : msg)
        }
        return try JSON(data: data)
    }

    private func ensureToken(force: Bool) async throws {
        let refresh = Prefs.refreshToken
        if refresh.isEmpty { return }
        if !force && Date().timeIntervalSince1970 * 1000 < Prefs.tokenExpiry - 60000 { return }
        let r = try await authCall("/auth/v1/token?grant_type=refresh_token", ["refresh_token": .str(refresh)])
        saveSession(r, Prefs.email)
    }

    /// Logging out: forget the session and everything cached on this phone.
    func wipe() {
        Prefs.clearSession()
        clearData()
        sessionChanged()
    }

    private func clearData() {
        cache.removeAll()
        board = nil
        boardAt = nil
        outbox.removeAll()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    // MARK: local reads

    private func coll(_ name: String) -> [String: JSON] {
        if let m = cache[name] { return m }
        var m: [String: JSON] = [:]
        if let o = try? JSON(data: Data(contentsOf: dir.appendingPathComponent(name + ".json"))) {
            for (k, v) in o.dict where v.isObject { m[k] = v }
        }
        cache[name] = m
        return m
    }

    func all(_ name: String) -> [JSON] {
        coll(name).sorted { $0.key < $1.key }.map { $0.value }
    }

    func `where`(_ name: String, _ field: String, _ value: String) -> [JSON] {
        all(name).filter { $0.string(field) == value }
    }

    func doc(_ name: String, _ id: String) -> JSON? { coll(name)[id] }

    // MARK: writes

    func put(_ name: String, _ doc0: JSON) {
        var doc = doc0
        doc["updatedAt"] = .num(Results.nowMs())
        let id = doc.string("id")
        var keep = doc
        // a screen may hold an older copy: keep cells another device wrote meanwhile
        if name == Store.results { keep = Results.merge(keep, coll(name)[id]) }
        var m = coll(name)
        m[id] = keep
        cache[name] = m
        persist(name)
        queue(name, id, "put")
        changed()
        push()
    }

    func delete(_ name: String, _ id: String) {
        var m = coll(name)
        m.removeValue(forKey: id)
        cache[name] = m
        persist(name)
        queue(name, id, "del")
        changed()
        push()
    }

    private func queue(_ name: String, _ id: String, _ op: String) {
        outbox.removeAll { $0.string("coll") == name && $0.string("id") == id }
        if sharedOn {
            outbox.append(["coll": .str(name), "id": .str(id), "op": .str(op)])
        }
        saveOutbox()
    }

    private func saveOutbox() { write("_outbox.json", JSON.arr(outbox).data()) }

    private func persist(_ name: String) { write(name + ".json", JSON.obj(coll(name)).data()) }

    private func write(_ file: String, _ data: Data) {
        try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
    }

    // MARK: network

    func push() {
        guard sharedOn else { return }
        Task { await pushNow() }
    }

    func pushNow() async {
        if pushing { return }
        pushing = true
        defer { pushing = false }
        while let job = outbox.first {
            if Prefs.teamId.isEmpty { return }
            let name = job.string("coll"), id = job.string("id")
            do {
                if job.string("op") == "put", var data = coll(name)[id] {
                    if name == Store.results && Results.mergeable(data) { data = try await mergeWithServer(id, data) }
                    let row: JSON = ["team_id": .str(Prefs.teamId), "coll": .str(name), "id": .str(id), "data": data]
                    _ = try await http("POST", "/rest/v1/docs?on_conflict=team_id,coll,id", JSON.arr([row]).text)
                } else {
                    _ = try await http("DELETE", "/rest/v1/docs?team_id=eq." + enc(Prefs.teamId) + "&coll=eq." + enc(name) + "&id=eq." + enc(id), nil)
                }
                outbox.removeAll { $0 == job }
                saveOutbox()
                lastError = nil
            } catch let e as HttpError {
                lastError = e.message
                if e.code >= 400 && e.code < 500 && ![401, 403, 408, 429].contains(e.code) {
                    // this one will never succeed; don't let it block everything behind it
                    outbox.removeAll { $0 == job }
                    saveOutbox()
                    continue
                }
                return
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
    }

    private func mergeWithServer(_ id: String, _ data: JSON) async throws -> JSON {
        let rows = try JSON(string: try await http("GET", "/rest/v1/docs?select=data&team_id=eq." + enc(Prefs.teamId)
            + "&coll=eq." + Store.results + "&id=eq." + enc(id), nil))
        let server = rows.count > 0 ? rows[0]["data"] : JSON.null
        guard server.isObject else { return data }
        // it may have been edited again while we were asking: merge the newest local copy
        let now = coll(Store.results)[id]
        let merged = Results.merge(now ?? data, server)
        if now != nil {
            var m = coll(Store.results)
            m[id] = merged
            cache[Store.results] = m
            persist(Store.results)
            changed()
        }
        return merged
    }

    /// Pushes the outbox, refreshes the profile and team, then pulls. Returns true if anything local changed.
    @discardableResult
    func sync() async -> Bool {
        guard sharedOn, loggedIn, !syncing else { return false }
        syncing = true
        defer { syncing = false }
        await pushNow()
        var changedAny = false
        let coach = Prefs.isCoach
        do {
            let before = Prefs.role + "|" + Prefs.name + "|" + Prefs.teamId
            try await loadProfile()
            if Prefs.teamId.isEmpty || Prefs.teamName.isEmpty {
                do { try await ensureTeam() } catch let e as AuthError { teamError = e.message }
            }
            if before != Prefs.role + "|" + Prefs.name + "|" + Prefs.teamId {
                changedAny = true
                sessionChanged()
            }
            await pushNow()
            if !Prefs.teamId.isEmpty {
                for c in [Store.config, Store.athletes, Store.sessions, Store.results, Store.daily] {
                    let filtered = !coach && (c == Store.results || c == Store.daily)
                    if try await pull(c, filtered ? "athleteId" : nil, Prefs.athleteId) { changedAny = true }
                }
            }
            lastSync = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        if changedAny { changed() }
        return changedAny
    }

    private func pull(_ name: String, _ field: String?, _ value: String) async throws -> Bool {
        let filtered = field != nil
        var q = "/rest/v1/docs?select=id,data&order=id&coll=eq." + enc(name)
        if name == Store.athletes { q = "/rest/v1/profiles?select=id,name&order=id&role=eq.athlete" }
        if let f = field { q += "&" + enc("data->>" + f) + "=eq." + enc(value) }
        var rows: [JSON] = []
        let page = 500
        var offset = 0
        while true {
            let part = try JSON(string: try await http("GET", q + "&limit=\(page)&offset=\(offset)", nil))
            rows.append(contentsOf: part.list)
            if part.count < page { break }
            offset += page
        }
        let m = coll(name)
        var pend = Set<String>()
        for o in outbox where o.string("coll") == name { pend.insert(o.string("id")) }
        var next: [String: JSON] = [:]
        for (k, v) in m {
            let inScope = !filtered || v.string(field!) == value
            if !inScope || pend.contains(k) { next[k] = v }
        }
        for r in rows {
            let id = r.string("id")
            var d = r["data"]
            if name == Store.athletes { d = ["id": .str(id), "name": .str(r.string("name")), "updatedAt": .num(Double(r.string("name").hashValue % 1_000_000))] }
            if d.isObject && !pend.contains(id) { next[id] = d }
        }
        var changed = next.count != m.count
        if !changed {
            for (k, v) in next {
                guard let old = m[k] else { changed = true; break }
                if name == Store.athletes ? old.string("name") != v.string("name") : old.long("updatedAt") != v.long("updatedAt") {
                    changed = true
                    break
                }
            }
        }
        if changed {
            cache[name] = next
            persist(name)
        }
        return changed
    }

    private func http(_ method: String, _ path: String, _ body: String?) async throws -> String {
        if demo { throw URLError(.notConnectedToInternet) }
        try await ensureToken(force: false)
        do {
            return try await httpOnce(method, path, body)
        } catch let e as HttpError {
            if e.code != 401 || Prefs.refreshToken.isEmpty { throw e }
            try await ensureToken(force: true)
            return try await httpOnce(method, path, body)
        }
    }

    private func httpOnce(_ method: String, _ path: String, _ body: String?) async throws -> String {
        var req = URLRequest(url: URL(string: url + path)!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "apikey")
        let token = Prefs.accessToken
        if !token.isEmpty { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let b = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            req.httpBody = Data(b.utf8)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        if code >= 400 { throw HttpError(code: code, message: "Server \(code): " + text) }
        return text
    }

    private func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: demo

    /// Demo data goes straight into the local store, never into the outbox.
    func seedPut(_ name: String, _ doc: JSON) {
        var m = coll(name)
        var d = doc
        d["updatedAt"] = .num(Results.nowMs())
        m[d.string("id")] = d
        cache[name] = m
    }

    func seedDone() {
        for c in [Store.config, Store.athletes, Store.sessions, Store.results, Store.daily] { persist(c) }
        changed()
    }
}

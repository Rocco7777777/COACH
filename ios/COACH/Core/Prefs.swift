import Foundation

/// Small settings kept on the phone (Prefs.java). Same Supabase project as the Android app.
enum Prefs {
    static let serverUrl = "https://bmaqofzrrgslbtcomenm.supabase.co"
    static let serverKey = "sb_publishable_gJse9Z1tu4GBDIipbIHNMw_zN7ErhbV"
    static let privacyUrl = URL(string: "https://rocco7777777.github.io/COACH/privacy.html")!

    private static var d: UserDefaults { .standard }

    private static func s(_ k: String) -> String { d.string(forKey: k) ?? "" }

    static var athleteId: String { s("athleteId") }
    static var email: String { s("email") }
    static var accessToken: String { s("accessToken") }
    static var refreshToken: String { s("refreshToken") }
    static var tokenExpiry: Double { d.double(forKey: "tokenExpiry") }
    static var name: String { s("name") }
    static var role: String { s("role").isEmpty ? "athlete" : s("role") }
    static var isCoach: Bool { role == "coach" }
    static var teamId: String { s("teamId") }
    static var teamName: String { s("teamName") }
    static var teamCoach: String { s("teamCoach") }
    static var joinCode: String { s("joinCode") }

    static var pendingCode: String {
        get { s("pendingCode") }
        set { d.set(newValue, forKey: "pendingCode") }
    }

    static var pendingTeam: String {
        get { s("pendingTeam") }
        set { d.set(newValue, forKey: "pendingTeam") }
    }

    /// The group the coach is looking at (TRENINZI, SPORTAŠI, LJESTVICE, Dolasci).
    static var group: String {
        get { s("group") }
        set { d.set(newValue, forKey: "group") }
    }

    static var demoMode: Bool {
        get { d.bool(forKey: "demoMode") }
        set { d.set(newValue, forKey: "demoMode") }
    }

    /// Tamna tema (Postavke). Stays through a logout: it belongs to the phone, not to the account.
    static var dark: Bool {
        get { d.bool(forKey: "dark") }
        set { d.set(newValue, forKey: "dark") }
    }

    /// Kopiraj trening: the exercises the coach ticked for a changed weight (folded names) and the rounding step in kg.
    /// They belong to the phone, like the theme.
    static var copyTicked: [String] {
        get { d.stringArray(forKey: "copyTicked") ?? [] }
        set { d.set(newValue, forKey: "copyTicked") }
    }

    static var copyStep: Double {
        get { d.double(forKey: "copyStep") }
        set { d.set(newValue, forKey: "copyStep") }
    }

    static var reminderHour: Int {
        get { d.object(forKey: "remH") == nil ? 8 : d.integer(forKey: "remH") }
        set { d.set(newValue, forKey: "remH") }
    }

    static var reminderMinute: Int {
        get { d.integer(forKey: "remM") }
        set { d.set(newValue, forKey: "remM") }
    }

    static func setSession(id: String, email: String, access: String, refresh: String, expiry: Double) {
        d.set(id, forKey: "athleteId")
        d.set(email, forKey: "email")
        d.set(access, forKey: "accessToken")
        d.set(refresh, forKey: "refreshToken")
        d.set(expiry, forKey: "tokenExpiry")
    }

    static func setProfile(name: String, role: String) {
        d.set(name, forKey: "name")
        d.set(role, forKey: "role")
    }

    static func setTeamId(_ id: String) { d.set(id, forKey: "teamId") }

    static func setTeam(name: String, coach: String, code: String) {
        d.set(name, forKey: "teamName")
        d.set(coach, forKey: "teamCoach")
        d.set(code, forKey: "joinCode")
    }

    static func clearSession() {
        for k in ["athleteId", "email", "accessToken", "refreshToken", "tokenExpiry", "name", "role", "teamId", "group",
                  "teamName", "teamCoach", "joinCode", "pendingCode", "pendingTeam"] {
            d.removeObject(forKey: k)
        }
    }
}

import SwiftUI

@MainActor
enum Session {
    static func logout() {
        Prefs.demoMode = false
        Store.shared.wipe()
        Reminders.schedule()
        Reminders.clearDelivered()
    }

    /// Logging out wipes the phone, outbox included: send what's still waiting first.
    static func logoutSafely() {
        let s = Store.shared
        if s.pending == 0 || s.demo { logout(); return }
        Toast.shared.show("Šaljem zadnje promjene…")
        Task {
            await s.pushNow()
            if s.pending == 0 { logout() } else { Nav.shared.unsent = s.pending }
        }
    }
}

/// Account (log out, delete), the dark theme, privacy. Nothing about the server: it syncs by itself.
struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var nav = Nav.shared
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.demo { demoCard } else { accountCard }
                themeCard
                PrivacyLink().padding(.top, 4)
                Text(versionText)
                    .font(C.text(12)).foregroundColor(C.muted).frame(maxWidth: .infinity)
                if let w = waiting {
                    Text(w).font(C.text(12)).foregroundColor(C.muted).frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(C.chalk)
        .navigationTitle("Postavke")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Obrisati račun?", isPresented: $confirmDelete) {
            Button("Obriši zauvijek", role: .destructive) { deleteAccount() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text(Prefs.isCoach
                 ? "Briše se tvoj račun. Ako u timu ima sportaša, tim i treninzi ostaju njima, ali ih više nitko neće moći mijenjati. Prazan tim briše se sa svim treninzima.\n\nOvo se ne može vratiti."
                 : "Brišu se tvoj račun, svi tvoji rezultati s treninga i natjecanja, stari rekordi, trčanja i dnevnik.\n\nOvo se ne može vratiti.")
        }
        .alert("Nije sve poslano", isPresented: Binding(get: { nav.unsent > 0 }, set: { if !$0 { nav.unsent = 0 } })) {
            Button("Ostani prijavljen", role: .cancel) { nav.unsent = 0 }
            Button("Odjavi svejedno", role: .destructive) {
                nav.unsent = 0
                Session.logout()
            }
        } message: {
            Text("Promjena koje još nisu na serveru: \(nav.unsent) (nema interneta?). Ako se sad odjaviš, one se gube.")
        }
    }

    private var demoCard: some View {
        Card {
            Label12("Demo verzija")
            Text("Primjer bez prijave i bez baze. Podaci su izmišljeni i ostaju samo na ovom mobitelu.")
                .font(C.text(15)).foregroundColor(C.ink).padding(.top, 6)
            PillButton(title: Prefs.isCoach ? "Prebaci na sportaša" : "Prebaci na trenera", color: C.sel, fg: C.onSel) { Demo.switchRole() }
                .padding(.top, 12)
            GhostButton(title: "Vrati primjer podatke") { Demo.reset() }.padding(.top, 8)
            GhostButton(title: "Izađi iz dema") { Demo.exit() }.padding(.top, 8)
        }
    }

    private var accountCard: some View {
        Card {
            Label12(Prefs.isCoach ? "Prijavljen kao trener" : "Prijavljen kao sportaš")
            Text(Prefs.name.uppercased()).font(C.display(22)).foregroundColor(C.ink).padding(.top, 6)
            Text(Prefs.email).font(C.text(14)).foregroundColor(C.muted).padding(.top, 2)
            if !Prefs.teamName.isEmpty {
                Text(teamText)
                    .font(C.bold(14)).foregroundColor(C.ink).padding(.top, 6)
            }
            GhostButton(title: "Odjavi se") { Session.logoutSafely() }.padding(.top, 12)
            Button { confirmDelete = true } label: {
                Text(deleting ? "Brišem…" : "Obriši račun").font(C.bold(13)).foregroundColor(C.red)
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var themeCard: some View {
        let dark = Binding<Bool>(get: { nav.dark }, set: { v in
            Prefs.dark = v
            nav.dark = v
        })
        return Card {
            Toggle(isOn: dark) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tamna tema").font(C.bold(16)).foregroundColor(C.ink)
                    Text("Crna pozadina, ugodnije za oči navečer.").font(C.text(13)).foregroundColor(C.muted)
                }
            }
            .tint(C.coral)
        }
    }

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let role = Prefs.isCoach ? "trener" : "sportaš"
        return "COACH \(v) (\(b)) · \(role)"
    }

    private var teamText: String {
        var t = "Tim: " + Prefs.teamName
        if !Prefs.isCoach && !Prefs.teamCoach.isEmpty { t += "  ·  trener " + Prefs.teamCoach }
        return t
    }

    /// Only when something hasn't reached the server yet; it goes by itself once there is a connection.
    private var waiting: String? {
        if store.demo || store.pending == 0 { return nil }
        return "Čeka slanje: \(store.pending). Šalje se samo čim ima interneta."
    }

    private func deleteAccount() {
        deleting = true
        Task {
            do {
                try await store.deleteAccount()
                Toast.shared.show("Račun je obrisan.")
                Session.logout()
            } catch {
                deleting = false
                Toast.shared.show(error.localizedDescription)
            }
        }
    }
}

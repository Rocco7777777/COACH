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

/// Account, reminder time, sync status, privacy, account deletion.
struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var nav = Nav.shared
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var reminder = Calendar.current.date(bySettingHour: Prefs.reminderHour, minute: Prefs.reminderMinute, second: 0, of: Date()) ?? Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.demo {
                    Card {
                        Label12("Demo verzija")
                        Text("Primjer bez prijave i bez baze. Podaci su izmišljeni i ostaju samo na ovom mobitelu.")
                            .font(C.text(15)).foregroundColor(C.carbon).padding(.top, 6)
                        PillButton(title: Prefs.isCoach ? "Prebaci na sportaša" : "Prebaci na trenera", color: C.carbon, fg: .white) { Demo.switchRole() }
                            .padding(.top, 12)
                        GhostButton(title: "Vrati primjer podatke") { Demo.reset() }.padding(.top, 8)
                        GhostButton(title: "Izađi iz dema") { Demo.exit() }.padding(.top, 8)
                    }
                } else {
                    Card {
                        Label12(Prefs.isCoach ? "Prijavljen kao trener" : "Prijavljen kao sportaš")
                        Text(Prefs.name.uppercased()).font(C.display(22)).foregroundColor(C.carbon).padding(.top, 6)
                        Text(Prefs.email).font(C.text(14)).foregroundColor(C.muted).padding(.top, 2)
                        if !Prefs.teamName.isEmpty {
                            Text(teamText)
                                .font(C.bold(14)).foregroundColor(C.carbon).padding(.top, 6)
                        }
                        GhostButton(title: "Odjavi se") { Session.logoutSafely() }.padding(.top, 12)
                        Button { confirmDelete = true } label: {
                            Text(deleting ? "Brišem…" : "Obriši račun").font(C.bold(13)).foregroundColor(C.red)
                                .frame(maxWidth: .infinity).padding(.top, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !Prefs.isCoach {
                    Card {
                        Label12("Jutarnji upitnik")
                        Text(reminderText)
                            .font(C.text(15)).foregroundColor(C.carbon).padding(.top, 6)
                        DatePicker("Vrijeme obavijesti", selection: $reminder, displayedComponents: .hourAndMinute)
                            .font(C.bold(15)).foregroundColor(C.carbon).tint(C.coral)
                            .environment(\.locale, Locale(identifier: "hr_HR"))
                            .padding(.top, 10)
                            .onChange(of: reminder) { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                Prefs.reminderHour = c.hour ?? 8
                                Prefs.reminderMinute = c.minute ?? 0
                                Reminders.schedule()
                                store.changed()
                            }
                        GhostButton(title: "Probna obavijest") {
                            Reminders.askPermission()
                            Reminders.test()
                            Toast.shared.show("Stiže za 3 sekunde")
                        }
                        .padding(.top, 8)
                    }
                }

                if !store.demo {
                    Card {
                        Label12("Zajednička baza")
                        Text(status).font(C.text(15)).foregroundColor(C.carbon).padding(.top, 6)
                        PillButton(title: "Sinkroniziraj sada", color: C.carbon, fg: .white) {
                            Task {
                                await store.sync()
                                Toast.shared.show(store.lastError == nil ? "Sinkronizirano" : "Nema veze sa serverom")
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                PrivacyLink().padding(.top, 4)
                Text(versionText)
                    .font(C.text(12)).foregroundColor(C.muted).frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(C.chalk)
        .navigationTitle("Postavke")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(C.carbon, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Obrisati račun?", isPresented: $confirmDelete) {
            Button("Obriši zauvijek", role: .destructive) { deleteAccount() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text(Prefs.isCoach
                 ? "Briše se tvoj račun. Ako u timu ima sportaša, tim i treninzi ostaju njima, ali ih više nitko neće moći mijenjati. Prazan tim briše se sa svim treninzima.\n\nOvo se ne može vratiti."
                 : "Brišu se tvoj račun, svi tvoji rezultati, stari rekordi, trčanja i dnevnik.\n\nOvo se ne može vratiti.")
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

    private var reminderText: String {
        let m = String(format: "%02d", Prefs.reminderMinute)
        return "Obavijest stiže u \(Prefs.reminderHour):\(m), a ako ga ne ispuniš, podsjeća te svaka 2 sata do 21 h."
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

    private var status: String {
        if let e = store.lastError { return "Nema veze: " + e }
        if store.pending > 0 { return "Čeka slanje: \(store.pending)" }
        return "Spojeno, sve poslano."
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

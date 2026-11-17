import SwiftUI

/// Email + password. Registering, an athlete brings the coach's 6-character code; a coach opens a new team.
struct LoginView: View {
    @State private var register = false
    @State private var coach = false
    @State private var busy = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var code = ""
    @State private var team = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            hero
            form
        }
        .background(C.chalk)
    }

    /// Dark from the very top, like the header of every other screen (the clock and battery are drawn white).
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                TrackLogo(size: 44)
                Text("COACH").font(C.display(40)).foregroundColor(.white)
            }
            Text("Treninzi, prolazi, kilaže, san i suplementi. Sportaši i trener u istoj aplikaciji.")
                .font(C.text(15)).foregroundColor(C.mutedLight).padding(.top, 14)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.header, ignoresSafeAreaEdges: .top)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Chip(title: "Prijava", on: !register) { register = false; error = nil }
                    Chip(title: "Novi račun", on: register) { register = true; error = nil }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if register {
                        HStack(spacing: 8) {
                            Chip(title: "Sportaš", on: !coach) { coach = false; error = nil }
                            Chip(title: "Trener", on: coach) { coach = true; error = nil }
                        }
                        .padding(.top, 4)
                        if coach {
                            Field(label: "Ime tima ili kluba") {
                                TextField("", text: $team).textInputAutocapitalization(.words).input()
                            }
                        } else {
                            Field(label: "Kod tima (dobiješ ga od trenera)") {
                                TextField("ABC234", text: $code)
                                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                    .font(C.display(20)).tracking(4)
                                    .onChange(of: code) { v in
                                        let c = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                                        if c != v { code = c }
                                    }
                                    .input()
                            }
                        }
                        Field(label: "Ime i prezime") {
                            TextField("", text: $name).textInputAutocapitalization(.words).textContentType(.name).input()
                        }
                    }
                    Field(label: "Email") {
                        TextField("", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().textContentType(.username).input()
                    }
                    Field(label: "Lozinka") {
                        SecureField("", text: $password).textContentType(register ? .newPassword : .password).input()
                    }
                }
                .padding(.top, 16)

                if let e = error {
                    Text(e).font(C.bold(14)).foregroundColor(C.red).padding(.top, 12)
                }

                PillButton(title: register ? "Napravi račun" : "Prijavi se", busy: busy) { submit() }
                    .padding(.top, 18)

                Text(register
                     ? (coach ? "Dobit ćeš kod tima koji šalješ sportašima. Tko se upiše s tim kodom, odmah je u tvom timu."
                        : "S kodom ulaziš ravno u trenerov tim. Nemaš kod? Traži ga od trenera.")
                     : "Trener i sportaši koriste istu aplikaciju, svatko sa svojim računom.")
                    .font(C.text(13)).foregroundColor(C.muted).padding(.top, 14)

                GhostButton(title: "Isprobaj demo") { Demo.start() }
                    .padding(.top, 20)
                Text("Izmišljeni tim i treninzi, bez računa. Ništa se ne šalje na server.")
                    .font(C.text(12)).foregroundColor(C.muted).padding(.top, 6)
                PrivacyLink().padding(.top, 10)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() {
        if busy { return }
        if email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || (register && name.trimmingCharacters(in: .whitespaces).count < 2) {
            error = register ? "Upiši ime, email i lozinku." : "Upiši email i lozinku."
            return
        }
        let clean = code.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "")
        if register && !coach && clean.count != 6 { error = "Kod tima ima 6 znakova. Traži ga od trenera."; return }
        if register && coach && team.trimmingCharacters(in: .whitespaces).count < 2 { error = "Upiši ime tima."; return }
        if register {
            Prefs.pendingCode = coach ? "" : clean
            Prefs.pendingTeam = coach ? team.trimmingCharacters(in: .whitespaces) : ""
        }
        busy = true
        error = nil
        hideKeyboard()
        let store = Store.shared
        Task { @MainActor in
            do {
                var p: JSON?
                if register {
                    p = try await store.signUp(email: email, password: password, name: name, joinCode: coach ? "" : clean, teamName: coach ? team : "")
                } else {
                    p = try await store.signIn(email: email, password: password)
                }
                if p != nil {
                    // a wrong code doesn't undo the login: the join screen asks again
                    do { try await store.ensureTeam() } catch { store.teamError = error.localizedDescription }
                }
                busy = false
                if p == nil {
                    register = false
                    error = "Račun je napravljen. Potvrdi email preko linka iz maila, pa se prijavi."
                } else {
                    Reminders.askPermission()
                    store.sessionChanged()
                    Task { await store.sync() }
                }
            } catch {
                busy = false
                self.error = error.localizedDescription
            }
        }
    }
}

struct PrivacyLink: View {
    var body: some View {
        Link(destination: Prefs.privacyUrl) {
            Text("Pravila privatnosti").font(C.bold(13)).foregroundColor(C.blue).underline()
                .frame(maxWidth: .infinity)
        }
    }
}

/// Logged in but in no team yet: enter the coach's code, or open a team as a coach.
struct JoinView: View {
    @State private var code = Prefs.pendingCode
    @State private var team = ""
    @State private var coach = false
    @State private var busy = false
    @State private var error: String? = Store.shared.teamError

    var body: some View {
        VStack(spacing: 0) {
            hero
            form
        }
        .background(C.chalk)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BOK, \(Fmt.firstName(Prefs.name).uppercased())").font(C.display(26)).foregroundColor(.white)
            Text(coach ? "Otvori svoj tim. Dobit ćeš kod koji šalješ sportašima."
                 : "Još nisi u timu. Upiši kod tima i odmah vidiš treninge svog trenera.")
                .font(C.text(15)).foregroundColor(C.mutedLight).padding(.top, 10)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.header, ignoresSafeAreaEdges: .top)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if coach {
                    Field(label: "Ime tima ili kluba") {
                        TextField("npr. AK Mladost sprint", text: $team).textInputAutocapitalization(.words).input()
                    }
                } else {
                    Field(label: "Kod tima") {
                        TextField("ABC234", text: $code)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .font(C.display(26)).tracking(6)
                            .onChange(of: code) { v in
                                let c = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                                if c != v { code = c }
                            }
                            .input(center: true)
                    }
                }
                if let e = error { Text(e).font(C.bold(14)).foregroundColor(C.red).padding(.top, 12) }
                PillButton(title: coach ? "Otvori tim" : "Uđi u tim", busy: busy) { submit() }.padding(.top, 16)
                GhostButton(title: coach ? "Ipak sam sportaš, imam kod" : "Ja sam trener, otvaram novi tim") {
                    coach.toggle()
                    error = nil
                    Store.shared.teamError = nil
                }
                .padding(.top, 10)
                GhostButton(title: "Odjavi se") { Session.logout() }.padding(.top, 24)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() {
        if busy { return }
        let cc = code.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "")
        if !coach && cc.count != 6 { error = "Kod ima 6 znakova."; return }
        if coach && team.trimmingCharacters(in: .whitespaces).count < 2 { error = "Upiši ime tima."; return }
        busy = true
        error = nil
        Store.shared.teamError = nil
        hideKeyboard()
        Task { @MainActor in
            do {
                if coach { try await Store.shared.createTeam(team) } else { try await Store.shared.joinTeam(cc) }
                busy = false
                if Prefs.teamId.isEmpty {
                    error = "Nije uspjelo. Pokušaj ponovno."
                    return
                }
                Toast.shared.show("Sad si u timu " + Prefs.teamName)
                Store.shared.sessionChanged()
                Task { await Store.shared.sync() }
            } catch {
                busy = false
                self.error = error.localizedDescription
            }
        }
    }
}

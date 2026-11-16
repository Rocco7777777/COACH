import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["wellness"] != nil {
            Task { @MainActor in Nav.shared.openWellness = true }
        }
        completionHandler()
    }
}

/// App-wide navigation requests (a tapped notification, screenshot mode).
@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var openWellness = false
    /// Set when a logout would drop changes that never reached the server.
    @Published var unsent = 0
}

/// Screenshot mode for the build machine: `-shot training|session|journal|wellness|progress|board|login|settings`.
enum Shot {
    static var name: String? {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-shot"), i + 1 < a.count { return a[i + 1] }
        return nil
    }
}

@main
@MainActor
struct COACHApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        if let shot = Shot.name {
            if shot == "login" {
                Store.shared.wipe()
                Prefs.demoMode = false
            } else if !Prefs.demoMode {
                Demo.start()
            } else {
                Demo.setUp()
            }
        } else if Prefs.demoMode {
            Demo.setUp()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @ObservedObject var store = Store.shared
    @Environment(\.scenePhase) private var phase
    @State private var timer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            C.chalk.ignoresSafeArea()
            content
                .id(store.sessionVersion)
            ToastOverlay()
        }
        .onChange(of: phase) { p in
            if p == .active { refresh() }
        }
        .onReceive(timer) { _ in
            if phase == .active { Task { await store.sync() } }
        }
        .onAppear { refresh() }
    }

    @ViewBuilder private var content: some View {
        if !store.loggedIn {
            LoginView()
        } else if !store.demo && Prefs.teamId.isEmpty {
            JoinView()
        } else if Prefs.isCoach {
            CoachWaitView()
        } else {
            AthleteHome()
        }
    }

    private func refresh() {
        guard store.loggedIn else { return }
        Reminders.schedule()
        Task {
            await store.sync()
            Reminders.schedule()
        }
    }
}

/// The coach's tools are still Android only.
struct CoachWaitView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(padding: 20, background: C.carbon, border: nil) {
                    TrackLogo(size: 40)
                    Text("BOK, \(Fmt.firstName(Prefs.name).uppercased())").font(C.display(24)).foregroundColor(.white).padding(.top, 12)
                    Text("Trenerski dio (slaganje treninga, Zapisnik, grupe, Excel) na iPhoneu još ne postoji. Za sada ga koristi na Android mobitelu ili tabletu. Sve je u istoj bazi, pa sportaši s iPhoneom vide tvoje treninge.")
                        .font(C.text(15)).foregroundColor(C.mutedLight).padding(.top, 8)
                }
                if !Prefs.joinCode.isEmpty {
                    Card {
                        Label12("Kod tvog tima")
                        Text(Prefs.joinCode).font(C.display(30)).tracking(6).foregroundColor(C.carbon).padding(.top, 6)
                        Text("Sportaši ga upišu kod registracije.").font(C.text(13)).foregroundColor(C.muted).padding(.top, 4)
                    }
                }
                GhostButton(title: "Odjavi se") { Session.logoutSafely() }
            }
            .padding(16)
        }
        .background(C.chalk)
    }
}

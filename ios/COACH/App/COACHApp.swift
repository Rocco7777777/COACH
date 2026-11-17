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
    /// Tamna tema, switched in Postavke.
    @Published var dark = Prefs.dark
}

/// Screenshot mode for the build machine: `-shot training|session|journal|wellness|progress|board|login|settings`,
/// "c-…" for the coach's screens. `-dark YES` shows them in the dark theme (it lands in UserDefaults).
enum Shot {
    static var name: String? {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-shot"), i + 1 < a.count { return a[i + 1] }
        return nil
    }
    /// `-store`: App Store screenshots, without the DEMO tag and the role switch.
    static var store: Bool { ProcessInfo.processInfo.arguments.contains("-store") }
}

@main
@MainActor
struct COACHApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        UINavigationBar.appearance().tintColor = .white
        if let shot = Shot.name {
            if shot == "login" {
                Store.shared.wipe()
                Prefs.demoMode = false
            } else if !Prefs.demoMode {
                Demo.start()
            } else {
                Demo.setUp()
            }
            // "c-…" shots show the demo team through its coach's eyes
            if shot != "login" { Prefs.setProfile(name: Demo.team[0].1, role: shot.hasPrefix("c-") ? "coach" : "athlete") }
        } else if Prefs.demoMode {
            Demo.setUp()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var nav = Nav.shared
    @Environment(\.scenePhase) private var phase
    @State private var timer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            C.chalk.ignoresSafeArea()
            content
                .id(store.sessionVersion)
            ToastOverlay()
        }
        .preferredColorScheme(nav.dark ? .dark : .light)
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
            CoachHome()
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

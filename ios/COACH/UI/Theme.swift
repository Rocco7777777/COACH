import SwiftUI
import UIKit

/// COACH palette and type, same as the Android app (C.java).
/// Colours that sit on the page or on a card follow the theme (Postavke, Tamna tema); the brand colours stay.
enum C {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    // brand, the same in both themes
    static let coral = Color(hex: 0xFF6257)
    static let green = Color(hex: 0x1FA86B)
    /// Blue as a surface under white text.
    static let blueFill = Color(hex: 0x2F5BFF)
    /// Red as a surface under white text.
    static let alarm = Color(hex: 0xC8223A)
    /// Dark text on coral, in both themes.
    static let night = Color(hex: 0x171A1D)
    /// The top bar, dark in both themes.
    static let header = Color(hex: 0x171A1D)
    /// Light grey text on the dark cards.
    static let mutedLight = Color(hex: 0xB9BEC2)

    /// Text and icons on the page and on cards.
    static let ink = dyn(0x171A1D, 0xF2F0EA)
    /// Dark cards that carry white text (this week, plan, team code).
    static let carbon = dyn(0x171A1D, 0x2A2F35)
    static let carbon2 = dyn(0x24282C, 0x3A4047)
    /// The page.
    static let chalk = dyn(0xF7F5F0, 0x0F1113)
    /// Cards, chips and the tab bar.
    static let card = dyn(0xFFFFFF, 0x1A1D21)
    /// Text boxes.
    static let field = dyn(0xFFFFFF, 0x121518)
    /// Small grey surfaces: a place without a medal.
    static let chip = dyn(0xEDEFEE, 0x2A2F35)
    static let stone = dyn(0xD7DBD8, 0x343A40)
    static let muted = dyn(0x6B7075, 0x9BA2A8)
    /// Faint marks: an empty tick, a chevron.
    static let faint = dyn(0xB9BEC2, 0x4A5157)
    /// A chosen chip or day and the text on it: dark on light, light on dark.
    static let sel = dyn(0x171A1D, 0xF2F0EA)
    static let onSel = dyn(0xFFFFFF, 0x171A1D)
    static let onSelDim = dyn(0xB9BEC2, 0x6B7075)
    /// Blue and red as text and lines.
    static let blue = dyn(0x2F5BFF, 0x7C97FF)
    static let red = dyn(0xC8223A, 0xFF6B7A)
    static let coralSoft = dyn(0xFFE3E0, 0x43211E)
    static let blueSoft = dyn(0xE3E9FF, 0x1E2A55)
    static let greenSoft = dyn(0xDDF3E8, 0x12352A)
    /// Dark coral: readable on white, says "set for you".
    static let own = dyn(0xB8392F, 0xFF8A80)

    static func display(_ size: CGFloat) -> Font { .custom("ArchivoBlack-Regular", size: size) }
    static func bold(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func text(_ size: CGFloat) -> Font { .system(size: size) }

    /// Wellness answers 1 to 5, as surfaces under white text.
    static func scale(_ v: Int) -> Color {
        switch v {
        case 1: return alarm
        case 2: return coral
        case 3: return Color(hex: 0x8A9096)
        case 4: return blueFill
        default: return green
        }
    }

    static func pace(_ level: Int) -> Color {
        switch level {
        case 1: return green
        case 2: return coral
        case 3: return red
        default: return ink
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: building blocks

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var background: Color = C.card
    var border: Color? = C.stone
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(border ?? .clear, lineWidth: 1))
    }
}

struct Label12: View {
    let text: String
    var color: Color = C.muted
    init(_ t: String, color: Color = C.muted) { text = t; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundColor(color)
    }
}

struct Tag: View {
    let text: String
    var fg: Color
    var bg: Color
    var body: some View {
        Text(text).font(.system(size: 12, weight: .bold)).foregroundColor(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }
}

struct PillButton: View {
    let title: String
    var color: Color = C.coral
    var fg: Color = C.night
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(fg) }
                Text(title.uppercased()).font(C.display(16)).foregroundColor(fg)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
    }
}

struct GhostButton: View {
    let title: String
    var color: Color = C.ink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(C.bold(15)).foregroundColor(color)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Capsule().stroke(C.stone, lineWidth: 1.2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let title: String
    let on: Bool
    /// A coloured chip with white text; nil = the usual chosen look.
    var onColor: Color? = nil
    let action: () -> Void
    var body: some View {
        let fill: Color = onColor ?? C.sel
        let text: Color = onColor == nil ? C.onSel : .white
        Button(action: action) {
            Text(title).font(C.bold(14)).foregroundColor(on ? text : C.ink)
                .padding(.horizontal, 14).frame(minHeight: 38)
                .background(Capsule().fill(on ? fill : C.card))
                .overlay(Capsule().stroke(on ? fill : C.stone, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }
}

struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label12(label)
            content
        }
    }
}

struct InputStyle: ViewModifier {
    var center = false
    func body(content: Content) -> some View {
        content
            .font(C.bold(16))
            .foregroundColor(C.ink)
            .multilineTextAlignment(center ? .center : .leading)
            .padding(.horizontal, 12).frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(C.field))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(C.stone, lineWidth: 1))
    }
}

extension View {
    func input(center: Bool = false) -> some View { modifier(InputStyle(center: center)) }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// "Gotovo" above number pads (they have no return key).
    func keyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Gotovo") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    .font(C.bold(16))
            }
        }
    }
}

struct EmptyCard: View {
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title.uppercased()).font(C.display(17)).foregroundColor(C.ink)
            Text(text).font(C.text(14)).foregroundColor(C.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 14).stroke(C.stone, style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
    }
}

/// The COACH mark: three coral lanes of a track.
struct TrackLogo: View {
    var size: CGFloat = 40
    var color: Color = C.coral
    var body: some View {
        ZStack {
            ForEach([19.9, 13.7, 7.5], id: \.self) { r in
                RoundedRectangle(cornerRadius: r * size / 44)
                    .stroke(color, lineWidth: 4.2 * size / 44)
                    .frame(width: r * 2 * size / 44, height: (r * 2 + 16) * size / 44)
            }
        }
        .frame(width: size, height: size * 1.2)
    }
}

/// Small toast at the bottom of the screen.
@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published var text: String?
    private var task: Task<Void, Never>?

    func show(_ t: String) {
        text = t
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { text = nil }
        }
    }
}

struct ToastOverlay: View {
    @ObservedObject var toast = Toast.shared
    var body: some View {
        VStack {
            Spacer()
            if let t = toast.text {
                Text(t).font(C.bold(14)).foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(C.carbon))
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: toast.text)
        .allowsHitTesting(false)
    }
}

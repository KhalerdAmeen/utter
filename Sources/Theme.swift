import AppKit
import AVFoundation
import SwiftUI

enum Theme {
    // Brand: near-black + signal orange, same as the icon and the website
    static let accent = Color(red: 1.0, green: 0.38, blue: 0.16)      // #FF6129
    static let record = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let success = Color(red: 0.24, green: 0.80, blue: 0.48)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.20)
    static let pill = Color(red: 0.07, green: 0.07, blue: 0.08)

    static let bg = Color(red: 0.055, green: 0.055, blue: 0.063)        // window
    static let sidebar = Color(red: 0.075, green: 0.075, blue: 0.083)   // sidebar
    static let surface = Color(red: 0.098, green: 0.098, blue: 0.110)   // cards
    static let surfaceHi = Color(red: 0.125, green: 0.125, blue: 0.140) // top of card gradient
    static let cardFill = surface
    static let hairline = Color.white.opacity(0.07)
    static let textDim = Color.white.opacity(0.55)
    static let accentSoft = accent.opacity(0.14)

    // Icon tile colours for settings rows (System Settings style, toned for dark)
    static let blue = Color(red: 0.26, green: 0.52, blue: 0.98)
    static let purple = Color(red: 0.58, green: 0.40, blue: 0.95)
    static let green = Color(red: 0.20, green: 0.72, blue: 0.45)
    static let pink = Color(red: 0.95, green: 0.35, blue: 0.55)
    static let gray = Color(red: 0.45, green: 0.45, blue: 0.50)
    static let teal = Color(red: 0.18, green: 0.70, blue: 0.78)
}

// MARK: - Layout building blocks

struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .tracking(-0.6)
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                content.padding(.top, 10)
            }
            .padding(.horizontal, 36)
            .padding(.top, 52)
            .padding(.bottom, 40)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            ZStack(alignment: .topTrailing) {
                Theme.bg
                // the soft orange glow from the website
                RadialGradient(colors: [Theme.accent.opacity(0.13), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 460)
            }
            .ignoresSafeArea()
        )
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5)
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Theme.textDim)
        }
        .padding(.top, 26)
        .padding(.bottom, 10)
    }
}

struct Card<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    init(padding: CGFloat = 16, @ViewBuilder _ content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, padding)
            .padding(.vertical, padding > 0 ? 4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground())
    }
}

/// Raised dark surface: subtle top-lit gradient, hairline border, soft shadow.
struct CardBackground: View {
    var radius: CGFloat = 14
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [Theme.surfaceHi, Theme.surface], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
    }
}

/// Coloured rounded-square icon, like macOS System Settings.
struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color.white)
            )
            .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
    }
}

/// A physical-looking key, e.g. ⌥ or ⇧.
struct Keycap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.17), Color.white.opacity(0.07)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.55), radius: 0, y: 1.5)
    }
}

/// Keys joined with small plus signs: ⇧ + ⌥
struct KeyCombo: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { pair in
                if pair.offset > 0 {
                    Text("+").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textDim)
                }
                Keycap(label: pair.element)
            }
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Theme.accent
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                IconTile(symbol: icon, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 11)
    }
}

/// Wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60) min" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

// MARK: - Audio playback for History

@MainActor
final class PlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingID: UUID?
    private var player: AVAudioPlayer?

    func toggle(_ id: UUID, url: URL) {
        if playingID == id {
            player?.stop()
            playingID = nil
            return
        }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        playingID = (player?.play() == true) ? id : nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playingID = nil }
    }
}

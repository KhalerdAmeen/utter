import AppKit
import SwiftUI

// The floating pill at the bottom of the screen.

enum OverlayState: Equatable {
    case listening(handsFree: Bool, command: Bool)
    case processing(String)
    case success(String)
    case message(String)
    case error(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    static let barCount = 26
    @Published var state: OverlayState = .message("")
    @Published var levels: [CGFloat] = Array(repeating: 0, count: OverlayModel.barCount)
    @Published var startedAt = Date()

    func push(_ level: Float) {
        var next = levels
        next.removeFirst()
        next.append(CGFloat(pow(Double(level), 0.75)))
        levels = next
    }
}

@MainActor
final class Overlay {
    private let model = OverlayModel()
    private var hideToken = 0
    private let size = NSSize(width: 480, height: 96)

    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        return p
    }()

    func listening(handsFree: Bool, command: Bool) {
        if case .listening = model.state, panel.isVisible {
            // keep timer + waveform running
        } else {
            model.levels = Array(repeating: 0, count: OverlayModel.barCount)
            model.startedAt = Date()
        }
        present(.listening(handsFree: handsFree, command: command), autoHide: nil)
    }

    func level(_ l: Float) { model.push(l) }
    func processing(_ text: String) { present(.processing(text), autoHide: nil) }
    func success(_ text: String, seconds: Double = 0.9) { present(.success(text), autoHide: seconds) }
    func message(_ text: String, seconds: Double = 2.2) { present(.message(text), autoHide: seconds) }
    func error(_ text: String, seconds: Double = 3.5) { present(.error(text), autoHide: seconds) }

    func hide() {
        hideToken += 1
        panel.orderOut(nil)
    }

    private func present(_ state: OverlayState, autoHide: Double?) {
        hideToken += 1
        let token = hideToken
        model.state = state
        if !panel.isVisible { position() }
        panel.orderFrontRegardless()
        if let autoHide {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHide) { [weak self] in
                guard let self, self.hideToken == token else { return }
                self.hide()
            }
        }
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 20))
    }
}

@MainActor
struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack {
            Spacer()
            pill
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 16)
        .environment(\.colorScheme, .dark)
    }

    private var pill: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(Theme.pill.opacity(0.96)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.state)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .listening(let handsFree, let command):
            if command {
                Text("EDIT")
                    .font(.system(size: 9.5, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.pill)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent))
            }
            PulsingDot()
            Waveform(levels: model.levels)
            TimelineView(.periodic(from: model.startedAt, by: 1)) { ctx in
                Text(elapsed(ctx.date))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            if handsFree {
                Text("tap to finish")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        case .processing(let text):
            ThinkingDots()
            label(text)
        case .success(let text):
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.success)
            label(text)
        case .message(let text):
            label(text)
        case .error(let text):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
            label(text)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.white)
            .lineLimit(1)
    }

    private func elapsed(_ now: Date) -> String {
        let s = Int(max(0, now.timeIntervalSince(model.startedAt)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct Waveform: View {
    let levels: [CGFloat]
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { pair in
                Capsule()
                    .fill(Color.white.opacity(0.35 + 0.65 * Double(pair.element)))
                    .frame(width: 2.5, height: max(3, 22 * pair.element))
            }
        }
        .frame(height: 22)
        .animation(.linear(duration: 0.05), value: levels)
    }
}

struct PulsingDot: View {
    @State private var dim = false
    var body: some View {
        Circle()
            .fill(Theme.record)
            .frame(width: 8, height: 8)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 6 - Double(i) * 0.9)))
                }
            }
        }
    }
}

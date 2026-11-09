import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Tone per kind of app

enum Tone: String, CaseIterable, Identifiable, Codable {
    case formal, casual, veryCasual
    var id: String { rawValue }

    var label: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .veryCasual: return "Very casual"
        }
    }

    var instruction: String {
        switch self {
        case .formal:
            return "Tone: formal. Polished, professional writing with full sentences, proper capitalization and punctuation. No slang."
        case .casual:
            return "Tone: casual. Natural and friendly, with proper capitalization and punctuation. Contractions are fine; keep their phrasing."
        case .veryCasual:
            return "Tone: very casual, like texting a friend. Lowercase is fine, light punctuation, no period at the end of a single sentence. Keep slang. Do not abbreviate words they said in full."
        }
    }

    var example: String {
        switch self {
        case .formal: return "Hi Sam, are you free to meet tomorrow at 4 p.m.? Please let me know."
        case .casual: return "Hey Sam, are you free to meet tomorrow at 4? Let me know."
        case .veryCasual: return "hey sam you free to meet tomorrow at 4? let me know"
        }
    }
}

enum AppCategory: String, CaseIterable, Identifiable {
    case ai, messages, email, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "AI & coding tools"
        case .messages: return "Messages"
        case .email: return "Email"
        case .other: return "Everything else"
        }
    }

    var subtitle: String {
        switch self {
        case .ai: return "Claude, ChatGPT, Cursor, VS Code, Terminal, Warp, Xcode"
        case .messages: return "Slack, WhatsApp, iMessage, Telegram, Discord"
        case .email: return "Mail, Outlook, Superhuman, Spark"
        case .other: return "Notes, docs, browsers and every other app"
        }
    }

    var defaultTone: Tone {
        switch self {
        case .email: return .formal
        default: return .casual
        }
    }

    func context(appName: String) -> String {
        switch self {
        case .ai:
            return "The user is writing a prompt or instructions for an AI assistant or coding agent in \(appName). Preserve technical terms, file names, function names, CLI commands, URLs and numbers exactly. Use a numbered list when they describe multiple steps or requirements."
        case .messages:
            return "The user is sending a chat message in \(appName). No greeting or sign-off unless they said one."
        case .email:
            return "The user is writing an email in \(appName). Use proper paragraphs. Do not add a greeting or sign-off they did not say."
        case .other:
            return "The user is typing into \(appName.isEmpty ? "an app" : appName)."
        }
    }

    private static let aiApps: Set<String> = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.dt.Xcode",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "com.anthropic.claudefordesktop", "com.openai.chat", "com.exafunction.windsurf",
    ]
    private static let messageApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "com.apple.MobileSMS",
        "ru.keepcoder.Telegram", "com.hnc.Discord", "com.facebook.archon",
    ]
    private static let emailApps: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.superhuman.electron", "com.readdle.smartemail-Mac",
    ]

    static func of(bundleID: String) -> AppCategory {
        if aiApps.contains(bundleID) { return .ai }
        if messageApps.contains(bundleID) { return .messages }
        if emailApps.contains(bundleID) { return .email }
        return .other
    }
}

// MARK: - Snippets (voice shortcuts)

struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var text: String
}

// MARK: - Reading the selected text (for command mode)

@MainActor
enum SelectionReader {
    /// Works in native apps (Notes, Mail, Xcode, most text fields).
    static func accessibilitySelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused else { return nil }
        let element = focusedRef as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String,
              !text.isEmpty else { return nil }
        return text
    }

    /// The text already in the box you're typing into (last ~1200 characters).
    /// Used only to spell names/terms correctly. Password fields don't expose this.
    static func focusedFieldText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused else { return nil }
        let element = focusedRef as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.suffix(1200))
    }

    /// Fallback for browsers/Electron apps: press ⌘C, read it, put the old clipboard back.
    static func copySelection() async -> String? {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 180_000_000)
        guard pb.changeCount != before, let text = pb.string(forType: .string), !text.isEmpty else { return nil }
        if !saved.isEmpty {
            pb.clearContents()
            pb.writeObjects(saved)
        }
        return text
    }
}

// MARK: - Snippets page

@MainActor
struct SnippetsPage: View {
    @ObservedObject var settings: AppSettings
    @State private var trigger = ""
    @State private var text = ""

    var body: some View {
        Page(title: "Snippets", subtitle: "Say a short phrase, get the full text. Great for links, addresses, sign-offs and prompts you reuse.") {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("When I say…   e.g. “my calendly”", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                    TextField("…type this   e.g. https://calendly.com/you", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...6)
                    HStack {
                        Text("Works on its own (“my calendly”) or mid-sentence (“send them my calendly”).")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Add snippet", action: add)
                            .keyboardShortcut(.defaultAction)
                            .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.top, 16)

            SectionLabel("\(settings.snippets.count) snippet\(settings.snippets.count == 1 ? "" : "s")")

            if settings.snippets.isEmpty {
                Text("No snippets yet.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(settings.snippets) { s in
                        SnippetRow(snippet: binding(s.id)) {
                            settings.snippets.removeAll { $0.id == s.id }
                        }
                    }
                }
            }
        }
    }

    private func binding(_ id: UUID) -> Binding<Snippet> {
        Binding(
            get: { settings.snippets.first { $0.id == id } ?? Snippet(trigger: "", text: "") },
            set: { new in
                if let i = settings.snippets.firstIndex(where: { $0.id == id }) { settings.snippets[i] = new }
            })
    }

    private func add() {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let x = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !x.isEmpty else { return }
        settings.snippets.insert(Snippet(trigger: t, text: x), at: 0)
        trigger = ""
        text = ""
    }
}

struct SnippetRow: View {
    @Binding var snippet: Snippet
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("SAY").font(.system(size: 9.5, weight: .bold)).tracking(0.6).foregroundStyle(Theme.accent)
                    TextField("", text: $snippet.trigger)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("TYPE").font(.system(size: 9.5, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                    TextField("", text: $snippet.text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ChipButton(icon: "trash", title: nil, action: onDelete)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Style page

@MainActor
struct StylePage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Page(title: "Style", subtitle: "Choose how you sound in each kind of app. Utter detects which app you're typing into.") {
            ForEach(AppCategory.allCases) { category in
                SectionLabel(category.title)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(category.subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.tone(for: category) },
                                set: { settings.setTone($0, for: category) })) {
                                ForEach(Tone.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 280)
                        }
                        Text(settings.tone(for: category).example)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }
                    .padding(.vertical, 14)
                }
            }
        }
    }
}

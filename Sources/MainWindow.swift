import AppKit
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, history, dictionary, snippets, style, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .style: return "textformat"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class MainModel: ObservableObject {
    @Published var tab: Tab = .home
}

struct AppActions {
    let retry: (UUID) -> Void
    let retryAll: () -> Void
}

// MARK: - Shell

struct MainView: View {
    @ObservedObject var nav: MainModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: HistoryStore
    let actions: AppActions

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(nav: nav, settings: settings, store: store)
                .frame(width: 200)
            Divider()
            Group {
                switch nav.tab {
                case .home: HomePage(nav: nav, settings: settings, store: store, actions: actions)
                case .history: HistoryPage(store: store, actions: actions)
                case .dictionary: DictionaryPage(settings: settings)
                case .snippets: SnippetsPage(settings: settings)
                case .style: StylePage(settings: settings)
                case .settings: SettingsPage(settings: settings, store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 520)
        .ignoresSafeArea()
    }
}

struct Sidebar: View {
    @ObservedObject var nav: MainModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                Text("Utter").font(.system(size: 15, weight: .semibold))
            }
            .padding(.leading, 8)
            .padding(.top, 48)
            .padding(.bottom, 20)

            ForEach(Tab.allCases) { tab in
                SidebarButton(tab: tab, selected: nav.tab == tab,
                              badge: tab == .history && store.failedCount > 0 ? store.failedCount : nil) {
                    nav.tab = tab
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hold \(settings.hotkey.short)")
                        .font(.system(size: 12, weight: .semibold))
                    Text("to dictate anywhere")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("⇧ Shift + \(settings.hotkey.short)")
                        .font(.system(size: 12, weight: .semibold))
                    Text("to edit selected text")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .sidebar))
    }
}

struct SidebarButton: View {
    let tab: Tab
    let selected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
                Text(tab.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.warning))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.08 : (hovering ? 0.04 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Home

@MainActor
struct HomePage: View {
    @ObservedObject var nav: MainModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: HistoryStore
    let actions: AppActions
    @StateObject private var player = PlayerModel()

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? part : "\(part), \(first)"
    }

    var body: some View {
        Page(title: greeting, subtitle: "Hold \(settings.hotkey.label) in any app and just talk. Quick tap for hands-free. Select text and hold Shift too to rewrite it by voice.") {
            VStack(spacing: 10) {
                if settings.apiKey.isEmpty {
                    Banner(icon: "key.fill", text: "Add your Groq API key to start dictating.", button: "Open Settings") { nav.tab = .settings }
                }
                if !Permissions.accessibilityGranted {
                    Banner(icon: "hand.raised.fill", text: "Turn on Accessibility so Utter can paste for you.", button: "Grant") { Permissions.openAccessibilitySettings() }
                }
                if store.failedCount > 0 {
                    Banner(icon: "arrow.clockwise", text: "\(store.failedCount) dictation\(store.failedCount == 1 ? "" : "s") didn't go through. Audio is saved.", button: "Retry all") { actions.retryAll() }
                }
            }
            .padding(.top, 14)

            HStack(spacing: 12) {
                StatCard(value: "\(store.totalWords)", label: "words dictated")
                StatCard(value: "\(store.items.count)", label: "dictations")
                StatCard(value: formatDuration(store.timeSavedSeconds), label: "saved vs typing")
            }
            .padding(.top, 14)

            HStack {
                SectionLabel("Recent")
                Spacer()
                if store.items.count > 4 {
                    Button("See all") { nav.tab = .history }
                        .buttonStyle(.link).font(.system(size: 12))
                        .padding(.top, 14)
                }
            }

            if store.items.isEmpty {
                Card {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform").font(.system(size: 26)).foregroundStyle(Theme.accent)
                        Text("Your dictations will show up here").font(.system(size: 13, weight: .medium))
                        Text("Try it now — click into any text box and hold \(settings.hotkey.short).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(store.items.prefix(4)) { item in
                        DictationCard(item: item, store: store, player: player, onRetry: actions.retry)
                    }
                }
            }
        }
    }
}

struct Banner: View {
    let icon: String
    let text: String
    let button: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.warning)
            Text(text).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warning.opacity(0.3)))
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - History

@MainActor
struct HistoryPage: View {
    @ObservedObject var store: HistoryStore
    let actions: AppActions
    @StateObject private var player = PlayerModel()
    @State private var query = ""

    private var filtered: [Dictation] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter {
            ($0.clean ?? "").localizedCaseInsensitiveContains(query)
                || ($0.raw ?? "").localizedCaseInsensitiveContains(query)
                || $0.appName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Page(title: "History", subtitle: "Every dictation with its audio. Play it back, copy it, or re-run it.") {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
                if store.failedCount > 0 {
                    Button("Retry \(store.failedCount) failed") { actions.retryAll() }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 14)

            if filtered.isEmpty {
                Text(store.items.isEmpty ? "Nothing yet — your dictations will appear here." : "No matches.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { item in
                        DictationCard(item: item, store: store, player: player, onRetry: actions.retry)
                    }
                }
            }
        }
    }
}

@MainActor
struct DictationCard: View {
    let item: Dictation
    let store: HistoryStore
    @ObservedObject var player: PlayerModel
    let onRetry: (UUID) -> Void
    @State private var showRaw = false
    @State private var copied = false
    @State private var showAddWord = false
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if item.isCommand {
                    Text("EDIT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.accent))
                }
                Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                dot
                Text(item.appName)
                dot
                Text(formatDuration(item.duration))
                if let ms = item.processingMs {
                    dot
                    Text(String(format: "%.1fs to process", Double(ms) / 1000))
                }
                if let models = modelsLabel {
                    dot
                    Text(models).help("Models used for this dictation")
                }
                Spacer()
                statusBadge
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Group {
                if let clean = item.clean, !clean.isEmpty {
                    Text(clean).font(.system(size: 13.5)).lineSpacing(2).textSelection(.enabled)
                } else if item.status == .failed {
                    Text(item.error ?? "Failed").font(.system(size: 12.5)).foregroundStyle(Theme.record)
                } else if item.status == .processing {
                    Text("Transcribing…").foregroundStyle(.secondary)
                } else {
                    Text("No speech detected").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.isCommand, let instruction = item.raw {
                Text("You said: “\(instruction)”")
                    .font(.system(size: 11.5)).italic().foregroundStyle(.secondary)
            }

            if let cleanupError = item.cleanupError {
                Text("Cleanup failed, so this is the raw text: \(cleanupError)")
                    .font(.system(size: 11)).foregroundStyle(Theme.warning)
            }

            if showRaw, let raw = item.isCommand ? item.sourceText : item.raw {
                Text(raw)
                    .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            HStack(spacing: 4) {
                if let clean = item.clean, !clean.isEmpty {
                    ChipButton(icon: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy") {
                        Paster.copy(clean)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                }
                ChipButton(icon: player.playingID == item.id ? "stop.fill" : "play.fill",
                           title: player.playingID == item.id ? "Stop" : "Play") {
                    player.toggle(item.id, url: store.audioURL(for: item))
                }
                ChipButton(icon: "arrow.clockwise", title: item.status == .failed ? "Retry" : "Re-run") {
                    onRetry(item.id)
                }
                .disabled(item.status == .processing)
                if item.isCommand {
                    if item.sourceText != nil {
                        ChipButton(icon: "text.alignleft", title: showRaw ? "Hide original" : "Original") { showRaw.toggle() }
                    }
                } else if let raw = item.raw, raw != item.clean {
                    ChipButton(icon: "text.alignleft", title: showRaw ? "Hide raw" : "Raw") { showRaw.toggle() }
                }
                if !item.isCommand {
                    ChipButton(icon: "character.book.closed", title: "Add word") { showAddWord = true }
                        .popover(isPresented: $showAddWord, arrowEdge: .bottom) { addWordPopover }
                }
                Spacer()
                ChipButton(icon: "folder", title: nil) {
                    NSWorkspace.shared.activateFileViewerSelecting([store.audioURL(for: item)])
                }
                ChipButton(icon: "trash", title: nil) { store.delete(item.id) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(item.status == .failed ? Theme.record.opacity(0.35) : Theme.hairline))
    }

    private var dot: some View { Text("·") }

    /// "whisper-large-v3 + gpt-oss-120b"
    private var modelsLabel: String? {
        guard let stt = item.sttModel else { return nil }
        let short: (String) -> String = { $0.split(separator: "/").last.map(String.init) ?? $0 }
        if let llm = item.llmModel { return "\(short(stt)) + \(short(llm))" }
        return short(stt)
    }

    private var addWordPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add to dictionary").font(.system(size: 13, weight: .semibold))
            Text("Type a name or word the way it should be spelled.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            TextField("e.g. Sam", text: $newWord)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { addWord(rerun: true) }
            HStack {
                Button("Add") { addWord(rerun: false) }
                Spacer()
                Button("Add & re-run") { addWord(rerun: true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func addWord(rerun: Bool) {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let settings = AppSettings.shared
        var list = settings.vocabularyList
        if !list.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) { list.append(word) }
        settings.setVocabulary(list)
        newWord = ""
        showAddWord = false
        if rerun { onRetry(item.id) }
    }

    @ViewBuilder private var statusBadge: some View {
        switch item.status {
        case .failed:
            Text("FAILED").font(.system(size: 9.5, weight: .bold)).tracking(0.5).foregroundStyle(Theme.record)
        case .processing:
            ProgressView().controlSize(.mini)
        case .done:
            EmptyView()
        }
    }
}

struct ChipButton: View {
    let icon: String
    let title: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                if let title { Text(title).font(.system(size: 11.5, weight: .medium)) }
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(hovering ? 0.09 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .onHover { hovering = $0 }
    }
}

// MARK: - Dictionary

@MainActor
struct DictionaryPage: View {
    @ObservedObject var settings: AppSettings
    @State private var newWord = ""

    var body: some View {
        Page(title: "Dictionary", subtitle: "Names, brands and jargon Utter should always spell right. Add anyone it keeps mishearing.") {
            HStack(spacing: 8) {
                TextField("Add a word or name — e.g. Sam, Khadstudio, Supabase", text: $newWord)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
                    .onSubmit(add)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 16)

            SectionLabel("\(settings.vocabularyList.count) words")

            if settings.vocabularyList.isEmpty {
                Text("No words yet.").foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(settings.vocabularyList, id: \.self) { word in
                        HStack(spacing: 6) {
                            Text(word).font(.system(size: 12.5, weight: .medium))
                            Button {
                                settings.setVocabulary(settings.vocabularyList.filter { $0 != word })
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.cardFill))
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                    }
                }
            }
        }
    }

    private func add() {
        let parts = newWord.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        var list = settings.vocabularyList
        for p in parts where !list.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) { list.append(p) }
        settings.setVocabulary(list)
        newWord = ""
    }
}

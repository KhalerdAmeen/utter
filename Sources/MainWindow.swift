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
                .frame(width: 216)
            Rectangle().fill(Theme.hairline).frame(width: 1)
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
            .background(Theme.bg)
        }
        .frame(minWidth: 780, minHeight: 540)
        .tint(Theme.accent)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}

struct Sidebar: View {
    @ObservedObject var nav: MainModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tellr").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white)
                    Text("Just talk.").font(.system(size: 11, design: .serif)).italic().foregroundStyle(Theme.textDim)
                }
            }
            .padding(.leading, 8)
            .padding(.top, 50)
            .padding(.bottom, 22)

            ForEach(Tab.allCases) { tab in
                SidebarButton(tab: tab, selected: nav.tab == tab,
                              badge: tab == .history && store.failedCount > 0 ? store.failedCount : nil) {
                    nav.tab = tab
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                ShortcutHint(keys: [settings.hotkey.keycap], text: "Hold to dictate")
                ShortcutHint(keys: ["⇧", settings.hotkey.keycap], text: "Rewrite selection")
                ShortcutHint(keys: ["⌃", settings.hotkey.keycap],
                             text: "Translate → \(LanguageOption.name(for: settings.quickTranslateLanguage))")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
            )
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }
}

struct ShortcutHint: View {
    let keys: [String]
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            KeyCombo(keys: keys)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
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
                    .foregroundStyle(selected ? Theme.accent : Theme.textDim)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.75))
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Theme.pill)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.warning))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.accent.opacity(0.20), Theme.accent.opacity(0.08)],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.white.opacity(hovering ? 0.05 : 0)))
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Theme.accent).frame(width: 3, height: 16).offset(x: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
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
        Page(title: greeting, subtitle: "Talk in any app. Tellr writes it, cleans it up, and pastes it where your cursor is.") {
            HeroCard(settings: settings)
                .padding(.top, 18)

            VStack(spacing: 10) {
                if settings.apiKey.isEmpty {
                    Banner(icon: "key.fill", text: "Add your Groq API key to start dictating.", button: "Open Settings") { nav.tab = .settings }
                }
                if !Permissions.accessibilityGranted {
                    Banner(icon: "hand.raised.fill", text: "Turn on Accessibility so Tellr can paste for you.", button: "Grant") { Permissions.openAccessibilitySettings() }
                }
                if store.failedCount > 0 {
                    Banner(icon: "arrow.clockwise", text: "\(store.failedCount) dictation\(store.failedCount == 1 ? "" : "s") didn't go through. Audio is saved.", button: "Retry all") { actions.retryAll() }
                }
            }
            .padding(.top, 14)

            HStack(spacing: 12) {
                StatCard(icon: "text.word.spacing", tint: Theme.accent, value: "\(store.totalWords)", label: "words dictated")
                StatCard(icon: "waveform", tint: Theme.purple, value: "\(store.items.count)", label: "dictations")
                StatCard(icon: "bolt.fill", tint: Theme.green, value: formatDuration(store.timeSavedSeconds), label: "saved vs typing")
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
        HStack(spacing: 12) {
            IconTile(symbol: icon, tint: Theme.warning, size: 26)
            Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warning.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warning.opacity(0.28)))
    }
}

/// The "how to use it" card at the top of Home, with keycaps.
struct HeroCard: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("Hold").font(.system(size: 22, design: .serif)).foregroundStyle(Color.white)
                    BigKeycap(label: settings.hotkey.keycap, caption: settings.hotkey == .fn ? "" : "right")
                    Text("and talk.").font(.system(size: 22, design: .serif)).foregroundStyle(Color.white)
                }
                HStack(spacing: 18) {
                    ShortcutHint(keys: ["⇧", settings.hotkey.keycap], text: "rewrite selection")
                    ShortcutHint(keys: ["⌃", settings.hotkey.keycap],
                                 text: "translate → \(LanguageOption.name(for: settings.quickTranslateLanguage))")
                }
            }
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 68, height: 68)
                .shadow(color: Theme.accent.opacity(0.45), radius: 18)
        }
        .padding(22)
        .background(
            ZStack {
                CardBackground(radius: 16)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.22), .clear],
                                         center: .trailing, startRadius: 0, endRadius: 260))
            }
        )
    }
}

struct BigKeycap: View {
    let label: String
    var caption: String = ""
    var body: some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 17, weight: .semibold, design: .rounded))
            if !caption.isEmpty {
                Text(caption).font(.system(size: 8.5, weight: .medium)).foregroundStyle(Theme.textDim)
            }
        }
        .foregroundStyle(Color.white)
        .frame(width: 46, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.20), Color.white.opacity(0.07)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.16)))
        .shadow(color: .black.opacity(0.6), radius: 0, y: 2.5)
        .shadow(color: Theme.accent.opacity(0.25), radius: 10)
    }
}

struct StatCard: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: icon, tint: tint, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
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
                Group {
                    Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    dot
                    Text(item.appName)
                }
                dot
                Text(formatDuration(item.duration))
                if let lang = languageLabel {
                    dot
                    Text(lang).foregroundStyle(item.targetLanguage == nil ? Color.secondary : Theme.accent)
                }
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
        .padding(16)
        .background(CardBackground())
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(item.status == .failed ? Theme.record.opacity(0.45) : Color.clear))
    }

    private var dot: some View { Text("·") }

    /// "whisper-large-v3 + gpt-oss-120b"
    /// "Arabic → English" when translated, or the spoken language when it wasn't English.
    private var languageLabel: String? {
        let heard: String? = item.detectedLanguage.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        if let code = item.targetLanguage, !code.isEmpty {
            let to = LanguageOption.name(for: code)
            if let heard, heard.lowercased() != to.lowercased() { return "\(heard) → \(to)" }
            return "→ \(to)"
        }
        if let heard, heard.lowercased() != "english" { return heard }
        return nil
    }

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
        Page(title: "Dictionary", subtitle: "Names, brands and jargon Tellr should always spell right. Add anyone it keeps mishearing.") {
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

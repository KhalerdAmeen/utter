import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Languages Whisper can hear and the writing model can write.
struct LanguageOption: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [LanguageOption] = pairs.map { LanguageOption(code: $0.0, name: $0.1) }

    private static let pairs: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("pt", "Portuguese"),
        ("it", "Italian"), ("nl", "Dutch"), ("ar", "Arabic"), ("zh", "Chinese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("hi", "Hindi"), ("ur", "Urdu"), ("bn", "Bengali"), ("ru", "Russian"),
        ("uk", "Ukrainian"), ("pl", "Polish"), ("tr", "Turkish"), ("fa", "Persian"), ("he", "Hebrew"),
        ("el", "Greek"), ("sv", "Swedish"), ("id", "Indonesian"), ("ms", "Malay"), ("vi", "Vietnamese"),
        ("th", "Thai"), ("sw", "Swahili"), ("yo", "Yoruba"), ("ha", "Hausa"), ("tl", "Tagalog"),
    ]

    static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code.uppercased()
    }
}

extension Notification.Name {
    static let tellrDockPreferenceChanged = Notification.Name("tellrDockPreferenceChanged")
}

enum Hotkey: String, CaseIterable, Identifiable {
    case rightOption, fn, rightCommand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightOption: return "Right Option ⌥"
        case .fn: return "Fn / Globe 🌐"
        case .rightCommand: return "Right Command ⌘"
        }
    }

    var short: String {
        switch self {
        case .rightOption: return "Right ⌥"
        case .fn: return "Fn 🌐"
        case .rightCommand: return "Right ⌘"
        }
    }

    /// The symbol shown on a keycap.
    var keycap: String {
        switch self {
        case .rightOption: return "⌥"
        case .fn: return "fn"
        case .rightCommand: return "⌘"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .fn: return 63
        case .rightCommand: return 54
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .fn: return .function
        case .rightCommand: return .command
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    static let defaultBaseURL = "https://api.groq.com/openai/v1"
    static let defaultSTT = "whisper-large-v3"   // full model: more accurate than turbo, still fast on Groq

    static let sttPresets: [ModelPreset] = [
        ModelPreset(id: "whisper-large-v3", name: "Whisper Large v3", note: "most accurate"),
        ModelPreset(id: "whisper-large-v3-turbo", name: "Whisper v3 Turbo", note: "fastest"),
    ]
    static let llmPresets: [ModelPreset] = [
        ModelPreset(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B", note: "best quality"),
        ModelPreset(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B", note: "fastest"),
        ModelPreset(id: "qwen/qwen3.8-27b", name: "Qwen 3.8 27B", note: "preview"),
    ]
    static let defaultLLM = "openai/gpt-oss-120b"
    private static let retiredLLMs: Set<String> = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]

    @Published var apiKey: String { didSet { Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "apiKey") } }
    @Published var baseURL: String { didSet { d.set(baseURL, forKey: "baseURL") } }
    @Published var sttModel: String { didSet { d.set(sttModel, forKey: "sttModel") } }
    @Published var llmModel: String { didSet { d.set(llmModel, forKey: "llmModel") } }
    @Published var cleanupEnabled: Bool { didSet { d.set(cleanupEnabled, forKey: "cleanupEnabled") } }
    @Published var keepOnClipboard: Bool { didSet { d.set(keepOnClipboard, forKey: "keepOnClipboard") } }
    @Published var useScreenContext: Bool { didSet { d.set(useScreenContext, forKey: "useScreenContext") } }
    @Published var alwaysShowInDock: Bool {
        didSet {
            d.set(alwaysShowInDock, forKey: "alwaysShowInDock")
            NotificationCenter.default.post(name: .tellrDockPreferenceChanged, object: nil)
        }
    }
    @Published var language: String { didSet { d.set(language, forKey: "language") } }          // what you speak ("" = auto-detect)
    @Published var outputLanguage: String { didSet { d.set(outputLanguage, forKey: "outputLanguage") } }   // what it types ("" = same as spoken)
    @Published var quickTranslateLanguage: String { didSet { d.set(quickTranslateLanguage, forKey: "quickTranslateLanguage") } }  // Control + key
    @Published var vocabulary: String { didSet { d.set(vocabulary, forKey: "vocabulary") } }
    @Published var hotkey: Hotkey { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var retentionDays: Int { didSet { d.set(retentionDays, forKey: "retentionDays") } }
    @Published var tones: [String: String] { didSet { d.set(tones, forKey: "tones") } }
    @Published var snippets: [Snippet] {
        didSet { if let data = try? JSONEncoder().encode(snippets) { d.set(data, forKey: "snippets") } }
    }

    private init() {
        AppSettings.importFromUtter()
        apiKey = Keychain.get("apiKey") ?? ""
        baseURL = d.string(forKey: "baseURL") ?? AppSettings.defaultBaseURL
        sttModel = d.string(forKey: "sttModel") ?? AppSettings.defaultSTT
        let storedLLM = d.string(forKey: "llmModel") ?? AppSettings.defaultLLM
        llmModel = AppSettings.retiredLLMs.contains(storedLLM) ? AppSettings.defaultLLM : storedLLM
        cleanupEnabled = d.object(forKey: "cleanupEnabled") as? Bool ?? true
        keepOnClipboard = d.object(forKey: "keepOnClipboard") as? Bool ?? true
        useScreenContext = d.object(forKey: "useScreenContext") as? Bool ?? true
        alwaysShowInDock = d.object(forKey: "alwaysShowInDock") as? Bool ?? false
        language = d.string(forKey: "language") ?? "en"
        outputLanguage = d.string(forKey: "outputLanguage") ?? ""
        quickTranslateLanguage = d.string(forKey: "quickTranslateLanguage") ?? "en"
        vocabulary = d.string(forKey: "vocabulary") ?? "Tellr, Khadstudio, Hilal, Claude, Claude Code, Framer, Figma, Sam"
        hotkey = Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightOption
        soundsEnabled = d.object(forKey: "soundsEnabled") as? Bool ?? true
        retentionDays = d.object(forKey: "retentionDays") as? Int ?? 30
        tones = d.dictionary(forKey: "tones") as? [String: String] ?? [:]
        if let data = d.data(forKey: "snippets"), let saved = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = saved
        } else {
            snippets = [Snippet(trigger: "my website", text: "https://khadstudio.co")]
        }
        d.set(llmModel, forKey: "llmModel")
    }

    /// The app was called Utter (bundle id co.khadstudio.utter). Copy its preferences over the first time Tellr runs.
    private static func importFromUtter() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "importedFromUtter") else { return }
        d.set(true, forKey: "importedFromUtter")
        guard let old = UserDefaults(suiteName: "co.khadstudio.utter")?.dictionaryRepresentation() else { return }
        let keys = ["baseURL", "sttModel", "llmModel", "cleanupEnabled", "keepOnClipboard", "useScreenContext",
                    "alwaysShowInDock", "language", "vocabulary", "hotkey", "soundsEnabled", "retentionDays",
                    "tones", "snippets"]
        for key in keys where d.object(forKey: key) == nil {
            if let value = old[key] { d.set(value, forKey: key) }
        }
    }

    func tone(for category: AppCategory) -> Tone {
        Tone(rawValue: tones[category.rawValue] ?? "") ?? category.defaultTone
    }

    func setTone(_ tone: Tone, for category: AppCategory) {
        tones[category.rawValue] = tone.rawValue
    }

    var vocabularyList: [String] {
        vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func setVocabulary(_ words: [String]) { vocabulary = words.joined(separator: ", ") }

    func resetProvider() {
        baseURL = AppSettings.defaultBaseURL
        sttModel = AppSettings.defaultSTT
        llmModel = AppSettings.defaultLLM
    }

    var config: AIConfig {
        AIConfig(
            baseURL: baseURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            sttModel: sttModel.trimmingCharacters(in: .whitespacesAndNewlines),
            llmModel: llmModel.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.trimmingCharacters(in: .whitespacesAndNewlines),
            vocabulary: vocabulary.trimmingCharacters(in: .whitespacesAndNewlines),
            cleanupEnabled: cleanupEnabled)
    }
}

// MARK: - Settings page

@MainActor
struct SettingsPage: View {
    @ObservedObject var settings: AppSettings
    let store: HistoryStore
    @State private var axGranted = Permissions.accessibilityGranted
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var showAdvanced = false

    private let retention = [7, 14, 30, 90, 365, 0]

    var body: some View {
        Page(title: "Settings", subtitle: "Tune how Tellr listens, writes and stores your dictations.") {
            SectionLabel("General")
            Card {
                SettingRow(title: "Always show in Dock", subtitle: "Tellr lives in the menu bar. It appears in the Dock while its window is open; turn this on to keep it there.", icon: "dock.rectangle", tint: Theme.gray) {
                    Toggle("", isOn: $settings.alwaysShowInDock).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Dictation key", subtitle: "Hold to talk, release to paste. Quick tap for hands-free, tap again to finish. Esc cancels. Hold Shift too to edit selected text by voice, or Control to translate.", icon: "keyboard", tint: Theme.accent) {
                    Picker("", selection: $settings.hotkey) {
                        ForEach(Hotkey.allCases) { Text($0.short).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                if settings.hotkey == .fn {
                    Text("Also set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                        .padding(.bottom, 8)
                }
            }

            Group {
                SectionLabel("Languages")
                Card {
                    SettingRow(title: "I speak", subtitle: "Auto-detect lets you switch languages freely. Picking one is a little faster and more accurate.", icon: "mic.fill", tint: Theme.blue) {
                        Picker("", selection: $settings.language) {
                            Text("Auto-detect").tag("")
                            ForEach(LanguageOption.all) { Text($0.name).tag($0.code) }
                        }
                        .labelsHidden().frame(width: 180)
                    }
                    Divider()
                    SettingRow(title: "Type in", subtitle: "Speak any language and Tellr types in this one. “Same as I speak” keeps your words in the language you used.", icon: "character.bubble", tint: Theme.purple) {
                        Picker("", selection: $settings.outputLanguage) {
                            Text("Same as I speak").tag("")
                            ForEach(LanguageOption.all) { Text($0.name).tag($0.code) }
                        }
                        .labelsHidden().frame(width: 180)
                    }
                    Divider()
                    SettingRow(title: "Quick translate", subtitle: "Hold Control as you start a dictation to translate just that one into this language.", icon: "globe", tint: Theme.teal) {
                        Picker("", selection: $settings.quickTranslateLanguage) {
                            ForEach(LanguageOption.all) { Text($0.name).tag($0.code) }
                        }
                        .labelsHidden().frame(width: 180)
                    }
                    if !settings.language.isEmpty && (!settings.outputLanguage.isEmpty) {
                        Text("Tip: set “I speak” to Auto-detect so you can talk in any language and still get \(LanguageOption.name(for: settings.outputLanguage)).")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                            .padding(.bottom, 8)
                    }
                }
            }

            SectionLabel("Writing")
            Card {
                SettingRow(title: "AI cleanup", subtitle: "Removes ums, applies your self-corrections, fixes punctuation and grammar.", icon: "sparkles", tint: Theme.accent) {
                    Toggle("", isOn: $settings.cleanupEnabled).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Keep text on clipboard", subtitle: "After pasting, your dictation stays copied so you can paste it again.", icon: "doc.on.clipboard", tint: Theme.gray) {
                    Toggle("", isOn: $settings.keepOnClipboard).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Use on-screen context", subtitle: "Reads the text box you're typing in so names already there get spelled right. Only sent along with a dictation; never saved.", icon: "text.viewfinder", tint: Theme.blue) {
                    Toggle("", isOn: $settings.useScreenContext).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Sound effects", icon: "speaker.wave.2.fill", tint: Theme.pink) {
                    Toggle("", isOn: $settings.soundsEnabled).toggleStyle(.switch).labelsHidden()
                }
            }

            SectionLabel("AI provider")
            Card {
                SettingRow(title: "Speech model", subtitle: "Turns your voice into text. Switch, then use Re-run in History to compare.", icon: "waveform", tint: Theme.purple) {
                    ModelPicker(selection: $settings.sttModel, presets: AppSettings.sttPresets)
                }
                Divider()
                SettingRow(title: "Writing model", subtitle: "Cleans up your text and powers command mode.", icon: "wand.and.stars", tint: Theme.accent) {
                    ModelPicker(selection: $settings.llmModel, presets: AppSettings.llmPresets)
                }
                Divider()
                SettingRow(title: "Groq API key", subtitle: settings.apiKey.isEmpty ? "Required. Free, no card needed." : "Stored securely in your Keychain.", icon: "key.fill", tint: Theme.green) {
                    SecureField("gsk_…", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                Divider()
                HStack {
                    Link("Get a free key →", destination: URL(string: "https://console.groq.com/keys")!)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(showAdvanced ? "Hide advanced" : "Advanced") { withAnimation { showAdvanced.toggle() } }
                        .buttonStyle(.link).font(.system(size: 12))
                }
                .padding(.vertical, 10)
                if showAdvanced {
                    Divider()
                    LabeledField(label: "Base URL", text: $settings.baseURL)
                    LabeledField(label: "Transcription model", text: $settings.sttModel)
                    LabeledField(label: "Cleanup model", text: $settings.llmModel)
                    HStack {
                        Spacer()
                        Button("Reset to defaults") { settings.resetProvider() }
                            .buttonStyle(.link).font(.system(size: 12))
                    }
                    .padding(.vertical, 8)
                }
            }

            Group {
                SectionLabel("Storage")
                Card {
                    SettingRow(title: "Keep recordings", subtitle: "Audio is saved before it's sent, so nothing is lost if your connection drops.", icon: "clock.arrow.circlepath", tint: Theme.blue) {
                        Picker("", selection: $settings.retentionDays) {
                            ForEach(retention, id: \.self) { Text($0 == 0 ? "Forever" : "\($0) days").tag($0) }
                        }
                        .labelsHidden().frame(width: 120)
                    }
                    Divider()
                    SettingRow(title: "Recordings folder", icon: "folder.fill", tint: Theme.teal) {
                        Button("Open in Finder") { NSWorkspace.shared.open(store.audioDir) }
                    }
                    Divider()
                    SettingRow(title: "Backup", subtitle: "Dictionary, snippets, style, settings and history text in one file. Audio and your API key aren't included.", icon: "externaldrive.fill", tint: Theme.gray) {
                        HStack(spacing: 8) {
                            Button("Export…") { Backup.export(settings: settings, store: store) }
                            Button("Import…") { Backup.importFile(settings: settings, store: store) }
                        }
                    }
                }

                SectionLabel("Permissions")
                Card {
                    PermissionRow(title: "Microphone", detail: "To hear you", granted: micGranted) {
                        AVCaptureDevice.requestAccess(for: .audio) { ok in
                            DispatchQueue.main.async { micGranted = ok }
                        }
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Divider()
                    PermissionRow(title: "Accessibility", detail: "To paste into other apps", granted: axGranted) {
                        Permissions.openAccessibilitySettings()
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            axGranted = Permissions.accessibilityGranted
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }
}

struct ModelPreset: Hashable {
    let id: String
    let name: String
    let note: String
}

struct ModelPicker: View {
    @Binding var selection: String
    let presets: [ModelPreset]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(presets, id: \.self) { p in
                Text("\(p.name) — \(p.note)").tag(p.id)
            }
            if !presets.contains(where: { $0.id == selection }) {
                Text("Custom: \(selection)").tag(selection)
            }
        }
        .labelsHidden()
        .frame(width: 260)
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer()
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 300)
        }
        .padding(.vertical, 6)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let fix: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: title == "Microphone" ? "mic.fill" : "hand.raised.fill",
                     tint: granted ? Theme.green : Theme.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.success)
            } else {
                Button("Grant access", action: fix)
            }
        }
        .padding(.vertical, 10)
    }
}

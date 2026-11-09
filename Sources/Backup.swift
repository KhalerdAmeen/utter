import AppKit
import UniformTypeIdentifiers

/// One portable file with everything that makes Utter "yours".
struct BackupFile: Codable {
    var app: String
    var version: Int
    var exportedAt: Date
    var vocabulary: String
    var snippets: [Snippet]
    var tones: [String: String]
    var hotkey: String
    var language: String
    var cleanupEnabled: Bool
    var keepOnClipboard: Bool
    var soundsEnabled: Bool
    var useScreenContext: Bool
    var retentionDays: Int
    var baseURL: String
    var sttModel: String
    var llmModel: String
    var history: [Dictation]
}

@MainActor
enum Backup {
    static func export(settings: AppSettings, store: HistoryStore) {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let panel = NSSavePanel()
        panel.title = "Export Utter backup"
        panel.nameFieldStringValue = "Utter Backup \(stamp).json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let file = BackupFile(
            app: "Utter", version: 1, exportedAt: Date(),
            vocabulary: settings.vocabulary, snippets: settings.snippets, tones: settings.tones,
            hotkey: settings.hotkey.rawValue, language: settings.language,
            cleanupEnabled: settings.cleanupEnabled, keepOnClipboard: settings.keepOnClipboard,
            soundsEnabled: settings.soundsEnabled, useScreenContext: settings.useScreenContext,
            retentionDays: settings.retentionDays, baseURL: settings.baseURL,
            sttModel: settings.sttModel, llmModel: settings.llmModel,
            history: store.items)
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(file).write(to: url, options: .atomic)
            alert("Backup saved", "\(store.items.count) dictations, \(settings.vocabularyList.count) dictionary words and \(settings.snippets.count) snippets exported.")
        } catch {
            alert("Couldn't save the backup", error.localizedDescription)
        }
    }

    static func importFile(settings: AppSettings, store: HistoryStore) {
        let panel = NSOpenPanel()
        panel.title = "Import Utter backup"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let file = try dec.decode(BackupFile.self, from: Data(contentsOf: url))
            guard file.app == "Utter" else { throw AIError("That file isn't an Utter backup") }

            // Dictionary: union, no duplicates
            var words = settings.vocabularyList
            let incoming = file.vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var newWords = 0
            for w in incoming where !words.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) {
                words.append(w); newWords += 1
            }
            settings.setVocabulary(words)

            // Snippets: add ones whose trigger we don't have yet
            var newSnippets = 0
            for s in file.snippets where !settings.snippets.contains(where: { AIClient.normalize($0.trigger) == AIClient.normalize(s.trigger) }) {
                settings.snippets.append(s); newSnippets += 1
            }

            // Preferences: take the backup's values
            settings.tones.merge(file.tones) { _, new in new }
            if let hk = Hotkey(rawValue: file.hotkey) { settings.hotkey = hk }
            settings.language = file.language
            settings.cleanupEnabled = file.cleanupEnabled
            settings.keepOnClipboard = file.keepOnClipboard
            settings.soundsEnabled = file.soundsEnabled
            settings.useScreenContext = file.useScreenContext
            settings.retentionDays = file.retentionDays
            settings.baseURL = file.baseURL
            settings.sttModel = file.sttModel
            settings.llmModel = file.llmModel

            let added = store.merge(file.history)
            alert("Backup imported", "Added \(added) dictations, \(newWords) dictionary words and \(newSnippets) snippets. Your style and settings were restored.")
        } catch {
            alert("Couldn't import that file", error.localizedDescription)
        }
    }

    private static func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }
}

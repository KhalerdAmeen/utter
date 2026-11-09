import Foundation
import Combine

struct Dictation: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case processing, done, failed }
    enum Mode: String, Codable { case dictation, command }

    var id: UUID
    var date: Date
    var audioFile: String
    var duration: Double
    var appName: String
    var bundleID: String
    var raw: String?
    var clean: String?
    var status: Status
    var error: String?
    var cleanupError: String?
    var processingMs: Int?
    var mode: Mode?            // nil = dictation (older entries)
    var sourceText: String?    // command mode: the text that was selected
    var sttModel: String?      // which models produced this, for comparing
    var llmModel: String?

    var isCommand: Bool { mode == .command }

    var wordCount: Int { (clean ?? "").split(whereSeparator: { $0.isWhitespace }).count }
}

/// Every dictation + its audio, stored in ~/Library/Application Support/Utter
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [Dictation] = []
    let audioDir: URL
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Utter", isDirectory: true)
        audioDir = base.appendingPathComponent("Recordings", isDirectory: true)
        fileURL = base.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: fileURL) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            items = (try? dec.decode([Dictation].self, from: data)) ?? []
        }
    }

    var failedCount: Int { items.filter { $0.status == .failed }.count }
    var totalWords: Int { items.reduce(0) { $0 + $1.wordCount } }
    var totalSpokenSeconds: Double { items.reduce(0) { $0 + $1.duration } }

    /// Typing at ~40 wpm vs. speaking it.
    var timeSavedSeconds: Double { max(0, Double(totalWords) / 40.0 * 60.0 - totalSpokenSeconds) }

    func audioURL(fileName: String) -> URL { audioDir.appendingPathComponent(fileName) }
    func audioURL(for item: Dictation) -> URL { audioURL(fileName: item.audioFile) }
    func item(_ id: UUID) -> Dictation? { items.first { $0.id == id } }

    func add(_ d: Dictation) {
        items.insert(d, at: 0)
        save()
    }

    func update(_ id: UUID, _ change: (inout Dictation) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        save()
    }

    func delete(_ id: UUID) {
        guard let d = item(id) else { return }
        try? FileManager.default.removeItem(at: audioURL(for: d))
        items.removeAll { $0.id == id }
        save()
    }

    /// Adds entries from a backup that aren't already here. Returns how many were added.
    func merge(_ incoming: [Dictation]) -> Int {
        let existing = Set(items.map { $0.id })
        var added = 0
        for var d in incoming where !existing.contains(d.id) {
            if d.status == .processing {
                d.status = .failed
                d.error = "Imported while still processing"
            }
            items.append(d)
            added += 1
        }
        items.sort { $0.date > $1.date }
        save()
        return added
    }

    /// Anything left "processing" from a crash or quit becomes retryable.
    func markInterrupted() {
        var changed = false
        for i in items.indices where items[i].status == .processing {
            items[i].status = .failed
            items[i].error = "Interrupted — retry to transcribe"
            changed = true
        }
        if changed { save() }
    }

    func purge(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let old = items.filter { $0.date < cutoff }
        guard !old.isEmpty else { return }
        for d in old { try? FileManager.default.removeItem(at: audioURL(for: d)) }
        items.removeAll { $0.date < cutoff }
        save()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

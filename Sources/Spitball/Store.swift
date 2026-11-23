import Observation
import AppKit
import Foundation

// Everything Spitball remembers lives in ~/Library/Application Support/Spitball as plain
// JSON. Nothing is ever uploaded.

nonisolated struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var text: String
    var seconds: Double
    var app: String?
    var bundleID: String?
    var words: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

nonisolated struct DictEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var word: String          // how it should be written, e.g. "TestFlight"
    var heardAs: String = ""  // optional, comma-separated: what it gets misheard as
}

nonisolated struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String       // what you say, e.g. "my email"
    var text: String          // what gets typed
}

nonisolated struct AppStyle: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var style: WritingStyle
    var instructions: String? = nil   // your own rules for this app ("always sign off with -N")
}

@Observable final class Store {
    static let shared = Store()

    var history: [HistoryItem] = [] { didSet { save(history, "history") } }
    var dictionary: [DictEntry] = [] { didSet { save(dictionary, "dictionary"); compiled = nil } }
    var snippets: [Snippet] = [] { didSet { save(snippets, "snippets") } }
    var styles: [AppStyle] = [] { didSet { save(styles, "styles") } }
    var notes: [Note] = [] { didSet { save(notes, "notes") } }

    static let defaultStyles = [
        AppStyle(bundleID: "com.apple.mail", name: "Mail", style: .smart),
        AppStyle(bundleID: "com.microsoft.Outlook", name: "Outlook", style: .smart),
        AppStyle(bundleID: "com.apple.MobileSMS", name: "Messages", style: .texting),
        AppStyle(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", style: .smart),
    ]

    /// Your own instructions for an app, plus the ones for everywhere.
    func instructions(for bundleID: String?) -> String {
        let app = styles.first(where: { $0.bundleID == bundleID })?.instructions ?? ""
        return [Settings.customInstructions, app].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The style for an app: its own, or your default.
    func style(for bundleID: String?) -> WritingStyle {
        if let id = bundleID, let s = styles.first(where: { $0.bundleID == id }) { return s.style }
        return Settings.defaultStyle
    }

    @ObservationIgnored private let dir: URL
    @ObservationIgnored private var loading = true
    @ObservationIgnored private var compiled: [(NSRegularExpression, String)]?

    init(directory: URL? = nil) {
        dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spitball", isDirectory: true)
        if directory == nil { Store.migrateFromMurmur(to: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        history = load("history") ?? []
        dictionary = load("dictionary") ?? []
        snippets = load("snippets") ?? []
        notes = load("notes") ?? []
        styles = load("styles") ?? Store.defaultStyles.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil   // only apps you have
        }
        loading = false
        // 2.3.1: the old install-time defaults (Formal in Mail, Casual in Slack) waited on
        // Apple Intelligence every time. Move those untouched defaults to Smart, once.
        if directory == nil, !UserDefaults.standard.bool(forKey: "stylesFast") {
            UserDefaults.standard.set(true, forKey: "stylesFast")
            let old: [String: WritingStyle] = ["com.apple.mail": .formal, "com.microsoft.Outlook": .formal, "com.tinyspeck.slackmacgap": .casual]
            for i in styles.indices where old[styles[i].bundleID] == styles[i].style && (styles[i].instructions ?? "").isEmpty {
                styles[i].style = .smart
            }
        }
    }

    /// Re-read from disk (the CLI and MCP server see what the app saved since).
    func reload() {
        loading = true
        history = load("history") ?? history
        notes = load("notes") ?? notes
        loading = false
    }

    // MARK: History + stats

    func record(_ text: String, seconds: Double, app: String?, bundleID: String? = nil) {
        guard Settings.keepHistory, !text.isEmpty else { return }
        history.insert(HistoryItem(date: Date(), text: text, seconds: seconds, app: app, bundleID: bundleID), at: 0)
        if history.count > 1000 { history.removeLast(history.count - 1000) }
    }

    var totalWords: Int { history.reduce(0) { $0 + $1.words } }
    var wordsToday: Int { history.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.words } }
    /// Days in a row with at least one dictation (today or ending yesterday).
    var streak: Int {
        let cal = Calendar.current
        let days = Set(history.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while days.contains(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
    var totalMinutes: Double { history.reduce(0) { $0 + $1.seconds } / 60 }
    var wordsPerMinute: Int { totalMinutes > 0.01 ? Int(Double(totalWords) / totalMinutes) : 0 }
    /// Versus typing at an average 40 wpm.
    var minutesSaved: Int { max(0, Int(Double(totalWords) / 40 - totalMinutes)) }

    // MARK: Text pipeline (dictionary, then snippets)

    func apply(_ text: String) -> String {
        var s = text
        for (re, word) in compiledDictionary() {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                            withTemplate: NSRegularExpression.escapedTemplate(for: word))
        }
        for snip in snippets where !snip.trigger.trimmingCharacters(in: .whitespaces).isEmpty {
            let words = snip.trigger.lowercased().split { !$0.isLetter && !$0.isNumber }.map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty, let re = try? NSRegularExpression(
                pattern: "(?<![\\w])" + words.joined(separator: "[\\s,-]+") + "(?![\\w])", options: .caseInsensitive) else { continue }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                            withTemplate: NSRegularExpression.escapedTemplate(for: snip.text))
        }
        return s
    }

    private func compiledDictionary() -> [(NSRegularExpression, String)] {
        if let compiled { return compiled }
        var out: [(NSRegularExpression, String)] = []
        for e in dictionary {
            let word = e.word.trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            var patterns = [Store.pattern(for: word)]
            patterns += e.heardAs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .map { "(?<![\\w])" + NSRegularExpression.escapedPattern(for: $0) + "(?![\\w])" }
            for p in patterns {
                if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) { out.append((re, word)) }
            }
        }
        compiled = out
        return out
    }

    /// "TestFlight" also matches "test flight" / "Test-Flight"; "GraphQL" matches
    /// "graph QL" / "graph q l". Built from the word's own humps and acronyms.
    static func pattern(for word: String) -> String {
        let re = try! NSRegularExpression(pattern: "[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+|[^\\sA-Za-z0-9]+")
        let parts = re.matches(in: word, range: NSRange(word.startIndex..., in: word)).compactMap { Range($0.range, in: word).map { String(word[$0]) } }
        let pieces = parts.map { part -> String in
            if part.count <= 4, part == part.uppercased(), part.allSatisfy(\.isLetter) {
                return part.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[\\s.]*")
            }
            return NSRegularExpression.escapedPattern(for: part)
        }
        return "(?<![\\w])" + pieces.joined(separator: "[\\s-]*") + "(?![\\w])"
    }

    /// The app used to be called Murmur. Bring its history, dictionary, snippets,
    /// styles and settings along, once.
    static func migrateFromMurmur(to dir: URL) {
        let fm = FileManager.default
        let old = dir.deletingLastPathComponent().appendingPathComponent("Murmur", isDirectory: true)
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: old.path) {
            try? fm.copyItem(at: old, to: dir)
        }
        let d = UserDefaults.standard
        if !d.bool(forKey: "migratedFromMurmur"), let oldPrefs = UserDefaults(suiteName: "com.nicksimpson.murmur")?.dictionaryRepresentation() {
            for key in ["trigger2", "engine", "noise", "shape", "removeFillers", "sounds", "relaxedTiming", "cursorDot",
                        "defaultStyle", "commandMode", "keepHistory", "polish"] {
                if let v = oldPrefs[key], d.object(forKey: key) == nil { d.set(v, forKey: key) }
            }
            d.set(true, forKey: "migratedFromMurmur")
        }
    }

    // MARK: Files

    private func url(_ name: String) -> URL { dir.appendingPathComponent("\(name).json") }

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }

    private static let saveQueue = DispatchQueue(label: "spitball.save", qos: .utility)
    /// Write in the background so saving history never holds up a paste.
    private func save<T: Encodable & Sendable>(_ value: T, _ name: String) {
        guard !loading else { return }
        let target = url(name)
        Store.saveQueue.async {
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
            if let data = try? e.encode(value) { try? data.write(to: target, options: .atomic) }
        }
    }
}

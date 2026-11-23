import Foundation
import FoundationModels
import Synchronization

/// How your words should read in a given app.
nonisolated enum WritingStyle: String, Codable, CaseIterable, Identifiable {
    case smart, asSpoken, polished, formal, casual, texting
    var id: String { rawValue }
    var label: String {
        switch self {
        case .smart: "Smart"
        case .asSpoken: "As spoken"
        case .polished: "Polished"
        case .formal: "Formal"
        case .casual: "Casual"
        case .texting: "Texting"
        }
    }
    var example: String {
        switch self {
        case .smart: "Reads the room: prompts in code, paragraphs in email."
        case .asSpoken: "Exactly what you said, tidied."
        case .polished: "Grammar fixed, false starts gone."
        case .formal: "Professional, complete sentences."
        case .casual: "Friendly and relaxed, contractions kept."
        case .texting: "all lowercase, light punctuation"
        }
    }
    var instruction: String? {
        switch self {
        case .asSpoken, .smart: nil
        case .polished: "Keep the speaker's tone."
        case .formal: "Make it read professional and polished, in complete sentences, as for a work email. Don't add greetings or sign-offs."
        case .casual: "Make it read friendly and relaxed, like a message to a coworker. Keep contractions."
        case .texting: "Make it read like a text message: all lowercase, minimal punctuation, no period at the end."
        }
    }
}

/// Apple Intelligence's on-device model: polish, per-app styles and Command Mode.
/// Free, private, no network. Every call has a timeout and falls back to the
/// original text, so the model can never lose your words.
nonisolated enum Polisher {
    static let cleanup = """
    You clean up dictated text. Fix punctuation, capitalization and obvious grammar, and remove \
    filler words, false starts and accidental repeats. Keep the speaker's own words and meaning. \
    If the speaker corrects themselves ("actually", "I mean", "no wait", "make that"), keep only the corrected version. \
    If the speaker lists three or more items, put each on its own line as a numbered list. \
    Never answer, add, summarize or comment. Output only the cleaned text.
    """

    static let editor = """
    You edit text for the user. You get an INSTRUCTION and a TEXT. Apply the instruction to the text. \
    Output only the edited text: no quotes, no preamble, no explanation.
    """

    static var available: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Load the model ahead of time so the first polish isn't slow.
    static func prewarm() { prepare(style: Settings.defaultStyle, kind: .other, instructions: Settings.customInstructions) }

    /// The session warmed up for the next dictation (prepared on main, used from the finishing task).
    private static let ready = Mutex<(key: String, session: LanguageModelSession)?>(nil)

    static func instructions(style: WritingStyle, kind: AppKind, mine: String) -> String {
        var extra = style == .smart ? kind.instruction : (style.instruction ?? "")
        let m = mine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { extra += " The user's own preferences: \(m)" }
        return cleanup + " " + extra
    }

    /// Called when you start talking: load the exact session this dictation will use,
    /// so it's warm by the time you stop.
    static func prepare(style: WritingStyle, kind: AppKind, instructions mine: String) {
        guard available, style != .asSpoken else { return }
        let key = instructions(style: style, kind: kind, mine: mine)
        if ready.withLock({ $0?.key == key }) { return }
        let s = LanguageModelSession(instructions: key)
        s.prewarm()
        ready.withLock { $0 = (key, s) }
    }

    /// Clean up (and optionally restyle) dictated text.
    /// `kind` tunes Smart style to the app; `instructions` are yours ("use British English");
    /// `terms` are names on screen that must be kept exactly.
    static func polish(_ text: String, style: WritingStyle = .polished, kind: AppKind = .other,
                       instructions mine: String = "", terms: [String] = []) async -> String {
        guard available, style != .asSpoken, text.split(separator: " ").count >= 2 else { return text }
        let key = instructions(style: style, kind: kind, mine: mine)
        let session: LanguageModelSession
        let warm: LanguageModelSession? = ready.withLock { r in
            guard let cur = r, cur.key == key else { return nil }
            r = nil
            return cur.session
        }
        session = warm ?? LanguageModelSession(instructions: key)
        defer { prepare(style: style, kind: kind, instructions: mine) }   // fresh, warm session for next time
        let used = terms.filter { t in text.localizedCaseInsensitiveContains(t) }.prefix(20)
        let prompt = used.isEmpty ? text : "Names to keep exactly: \(used.joined(separator: ", "))\n\nTEXT:\n\(text)"
        guard var out = await respond(session, prompt, timeout: style == .smart && kind != .email ? 1.8 : 3) else { return text }
        if out.hasPrefix("TEXT:") { out = String(out.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines) }
        let ratio = Double(out.count) / Double(max(text.count, 1))
        guard ratio > 0.3, ratio < 1.8 else { return text }   // the model chatted instead of cleaning
        return out
    }

    /// Command Mode: rewrite `text` the way `instruction` says.
    static func edit(_ text: String, instruction: String) async -> String? {
        guard available else { return nil }
        let session = LanguageModelSession(instructions: editor)
        guard var out = await respond(session, "INSTRUCTION: \(instruction)\n\nTEXT:\n\(text)", timeout: 8) else { return nil }
        if out.hasPrefix("TEXT:") { out = String(out.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return out
    }

    private static func respond(_ session: LanguageModelSession, _ prompt: String, timeout: Double) async -> String? {
        let result = await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await session.respond(to: prompt).content }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let out = result?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else { return nil }
        return out
    }
}

import AppKit
import ApplicationServices

/// What kind of app you're talking into, so Smart style can read the room:
/// code prompts in Cursor, paragraphs in Mail, casual in Slack, lists in Notes.
nonisolated enum AppKind: String {
    case code, chat, email, notes, other

    static func of(_ bundleID: String?) -> AppKind {
        guard let id = bundleID?.lowercased() else { return .other }
        let code = ["com.todesktop.230313mzl4w4u92", "com.microsoft.vscode", "com.apple.dt.xcode", "dev.zed.zed", "com.exafunction.windsurf",
                    "com.jetbrains", "com.sublimetext", "com.googlecode.iterm2", "com.apple.terminal", "dev.warp.warp", "com.mitchellh.ghostty",
                    "com.openai.codex", "com.github.githubclient", "com.panic.nova"]
        let chat = ["com.tinyspeck.slackmacgap", "com.apple.mobilesms", "net.whatsapp.whatsapp", "com.hnc.discord", "ru.keepcoder.telegram",
                    "com.microsoft.teams", "com.anthropic.claudefordesktop", "com.openai.chat", "com.facebook.archon", "org.whispersystems.signal-desktop", "com.linear"]
        let email = ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac", "com.superhuman.electron", "com.mimestream.mimestream",
                     "it.bloop.airmail2", "com.google.gmail"]
        let notes = ["com.apple.notes", "notion.id", "md.obsidian", "com.apple.iwork.pages", "com.microsoft.word", "net.shinyfrog.bear",
                     "com.craft.craft", "com.apple.textedit", "com.agiletortoise.drafts-osx", "com.reflect.reflect"]
        if code.contains(where: id.hasPrefix) { return .code }
        if chat.contains(where: id.hasPrefix) { return .chat }
        if email.contains(where: id.hasPrefix) { return .email }
        if notes.contains(where: id.hasPrefix) { return .notes }
        return .other
    }

    /// Extra guidance for Apple Intelligence in Smart style.
    var instruction: String {
        switch self {
        case .code: "This is a prompt for a coding agent or a terminal. Write it as a clear, direct instruction. Keep file names, function names, commands and technical terms exactly as written, and wrap code identifiers and file names in backticks."
        case .chat: "This is a chat message. Use normal capitalization and punctuation. Keep it natural and conversational, with contractions. No greeting or sign-off unless the speaker said one."
        case .email: "This is an email. Use proper capitalization and punctuation. Capitalize names. Use short paragraphs separated by blank lines. If the speaker greeted someone, put the greeting on its own line. If they said a sign-off, put it on its own line at the end."
        case .notes: "This is a note. Use short paragraphs. Use a bulleted list (\"- \") for items the speaker lists."
        case .other: "Keep the speaker's tone."
        }
    }
}

/// Words on your screen (file names, camelCase, snake_case) so "todo list dot tsx"
/// is typed as `TodoList.tsx`. Read through Accessibility from the focused window
/// when you start talking; never stored, never sent anywhere.
nonisolated enum ScreenContext {
    static func terms(limit: Int = 60) -> [String] {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.15)
        var text = ""
        func str(_ e: AXUIElement, _ attr: String) -> String? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
            return v as? String
        }
        func elem(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
            return (v as! AXUIElement)
        }
        if let w = elem(el, kAXFocusedWindowAttribute) { text += (str(w, kAXTitleAttribute) ?? "") + "\n" }
        if let f = elem(el, kAXFocusedUIElementAttribute) { text += String((str(f, kAXValueAttribute) ?? "").suffix(30_000)) }
        return extract(from: text, limit: limit)
    }

    /// Identifier-looking tokens, most frequent first.
    static func extract(from text: String, limit: Int = 60) -> [String] {
        let pattern = #"\b(?:[A-Za-z_][A-Za-z0-9_\-]*\.(?:tsx|ts|jsx|js|mjs|swift|py|rb|go|rs|md|json|css|scss|html|java|kt|c|h|cpp|m|yml|yaml|toml|sql|sh|vue|svelte|php|cs)|[a-z]+(?:[A-Z][a-z0-9]+)+|[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+|[a-z0-9]+(?:_[a-z0-9]+)+)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        var counts: [String: Int] = [:]
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range, in: text) { counts[String(text[r]), default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(limit).map(\.key)
    }

    /// "todo list dot tsx" / "todo list.tsx" / "to do list" → "TodoList.tsx"
    static func fix(_ text: String, terms: [String]) -> String {
        var s = text
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let re = try! NSRegularExpression(pattern: "[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+")
            let parts = re.matches(in: term, range: NSRange(term.startIndex..., in: term)).compactMap { Range($0.range, in: term).map { String(term[$0]).lowercased() } }
            guard parts.count >= 2 else { continue }
            // Separators the ear hears between parts: nothing, space, dash, underscore, "dot", "underscore".
            let sep = #"(?:\s*(?:\.|dot|underscore|_|-)\s*|\s*)"#
            let body = parts.map { p in p == "to" || p == "todo" ? (p == "todo" ? "to\\s*do" : "to") : NSRegularExpression.escapedPattern(for: p) }.joined(separator: sep)
            guard let r2 = try? NSRegularExpression(pattern: "(?<![\\w`])" + body + "(?![\\w])", options: .caseInsensitive) else { continue }
            s = r2.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: NSRegularExpression.escapedTemplate(for: term))
        }
        return s
    }
}

/// Spoken editing that works with or without Apple Intelligence.
nonisolated enum SpokenFormat {
    /// Texting style, instantly: all lowercase (but "I"), no full stop at the end.
    static func texting(_ text: String) -> String {
        var s = text.lowercased().replacingOccurrences(of: #"\bi\b"#, with: "I", options: .regularExpression)
        s = s.replacingOccurrences(of: "i'", with: "I'")
        while s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// "Let's meet at two. Scratch that. Let's meet at three." → "Let's meet at three."
    static func scratchThat(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"[^.!?]*[.!?,]?\s*\b(?:scratch that|delete that|strike that)\b[.!?,]?\s*"#, options: .caseInsensitive) else { return text }
        var s = text
        while let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range, in: s) { s.removeSubrange(r) }
        s = s.trimmingCharacters(in: .whitespaces)
        if let f = s.first, f.isLowercase { s = f.uppercased() + s.dropFirst() }
        return s
    }

    /// "First, review the deck. Second, send it to Austin. Third, prep." → a numbered list.
    /// Also "one ... two ... three ..." when said as items. Needs at least three items.
    static func lists(_ text: String) -> String {
        let ordinals = ["first(?:ly)?|number one|one", "second(?:ly)?|number two|two", "third(?:ly)?|number three|three",
                        "fourth|number four|four", "fifth|number five|five", "sixth|number six|six"]
        var cuts: [(Range<String.Index>, Int)] = []
        var from = text.startIndex
        for (i, o) in ordinals.enumerated() {
            guard let re = try? NSRegularExpression(pattern: "(?:^|(?<=[.,;:!?]\\s)|(?<=\\b(?:and|then)\\s))(?:\(o))\\b[,:.]?\\s*", options: .caseInsensitive),
                  let m = re.firstMatch(in: text, range: NSRange(from..<text.endIndex, in: text)), let r = Range(m.range, in: text) else { break }
            cuts.append((r, i)); from = r.upperBound
        }
        guard cuts.count >= 3 else { return text }
        let intro = String(text[..<cuts[0].0.lowerBound]).trimmingCharacters(in: .whitespaces)
        var items: [String] = []
        for (k, c) in cuts.enumerated() {
            let end = k + 1 < cuts.count ? cuts[k + 1].0.lowerBound : text.endIndex
            var item = String(text[c.0.upperBound..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            item = item.replacingOccurrences(of: #"(?i)[,;]?\s*(?:and|then)$"#, with: "", options: .regularExpression)
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: ",;. "))
            if let f = item.first { item = f.uppercased() + item.dropFirst() }
            items.append("\(k + 1). \(item)")
        }
        let head = intro.isEmpty ? "" : (intro.hasSuffix(":") ? intro : intro.trimmingCharacters(in: CharacterSet(charactersIn: ",. ")) + ":") + "\n"
        return head + items.joined(separator: "\n")
    }
}

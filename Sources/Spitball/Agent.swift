import Foundation

// Agent access: your notes and dictations, for Claude, Cursor, Codex, ChatGPT…
//   Spitball --mcp                 a local MCP server over stdio (read-only)
//   spitball notes [search]        the command-line tool (same binary)
//   spitball note latest|<id>      one note as Markdown
//   spitball history [search] [-n 20]
//   spitball stats
// Everything is read from your Mac. Nothing is uploaded, no API key, no account.

enum AgentAccess {
    static let binary = "/Applications/Spitball.app/Contents/MacOS/Spitball"
    static var mcpConfig: String {
        """
        {
          "mcpServers": {
            "spitball": { "command": "\(Bundle.main.executablePath ?? binary)", "args": ["--mcp"] }
          }
        }
        """
    }

    static let commands: Set<String> = ["notes", "note", "history", "stats", "help", "--help"]

    /// Put `spitball` on your PATH (~/.local/bin, no admin password needed).
    static func installCLI() -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let link = dir.appendingPathComponent("spitball")
        try? FileManager.default.removeItem(at: link)
        do {
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: Bundle.main.executablePath ?? binary)
            let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
            return path.contains(dir.path) ? "Installed. Try: spitball notes" : "Installed to ~/.local/bin. Add it to your PATH, then try: spitball notes"
        } catch { return "Couldn't install: \(error.localizedDescription)" }
    }

    // MARK: Shared queries

    @MainActor static func notes(_ store: Store, query: String?, limit: Int) -> [Note] {
        let all = store.notes
        guard let q = query, !q.isEmpty else { return Array(all.prefix(limit)) }
        return Array(all.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.transcript.localizedCaseInsensitiveContains(q)
            || $0.summary.joined(separator: " ").localizedCaseInsensitiveContains(q) }.prefix(limit))
    }

    @MainActor static func note(_ store: Store, _ id: String) -> Note? {
        id == "latest" ? store.notes.first : store.notes.first { $0.id.uuidString.lowercased().hasPrefix(id.lowercased()) }
    }

    @MainActor static func history(_ store: Store, query: String?, limit: Int) -> [HistoryItem] {
        let all = store.history
        guard let q = query, !q.isEmpty else { return Array(all.prefix(limit)) }
        return Array(all.filter { $0.text.localizedCaseInsensitiveContains(q) || ($0.app ?? "").localizedCaseInsensitiveContains(q) }.prefix(limit))
    }

    @MainActor static func stats(_ store: Store) -> String {
        "\(store.totalWords) words dictated, \(store.wordsPerMinute) wpm, about \(store.minutesSaved) minutes saved vs typing, \(store.history.count) dictations, \(store.notes.count) notes."
    }

    static func line(_ n: Note) -> String {
        "\(n.id.uuidString.prefix(8))  \(n.date.formatted(date: .abbreviated, time: .shortened))  \(Note.clock(n.duration))  \(n.title)"
    }

    static func line(_ h: HistoryItem) -> String {
        "\(h.date.formatted(date: .abbreviated, time: .shortened))  \(h.app ?? "—")  \(h.text)"
    }

    // MARK: CLI

    @MainActor static func runCLI(_ args: [String]) -> Int32 {
        let store = Store.shared
        let cmd = args.first ?? "help"
        var rest = Array(args.dropFirst())
        var limit = 20
        if let i = rest.firstIndex(of: "-n"), i + 1 < rest.count, let n = Int(rest[i + 1]) { limit = n; rest.removeSubrange(i...(i + 1)) }
        let query = rest.isEmpty ? nil : rest.joined(separator: " ")
        switch cmd {
        case "notes":
            let found = notes(store, query: query, limit: limit)
            print(found.isEmpty ? "No notes." : found.map(line).joined(separator: "\n"))
        case "note":
            guard let n = note(store, query ?? "latest") else { print("No such note."); return 1 }
            print(n.markdown)
        case "history":
            let found = history(store, query: query, limit: limit)
            print(found.isEmpty ? "No dictations." : found.map(line).joined(separator: "\n"))
        case "stats":
            print(stats(store))
        default:
            print("""
            spitball: your Spitball notes and dictations, from the terminal.

              spitball notes [search] [-n 20]     list notes
              spitball note latest|<id>           print a note as Markdown
              spitball history [search] [-n 20]   recent dictations
              spitball stats                      words, speed, time saved

            For AI agents, add this MCP server: \(Bundle.main.executablePath ?? binary) --mcp
            """)
        }
        return 0
    }

    // MARK: MCP (JSON-RPC 2.0 over stdio, newline-delimited)

    static let tools: [[String: Any]] = [
        tool("list_notes", "List the user's Spitball voice notes and meeting notes, newest first. Optionally filter by a search query.",
             ["query": ["type": "string", "description": "Words to search titles, summaries and transcripts for"],
              "limit": ["type": "integer", "description": "How many (default 20)"]]),
        tool("get_note", "Get one note as Markdown: title, summary, action items and the full transcript (meetings say who spoke).",
             ["id": ["type": "string", "description": "A note id (or its first 8 characters) from list_notes, or \"latest\""]], required: ["id"]),
        tool("search_dictations", "Search what the user has dictated with Spitball, with the app and time of each dictation.",
             ["query": ["type": "string"], "limit": ["type": "integer"]]),
        tool("get_stats", "The user's Spitball stats: words dictated, words per minute, time saved.", [:]),
    ]

    static func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
        ["name": name, "description": desc, "inputSchema": ["type": "object", "properties": props, "required": required],
         "annotations": ["readOnlyHint": true]]
    }

    @MainActor static func runMCP() {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let raw = readLine(strippingNewline: true) {
            guard let data = raw.data(using: .utf8), let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let id = msg["id"]
            let method = msg["method"] as? String ?? ""
            let params = msg["params"] as? [String: Any] ?? [:]
            guard id != nil else { continue }   // notifications need no reply
            var result: [String: Any]?
            var error: [String: Any]?
            switch method {
            case "initialize":
                result = ["protocolVersion": (params["protocolVersion"] as? String) ?? "2025-06-18",
                          "capabilities": ["tools": [:]],
                          "serverInfo": ["name": "spitball", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2"],
                          "instructions": "Read-only access to the user's Spitball voice notes, meeting notes and dictation history, stored on their Mac."]
            case "ping": result = [:]
            case "tools/list": result = ["tools": tools]
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let a = params["arguments"] as? [String: Any] ?? [:]
                let q = a["query"] as? String
                let limit = (a["limit"] as? Int) ?? 20
                Store.shared.reload()
                let text: String
                switch name {
                case "list_notes":
                    let found = notes(.shared, query: q, limit: limit)
                    text = found.isEmpty ? "No notes." : found.map { n in
                        "- \(line(n))\(n.summary.first.map { "\n  " + $0 } ?? "")"
                    }.joined(separator: "\n")
                case "get_note":
                    text = note(.shared, a["id"] as? String ?? "latest")?.markdown ?? "No note with that id."
                case "search_dictations":
                    let found = history(.shared, query: q, limit: limit)
                    text = found.isEmpty ? "No dictations found." : found.map(line).joined(separator: "\n")
                case "get_stats":
                    text = stats(.shared)
                default:
                    error = ["code": -32602, "message": "Unknown tool \(name)"]; text = ""
                }
                if error == nil { result = ["content": [["type": "text", "text": text]]] }
            default:
                error = ["code": -32601, "message": "Method not found: \(method)"]
            }
            var reply: [String: Any] = ["jsonrpc": "2.0", "id": id!]
            if let error { reply["error"] = error } else { reply["result"] = result ?? [:] }
            if let out = try? JSONSerialization.data(withJSONObject: reply), let s = String(data: out, encoding: .utf8) { print(s) }
        }
    }
}

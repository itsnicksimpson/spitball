import Foundation

/// Spitball Club: an OPT-IN leaderboard. When you join, Spitball shares only your
/// running totals (words and seconds spoken), an anonymous install id and the
/// nickname you choose. Never audio, never text. Off by default.
enum Club {
    /// Set `SpitballClubAPI` in Info.plist to the deployed Worker URL to turn this on.
    static var api: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SpitballClubAPI") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }
    static var available: Bool { api != nil }

    static var installID: String {
        if let id = UserDefaults.standard.string(forKey: "clubID") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "clubID")
        return id
    }

    @MainActor private static var pending: DispatchWorkItem?

    /// Debounced: reports totals a few seconds after you stop dictating.
    @MainActor static func report() {
        guard let api, UserDefaults.standard.bool(forKey: "joinClub") else { return }
        pending?.cancel()
        let work = DispatchWorkItem {
            let store = Store.shared
            let body: [String: Any] = [
                "id": installID,
                "handle": UserDefaults.standard.string(forKey: "clubHandle") ?? "",
                "words": store.totalWords,
                "seconds": Int(store.history.reduce(0) { $0 + $1.seconds }),
            ]
            var req = URLRequest(url: api.appendingPathComponent("v1/report"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 10
            URLSession.shared.dataTask(with: req).resume()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Your rank among members, if you've joined.
    static func rank() async -> (rank: Int, members: Int)? {
        guard let api, UserDefaults.standard.bool(forKey: "joinClub") else { return nil }
        var c = URLComponents(url: api.appendingPathComponent("v1/rank"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "id", value: installID)]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = j["rank"] as? Int, let m = j["members"] as? Int else { return nil }
        return (r, m)
    }
}

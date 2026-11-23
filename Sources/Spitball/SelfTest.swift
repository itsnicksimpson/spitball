import AppKit
import AVFoundation
import SwiftUI

/// `Spitball --self-test [audio files…]` — checks the parts that don't need a human:
/// double-tap logic, text cleanup, both engines on real audio, and island renders.
enum SelfTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ ok: Bool, _ name: String) {
        print(ok ? "  ✓ \(name)" : "  ✗ \(name)")
        if !ok { failures += 1 }
    }

    static func run() {
        print("Double-tap ⌘")
        var d = DoubleTapDetector()
        d.press(at: 0, otherModifiers: false); _ = d.release(at: 0.08)
        d.press(at: 0.2, otherModifiers: false)
        check(d.release(at: 0.28) == .doubleTap, "two quick taps start dictation")

        d = DoubleTapDetector()
        d.press(at: 0, otherModifiers: false); _ = d.release(at: 0.08)
        d.press(at: 0.9, otherModifiers: false)
        check(d.release(at: 1.0) == .tap, "taps too far apart don't")

        d = DoubleTapDetector()
        d.press(at: 0, otherModifiers: false); d.interrupt(); _ = d.release(at: 0.1)   // ⌘C
        d.press(at: 0.2, otherModifiers: false)
        check(d.release(at: 0.28) != .doubleTap, "⌘C then ⌘ doesn't")

        d = DoubleTapDetector()
        d.press(at: 0, otherModifiers: false); _ = d.release(at: 0.6)                // long hold
        d.press(at: 0.7, otherModifiers: false)
        check(d.release(at: 0.75) != .doubleTap, "a long hold then a tap doesn't")

        d = DoubleTapDetector()
        d.press(at: 0, otherModifiers: true); _ = d.release(at: 0.05)                // ⇧⌘
        d.press(at: 0.15, otherModifiers: false)
        check(d.release(at: 0.2) != .doubleTap, "⇧⌘ then ⌘ doesn't")

        print("Cleanup")
        check(Typer.clean("Um, hey there. Uh, it works.") == "Hey there. It works.", "drops um/uh and re-capitalizes")
        check(Typer.clean("  Plain sentence.  ") == "Plain sentence.", "leaves clean text alone")
        check(SpokenFormat.scratchThat("Let's meet at two. Scratch that. Let's meet at three.") == "Let's meet at three.", "\"scratch that\" drops the sentence before it")
        let list = SpokenFormat.lists("Today I need to do three things. First, review the landing page. Second, send Austin the deck. And third, prep for the call.")
        check(list == "Today I need to do three things:\n1. Review the landing page\n2. Send Austin the deck\n3. Prep for the call", "spoken list becomes a numbered list")
        check(SpokenFormat.lists("I had one coffee and two bagels.") == "I had one coffee and two bagels.", "numbers in a sentence aren't a list")
        let stream = SpeakerStream(speaker: "You")
        var tone = (0..<(16_000 * 27)).map { i in Float(sin(Double(i) * 0.05)) * 0.3 }
        for i in (16_000 * 22)..<(16_000 * 22 + 8_000) { tone[i] = 0 }   // a pause at 22 s
        stream.append(tone)
        let piece = stream.take(final: false)
        check(piece.map { abs(Double($0.samples.count) / 16_000 - 22.25) < 0.5 } == true, "long notes are cut at a pause")
        check(stream.take(final: true).map { abs($0.start - Double(piece?.samples.count ?? 0) / 16_000) < 0.01 } == true, "the rest keeps its timestamp")
        let terms = ScreenContext.extract(from: "export const TodoList = () => { useState(); } // TodoList.tsx api_client")
        check(terms.contains("TodoList.tsx") && terms.contains("api_client") && terms.contains("useState"), "finds file names and code terms on screen")
        check(ScreenContext.fix("Add a filter to todo list dot tsx using use state", terms: terms) == "Add a filter to TodoList.tsx using useState", "spoken file names come out exact")
        if Polisher.available {
            check(!AppDelegate.needsAI("running five minutes late start without me", style: .smart, kind: .chat, instructions: ""), "Smart in chat pastes instantly (no AI wait)")
            check(AppDelegate.needsAI("hey dan thanks for the update", style: .smart, kind: .email, instructions: ""), "Smart in email uses AI for paragraphs")
            check(!AppDelegate.needsAI("so I mean it's actually a long message about the launch and the sidebar", style: .smart, kind: .chat, instructions: ""), "long chat messages never wait on AI")
        }
        check(AppKind.of("com.todesktop.230313mzl4w4u92") == .code && AppKind.of("com.apple.mail") == .email, "knows Cursor is code and Mail is email")
        check(Typer.clean("I think we, uh, we should ship") == "I think we, we should ship", "mid-sentence uh")
        check(Typer.clean("Meet at 3 p.m. and bring snacks, e.g. chips.") == "Meet at 3 p.m. and bring snacks, e.g. chips.", "keeps p.m. / e.g. lowercase")

        print("Practice matching")
        check(Practice.score("Running 5 minutes late. Start without me.", Practice.phrases[0]) >= 0.6, "numbers and punctuation forgiven")
        check(Practice.score("Can you send me the deck by Friday", Practice.phrases[1]) == 1, "exact phrase")
        check(Practice.score("pizza tonight", Practice.phrases[2]) < 0.6, "wrong phrase doesn't pass")

        print("Live highlight")
        let pr = Practice()
        pr.live("running five"); check(pr.spoken == 2, "lights up words as they're heard")
        pr.live("running 5 minutes late start"); check(pr.spoken == 5, "numbers count (5 = five)")
        pr.live("running five minutes late, start without me"); check(pr.spoken == 7, "whole phrase lit")

        print("Dictionary & snippets")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("spitball-test-\(UUID())")
        let st = Store(directory: tmp)
        st.dictionary = [DictEntry(word: "TestFlight"), DictEntry(word: "GraphQL"), DictEntry(word: "PlanetScale"),
                         DictEntry(word: "Nick", heardAs: "Nik, Nic")]
        st.snippets = [Snippet(trigger: "my email", text: "nick@example.com")]
        check(st.apply("before the test flight build goes out") == "before the TestFlight build goes out", "test flight → TestFlight")
        check(st.apply("update the graph QL schema") == "update the GraphQL schema", "graph QL → GraphQL")
        check(st.apply("the planet scale bill") == "the PlanetScale bill", "planet scale → PlanetScale")
        check(st.apply("thanks Nik") == "thanks Nick", "heard-as alias")
        check(st.apply("an island trip") == "an island trip", "doesn't touch unrelated words")
        check(st.apply("Send it to my email.") == "Send it to nick@example.com.", "snippet inline")
        st.history = []
        st.history.append(HistoryItem(date: Date(), text: "one two three four", seconds: 2, app: nil))
        check(st.wordsPerMinute == 120, "words per minute")
        try? FileManager.default.removeItem(at: tmp)

        let files = CommandLine.arguments.drop { $0 != "--self-test" }.dropFirst().map { URL(fileURLWithPath: $0) }
        let done = DispatchSemaphore(value: 0)
        Task {
            await engines(files)
            await ai()
            await MainActor.run { renders() }
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date() + 0.05) }
        print(failures == 0 ? "\nAll good." : "\n\(failures) failed.")
        exit(failures == 0 ? 0 : 1)
    }

    /// `Spitball --bench file.aiff`: how long Parakeet takes on a real-length clip.
    static func bench(_ path: String) async {
        let parakeet = ParakeetEngine()
        try? await parakeet.load { _ in }
        guard let s = try? samples(URL(fileURLWithPath: path)) else { print("can't read \(path)"); return }
        print(String(format: "audio %.1fs", Double(s.count) / 16_000))
        var whole = ""
        for i in 0..<3 {
            let t = Date()
            whole = (try? await parakeet.transcribe(s)) ?? ""
            print(String(format: "whole clip, run %d: %d ms, %d words", i + 1, Int(Date().timeIntervalSince(t) * 1000), whole.split(separator: " ").count))
        }
        // Streaming: pieces were done while talking, so after you stop only the tail is left.
        guard let r = try? await Dictation.transcribeInPieces(s, with: parakeet) else { return }
        let t = Date()
        _ = try? await parakeet.transcribe(Array(s[r.tailStart...]))
        let a = Set(whole.lowercased().split(separator: " ")), b = Set(r.text.lowercased().split(separator: " "))
        print(String(format: "streaming: %d pieces done while talking, %.1fs tail → %d ms after you stop; word match %.0f%%",
                     r.pieces, Double(s.count - r.tailStart) / 16_000, Int(Date().timeIntervalSince(t) * 1000),
                     100 * Double(a.intersection(b).count) / Double(max(1, a.count))))
    }

    static func ai() async {
        guard Polisher.available else { print("Apple Intelligence: not available, skipped"); return }
        print("Apple Intelligence (on-device)")
        var t = Date()
        let edited = await Polisher.edit("hey can u send me the deck by friday, need it for the board thing", instruction: "make this more formal")
        check(edited != nil && edited != "", String(format: "Command Mode %.1fs → %@", Date().timeIntervalSince(t), edited ?? "nil"))
        t = Date()
        let es = await Polisher.edit("See you tomorrow at the office.", instruction: "translate to Spanish")
        check(es?.lowercased().contains("mañana") == true, String(format: "translate %.1fs → %@", Date().timeIntervalSince(t), es ?? "nil"))
        for style in [WritingStyle.formal, .casual, .texting] {
            t = Date()
            let out = await Polisher.polish("So I think we we should probably push the launch to next week because the build isn't ready.", style: style)
            check(!out.isEmpty, String(format: "%@ %.1fs → %@", style.label, Date().timeIntervalSince(t), out))
        }
        _ = await AppDelegate.format("warm up the pipeline once", app: nil, terms: [])
        check(SpokenFormat.texting("Running late. I'll be there soon.") == "running late. I'll be there soon", "Texting style is instant: lowercase, no final period")
        for (app, label) in [("com.anthropic.claudefordesktop", "Claude"), ("com.apple.MobileSMS", "Messages")] {
            let t0 = Date()
            let out = await AppDelegate.format("okay so let's add the new sidebar and then ship it tonight", app: app, terms: [])
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            check(ms < 60, "after transcription, \(label) pastes in \(ms) ms → \(out)")
        }
        Polisher.prepare(style: .smart, kind: .email, instructions: ""); try? await Task.sleep(for: .seconds(1.5))   // like talking
        t = Date()
        let smart = await Polisher.polish("hey dan thanks for the update um I'll send the final copy tonight then we can publish tomorrow thanks nick", style: .smart, kind: .email)
        check(smart.contains("\n"), String(format: "Smart email %.1fs → %@", Date().timeIntervalSince(t), smart.replacingOccurrences(of: "\n", with: " ⏎ ")))
        t = Date()
        let brit = await Polisher.polish("the color of the organization logo is great", style: .polished, instructions: "Use British English spelling.")
        check(brit.lowercased().contains("colour"), String(format: "your instructions %.1fs → %@", Date().timeIntervalSince(t), brit))
        t = Date()
        var note = Note(date: Date(), kind: .meeting, title: "Meeting")
        note.lines = [
            NoteLine(at: 0, speaker: "You", text: "Thanks for joining. Let's lock the launch date for the Atlas redesign."),
            NoteLine(at: 6, speaker: "Them", text: "Engineering can be ready by March third if design hands off the pricing page this week."),
            NoteLine(at: 14, speaker: "You", text: "Great, I'll send the pricing page to Priya by Friday. Can you set up the staging build?"),
            NoteLine(at: 20, speaker: "Them", text: "Yes, I'll have staging up Monday and share the link in Slack."),
        ]
        let d = await Digest.make(from: note)
        check(!d.title.isEmpty && !d.summary.isEmpty && !d.actions.isEmpty,
              String(format: "meeting digest %.1fs → %@ | %d points | %@", Date().timeIntervalSince(t), d.title, d.summary.count, d.actions.joined(separator: "; ")))
    }

    static func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inF = file.processingFormat
        let inBuf = AVAudioPCMBuffer(pcmFormat: inF, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        let conv = AVAudioConverter(from: inF, to: Recorder.format)!
        let out = AVAudioPCMBuffer(pcmFormat: Recorder.format,
                                   frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / inF.sampleRate) + 64)!
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, s in
            if fed { s.pointee = .endOfStream; return nil }
            fed = true; s.pointee = .haveData; return inBuf
        }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }

    static func engines(_ files: [URL]) async {
        guard !files.isEmpty else { return }
        print("Engines")
        let apple = AppleEngine()
        let parakeet = ParakeetEngine()
        var t = Date()
        do { try await apple.prepare {}; check(apple.isReady, String(format: "Apple ready (%.2fs)", Date().timeIntervalSince(t))) }
        catch { check(false, "Apple prepare: \(error)") }
        t = Date()
        do { try await parakeet.load { _ in }; check(await parakeet.isReady, String(format: "Parakeet ready (%.2fs)", Date().timeIntervalSince(t))) }
        catch { check(false, "Parakeet load: \(error)") }

        if let f = files.first, let all = try? samples(f) {
            let lc = LiveCaption()
            var partials: [String] = []
            lc.start(engine: apple) { partials.append($0) }
            var i = 0
            while i < all.count { lc.feed(Array(all[i..<min(i + 1600, all.count)])); i += 1600; try? await Task.sleep(for: .milliseconds(20)) }
            try? await Task.sleep(for: .seconds(1.5))
            lc.stop()
            check(partials.count >= 2 && !(partials.last ?? "").isEmpty, "live captions stream (\(partials.count) updates) → \(partials.last ?? "")")
        }
        for f in files {
            guard let s = try? samples(f) else { check(false, "read \(f.lastPathComponent)"); continue }
            print("  \(f.lastPathComponent) (\(String(format: "%.1f", Double(s.count) / 16_000))s of audio)")
            for (name, run) in [("Parakeet", { try await parakeet.transcribe(s) }), ("Apple", { try await apple.transcribe(s) })] as [(String, () async throws -> String)] {
                let t0 = Date()
                do {
                    let text = try await run()
                    let ms = Int(Date().timeIntervalSince(t0) * 1000)
                    check(!text.isEmpty, "\(name) \(ms)ms → \(Typer.clean(text))")
                } catch { check(false, "\(name): \(error)") }
            }
        }
    }

    /// Draws the real welcome window off-screen (AppKit-backed, so the text box renders too).
    @MainActor static func renderWelcome(_ path: String, stage: Int, keys: KeyState, after: Double) {
        let status = SetupStatus(app: nil)
        status.mic = true; status.accessibility = false
        status.engine = "Parakeet ready, on-device"; status.engineDone = true; status.accessibility = true
        let practice = Practice()
        if keys.listening { practice.phase = .listening }
        if path.contains("finished") { practice.finished = true; Member.shared.ensure() }
        let im = IslandModel(); im.levels = [0.2, 0.4, 0.7, 0.9, 1, 0.9, 0.7, 0.4, 0.2]
        let view = WelcomeView(keys: keys, island: im, status: status, practice: practice, trigger: .doubleCommand, skip: {}, initialStage: stage)
        let host = NSHostingView(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 480, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date() + after)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        win.orderOut(nil)
    }

    @MainActor static func renderView<V: View>(_ v: V, size: NSSize, path: String) {
        let host = NSHostingView(rootView: v)
        let win = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date() + 0.4)
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        win.orderOut(nil)
    }

    @MainActor static func renders() {
        try? FileManager.default.createDirectory(atPath: "shots", withIntermediateDirectories: true)
        let k1 = KeyState()
        renderWelcome("shots/welcome.png", stage: 4, keys: k1, after: 0.6)
        let k2 = KeyState(); k2.listening = true; k2.commandDown = true; k2.taps = 2
        renderWelcome("shots/welcome-listening.png", stage: 4, keys: k2, after: 1.6)
        renderWelcome("shots/welcome-intro.png", stage: 2, keys: KeyState(), after: 0.3)
        renderWelcome("shots/welcome-finished.png", stage: 4, keys: KeyState(), after: 0.6)
        renderView(WhatsNewView(close: {}), size: NSSize(width: 440, height: 520), path: "shots/whatsnew.png")
        renderView(PermissionGuide(open: {}).frame(width: 448).padding(16).background(Color.white), size: NSSize(width: 480, height: 200), path: "shots/permguide.png")
        renderView(IDCardView(member: Member.shared).frame(width: 600, height: 378).padding(20).background(Color.white), size: NSSize(width: 640, height: 418), path: "shots/idcard.png")
        let savedTheme = UserDefaults.standard.string(forKey: "theme") ?? "pacific"
        let demo = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("spitball-demo-\(UUID())"))
        demo.dictionary = [DictEntry(word: "TestFlight"), DictEntry(word: "GraphQL", heardAs: "graph QL"), DictEntry(word: "PlanetScale")]
        demo.snippets = [Snippet(trigger: "my email", text: "nick@example.com"), Snippet(trigger: "my calendar", text: "cal.com/nick/30min")]
        demo.history = [HistoryItem(date: Date().addingTimeInterval(-90), text: "Running five minutes late, start without me.", seconds: 2.4, app: "Messages", bundleID: "com.apple.MobileSMS"),
                        HistoryItem(date: Date().addingTimeInterval(-3600), text: "Can you send me the deck by Friday? I want to review the GraphQL changes before the TestFlight build goes out.", seconds: 6.1, app: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
                        HistoryItem(date: Date().addingTimeInterval(-86400), text: "Make the hero headline bigger and ship it before the demo day dry run.", seconds: 3.8, app: "Linear", bundleID: "com.linear")]
        for theme in RetroTheme.allCases {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            for tab in theme == .pacific ? PrefTab.allCases : [.history] {
                let nav = WindowNav(); nav.tab = tab
                renderView(SpitballView(store: demo, nav: nav, runSetup: {}, close: {}), size: NSSize(width: 600, height: 640),
                           path: "shots/app-\(theme.rawValue)-\(tab.rawValue).png")
            }
        }
        UserDefaults.standard.set(savedTheme, forKey: "theme")
        // Pro skin renders
        let savedSkin = UserDefaults.standard.string(forKey: "skin")
        UserDefaults.standard.set("pro", forKey: "skin")
        var demoNote = Note(date: Date().addingTimeInterval(-3600), kind: .meeting, title: "Atlas launch date and handoff", duration: 1260, app: "Zoom")
        demoNote.lines = [NoteLine(at: 0, speaker: "You", text: "Thanks for joining. Let's lock the launch date."),
                          NoteLine(at: 6, speaker: "Them", text: "Engineering can be ready by March third if design hands off this week.")]
        demoNote.summary = ["Launch targeted for March 3, pending design handoff this week.", "Staging build goes up Monday."]
        demoNote.actions = ["You: send the pricing page to Priya by Friday", "Them: share the staging link in Slack"]
        var voice = Note(date: Date().addingTimeInterval(-86_400), kind: .voice, title: "Ideas for the onboarding film", duration: 184)
        voice.summary = ["Open on the notch island, cut to the ID card."]
        demo.notes = [demoNote, voice]
        renderView(ProSession(note: demoNote, close: {}, delete: {}), size: NSSize(width: 860, height: 700), path: "shots/pro-session.png")
        renderView(ZStack { Color.white; NoteDetail(note: demoNote, theme: .pacific, back: {}, delete: {}).padding(.top, 20) }, size: NSSize(width: 600, height: 560), path: "shots/pro-note.png")
        do { let nav = WindowNav(); nav.tab = .general
             renderView(ProSpitballView(store: demo, nav: nav, runSetup: {}), size: NSSize(width: 860, height: 2000), path: "shots/pro-settings-tall.png") }
        for tab in [PrefTab.history, .notes, .general, .styles, .dictionary] {
            let nav = WindowNav(); nav.tab = tab
            renderView(ProSpitballView(store: demo, nav: nav, runSetup: {}), size: NSSize(width: 940, height: 700), path: "shots/pro-\(tab.rawValue).png")
        }
        let ps = SetupStatus(app: nil); ps.mic = true; ps.accessibility = true; ps.engine = "Parakeet ready"; ps.engineDone = true
        let pp = Practice(); pp.phase = .listening; pp.spoken = 3
        let pim = IslandModel(); pim.levels = [0.2, 0.4, 0.7, 0.9, 1, 0.9, 0.7, 0.4, 0.2]
        renderView(ProWelcomeView(keys: KeyState(), island: pim, status: ps, practice: pp, trigger: .doubleCommand, skip: {}), size: NSSize(width: 560, height: 760), path: "shots/pro-welcome.png")
        let pf = Practice(); pf.finished = true; Member.shared.ensure()
        renderView(ProWelcomeView(keys: KeyState(), island: pim, status: ps, practice: pf, trigger: .doubleCommand, skip: {}), size: NSSize(width: 560, height: 760), path: "shots/pro-finished.png")
        renderView(WhatsNewView(close: {}), size: NSSize(width: 440, height: 520), path: "shots/pro-whatsnew.png")
        if let savedSkin { UserDefaults.standard.set(savedSkin, forKey: "skin") } else { UserDefaults.standard.removeObject(forKey: "skin") }
        let im = IslandModel(); im.style = .notch; im.cutoutWidth = 185; im.barHeight = 32; im.phase = .listening
        im.levels = [0.2, 0.4, 0.7, 0.9, 1, 0.9, 0.7, 0.4, 0.2]
        renderView(ZStack(alignment: .top) { Color(white: 0.9); IslandView(m: im) }, size: NSSize(width: 560, height: 60), path: "shots/island-orb.png")
        renderView(ZStack { Color.white; CaretWaveView(m: im) }, size: NSSize(width: 60, height: 30), path: "shots/cursor-dot.png")
        let ed = IslandModel(); ed.style = .notch; ed.cutoutWidth = 185; ed.barHeight = 32; ed.phase = .listening; ed.editing = true; ed.levels = im.levels
        renderView(ZStack(alignment: .top) { Color(white: 0.9); IslandView(m: ed) }, size: NSSize(width: 560, height: 60), path: "shots/island-edit.png")
        for (n, st, lv) in [("glass-floating", IslandStyle.floating, CGFloat(0.25)), ("glass-notch", .notch, 0.25), ("glass-notch-quiet", .notch, 0.08)] {
            let g = IslandModel(); g.style = st; g.cutoutWidth = 185; g.barHeight = 37; g.phase = .listening; g.armed = true
            g.levels = [0.3, 0.5, 0.8, 0.95, 1, 0.9, 0.7, 0.5, 0.3].map { $0 * lv }
            let r = ImageRenderer(content: ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.95, green: 0.8, blue: 0.7), Color(red: 0.6, green: 0.75, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
                IslandView(m: g)
                if st == .notch {   // the physical notch hides the middle: show what you actually see
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(Color.black).frame(width: 185, height: 37)
                }
            }.frame(width: 560, height: 60)); r.scale = 3
            if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "shots/\(n).png")) }
        }
        let cm = IslandModel(); cm.phase = .listening; cm.armed = true; cm.levels = [0.05, 0.3, 0.1, 0.45, 0.15, 0.35, 0.08, 0.25, 0.05]
        let cr = ImageRenderer(content: HStack(spacing: 2) {
            Text("Running five minutes late").font(.system(size: 15)).foregroundStyle(.black)
            Rectangle().fill(Color.blue).frame(width: 2, height: 18)
            CaretWaveView(m: cm).padding(.leading, 4)
        }.padding(12).background(Color.white)); cr.scale = 4
        if let tiff = cr.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "shots/glass-caret.png")) }
        print("Island renders → shots/")
        try? FileManager.default.createDirectory(atPath: "shots", withIntermediateDirectories: true)
        let levels: [CGFloat] = [0.2, 0.5, 0.9, 0.6, 0.3, 0.7, 1, 0.4, 0.2]
        let cases: [(String, IslandStyle, CGFloat, CGFloat, IslandModel.Phase, Bool)] = [
            ("notch-listening", .notch, 185, 32, .listening, false),
            ("notch-handsfree", .notch, 185, 32, .listening, true),
            ("notch-working", .notch, 185, 32, .working, false),
            ("notch-message", .notch, 185, 32, .message, false),
            ("island-listening", .island, 126, 34, .listening, false),
            ("island-handsfree", .island, 126, 34, .listening, true),
            ("island-working", .island, 126, 34, .working, false),
            ("island-message", .island, 126, 34, .message, false),
            ("floating-listening", .floating, 0, 30, .listening, false),
        ]
        for (name, style, cutout, bar, phase, hands) in cases {
            let m = IslandModel()
            m.style = style; m.cutoutWidth = cutout; m.barHeight = bar
            m.phase = phase; m.handsFree = hands; m.levels = levels
            m.message = "Downloading Parakeet… 42%"
            let menuBar = ZStack(alignment: .top) {
                Color(white: 0.93)
                Rectangle().fill(Color(white: 0.86)).frame(height: bar)
                // Stand-in for the physical cutout so we can see it's covered.
                if style == .island {
                    Capsule().fill(Color.red.opacity(0.6)).frame(width: cutout, height: bar - 10).padding(.top, 5)
                } else if style == .notch {
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(Color.red.opacity(0.6))
                        .frame(width: cutout, height: bar)
                }
                IslandView(m: m)
            }
            .frame(width: 560, height: 90)
            let r = ImageRenderer(content: menuBar); r.scale = 2
            if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "shots/\(name).png"))
            }
        }
        check(true, "rendered \(cases.count) states")
    }
}

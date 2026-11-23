import AppKit
import AVFoundation

/// `Spitball --mic-test` — records 3 s through the real Recorder and reports what came in.
enum MicTest {
    static func run() {
        // Dev tool: never leave the user's real setting changed.
        let saved = UserDefaults.standard.string(forKey: "noise")
        atexit_b { if let saved { UserDefaults.standard.set(saved, forKey: "noise") } else { UserDefaults.standard.removeObject(forKey: "noise") } }
        if CommandLine.arguments.contains("--caret") {
            print("accessibility trusted: \(AXIsProcessTrusted())")
            for i in 0..<4 {
                let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                let t = Date()
                let r = Caret.rect()
                print("\(i + 1). \(app): caret \(r.map { "at \(Int($0.minX)),\(Int($0.minY)) h\(Int($0.height))" } ?? "NOT FOUND") in \(Int(Date().timeIntervalSince(t) * 1000)) ms")
                Thread.sleep(forTimeInterval: 0.3)
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--route") {
            // Which mic would a dictation use right now, and does audio actually arrive?
            let def = AudioDevices.defaultInput()
            let name = { (id: AudioDeviceID?) in AudioDevices.inputs().first { $0.id == id }?.name ?? "system default" }
            print("default input: \(name(def))\(def.map { AudioDevices.isBluetooth($0) ? " (Bluetooth)" : "" } ?? "")")
            print("Spitball records from: \(name(AudioDevices.selected ?? def))")
            Settings.noise = .off
            let r = Recorder(); r.warmUp()
            for i in 0..<3 {
                let t = Date()
                try? r.start()
                Thread.sleep(forTimeInterval: 0.6)
                let n = r.sampleCount
                _ = r.stop()
                print("run \(i + 1): start→0.6 s, \(n) samples \(n > 0 ? "✓ audio arriving" : "✗ SILENT") (\(Int(Date().timeIntervalSince(t) * 1000)) ms)")
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--timing") {
            Settings.noise = CommandLine.arguments.contains("--vp") ? .always : .off
            let r = Recorder()
            for i in 0..<4 {
                let t = Date()
                try? r.start()
                let a = Int(Date().timeIntervalSince(t) * 1000)
                Thread.sleep(forTimeInterval: 0.3)
                let t2 = Date(); _ = r.stop()
                print("run \(i + 1): start \(a) ms, stop \(Int(Date().timeIntervalSince(t2) * 1000)) ms")
            }
            exit(0)
        }
        let engine = AVAudioEngine()
        let f = engine.inputNode.outputFormat(forBus: 0)
        print("input format: \(f)")
        nonisolated(unsafe) var peaks = [Float](repeating: 0, count: Int(f.channelCount))   // test tool only
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: f) { @Sendable b, _ in
            guard let ch = b.floatChannelData else { return }
            for c in 0..<Int(b.format.channelCount) {
                for i in 0..<Int(b.frameLength) { peaks[c] = max(peaks[c], abs(ch[c][i])) }
            }
        }
        try? engine.start()
        Thread.sleep(forTimeInterval: 1.5)
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        print("raw per-channel peaks: \(peaks.map { String(format: "%.4f", $0) })")

        Settings.noise = CommandLine.arguments.contains("--raw") ? .off : (CommandLine.arguments.contains("--smart") ? .smart : .always)
        let r = Recorder()
        var levels: [CGFloat] = []
        r.onBands = { levels.append(CGFloat($0.max() ?? 0)) }
        let ts = Date()
        defer {}
        do { try r.start(); print(String(format: "start took %.0fms", Date().timeIntervalSince(ts) * 1000)) } catch { print("recorder start failed: \(error)"); exit(1) }
        let end = Date() + 4
        while Date() < end { RunLoop.main.run(until: Date() + 0.05) }
        let s = r.stop()
        let peak = s.map(abs).max() ?? 0
        print("voice processing: \(r.usingVoiceProcessing)")
        print("recorder: \(s.count) samples (\(String(format: "%.2f", Double(s.count) / 16000))s), peak \(String(format: "%.4f", peak)), level reports \(levels.count), max level \(String(format: "%.2f", levels.max() ?? 0))")
        let apple = AppleEngine()
        let done = DispatchSemaphore(value: 0)
        Task {
            try? await apple.prepare {}
            let t = (try? await apple.transcribe(s)) ?? "(error)"
            print("transcript: \"\(t)\"")
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date() + 0.05) }
        exit(0)
    }
}

import AppKit
import AVFoundation
import CoreAudio
import FoundationModels
import Observation
import SwiftUI

// Voice notes and bot-free meeting notes.
// A voice note records your mic. A meeting also records what your Mac plays
// (the other people on Zoom, Meet, FaceTime…) through a Core Audio tap, so no
// bot joins the call. Each side is transcribed on its own, so the transcript
// knows who's "You" and who's "Them". Apple Intelligence writes the title,
// summary and action items. Nothing leaves your Mac.

nonisolated struct NoteLine: Codable, Equatable, Identifiable {
    var id = UUID()
    var at: Double            // seconds from the start
    var speaker: String       // "You" / "Them" (voice notes: "You")
    var text: String
}

nonisolated struct Note: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case voice, meeting }
    var id = UUID()
    var date: Date
    var kind: Kind
    var title: String
    var duration: Double = 0
    var lines: [NoteLine] = []
    var summary: [String] = []
    var actions: [String] = []
    var app: String?          // the call app, for meetings

    var transcript: String {
        lines.map { kind == .meeting ? "\($0.speaker): \($0.text)" : $0.text }.joined(separator: kind == .meeting ? "\n" : " ")
    }
    var words: Int { lines.reduce(0) { $0 + $1.text.split(separator: " ").count } }

    var markdown: String {
        var md = "# \(title)\n\n_\(date.formatted(date: .abbreviated, time: .shortened)) · \(Note.clock(duration))\((app.map { " · " + $0 }) ?? "")_\n\n"
        if !summary.isEmpty { md += "## Summary\n\n" + summary.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        if !actions.isEmpty { md += "## Action items\n\n" + actions.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n\n" }
        md += "## Transcript\n\n"
        md += kind == .meeting
            ? lines.map { "**\($0.speaker)** (\(Note.clock($0.at))): \($0.text)" }.joined(separator: "\n\n")
            : transcript
        return md + "\n"
    }

    static func clock(_ s: Double) -> String {
        let t = Int(s); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Capture

/// 16 kHz mono from the microphone, delivered in small chunks.
nonisolated final class MicCapture {
    private let engine = AVAudioEngine()
    var onSamples: (@Sendable ([Float]) -> Void)?   // called on the audio thread

    func start() throws {
        let input = engine.inputNode
        if let dev = AudioDevices.selected { AudioDevices.use(dev, on: engine) }
        let inFormat = AudioDevices.tapFormat(input)
        guard let conv = AVAudioConverter(from: inFormat, to: Recorder.format) else { throw DictationError.noEngine }
        try Recorder.objc {
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buf, _ in
                self?.onSamples?(Resample.convert(buf, with: conv))
            }
        }
        var startError: Error?
        try Recorder.objc { do { try self.engine.start() } catch { startError = error } }
        if let startError { throw startError }
    }

    func stop() { _ = try? Recorder.objc { self.engine.inputNode.removeTap(onBus: 0); self.engine.stop() } }
}

/// Everything your Mac plays (call audio), via a Core Audio process tap
/// (macOS 14.2+). macOS asks once for "System Audio Recording" permission.
nonisolated final class SystemAudioCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private var format: AVAudioFormat?
    private let queue = DispatchQueue(label: "spitball.systemaudio", qos: .userInitiated)
    var onSamples: (@Sendable ([Float]) -> Void)?   // called on the audio thread

    func start() throws {
        let me = Self.processObject(for: ProcessInfo.processInfo.processIdentifier)
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: me.map { [$0] } ?? [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        desc.name = "Spitball meeting notes"
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { throw NotesError.systemAudio }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd) == noErr,
              let fmt = AVAudioFormat(streamDescription: &asbd) else { stop(); throw NotesError.systemAudio }
        format = fmt
        converter = AVAudioConverter(from: fmt, to: Recorder.format)

        let outputUID = Self.defaultOutputUID() ?? ""
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Spitball Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else { stop(); throw NotesError.systemAudio }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { [weak self] _, input, _, _, _ in
            guard let self, let fmt = self.format, let conv = self.converter,
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: input, deallocator: nil) else { return }
            self.onSamples?(Resample.convert(buf, with: conv))
        }
        guard status == noErr, AudioDeviceStart(aggID, procID) == noErr else { stop(); throw NotesError.systemAudio }
    }

    func stop() {
        if aggID != kAudioObjectUnknown {
            if let procID { AudioDeviceStop(aggID, procID); AudioDeviceDestroyIOProcID(aggID, procID) }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggID = AudioObjectID(kAudioObjectUnknown); tapID = AudioObjectID(kAudioObjectUnknown); procID = nil
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = pid
        var obj = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &obj)
        return st == noErr && obj != kAudioObjectUnknown ? obj : nil
    }

    private static func defaultOutputUID() -> String? {
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}

nonisolated enum NotesError: LocalizedError {
    case systemAudio
    var errorDescription: String? { "Couldn't record call audio. Allow System Audio Recording for Spitball in Privacy & Security." }
}

nonisolated enum Resample {
    static func convert(_ buf: AVAudioPCMBuffer, with conv: AVAudioConverter) -> [Float] {
        let ratio = Recorder.format.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: Recorder.format, frameCapacity: cap) else { return [] }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard let ch = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
    }
}

// MARK: - Live note taking

/// Buffers one speaker's audio and transcribes it in ~20 s pieces, cut at a pause.
/// Lock-protected: audio threads append, the note taker reads.
nonisolated final class SpeakerStream: @unchecked Sendable {
    let speaker: String
    private var buffer: [Float] = []
    private var consumed = 0          // samples already transcribed
    private let lock = NSLock()
    init(speaker: String) { self.speaker = speaker }

    func append(_ s: [Float]) { lock.lock(); buffer += s; lock.unlock() }

    /// The next piece to transcribe: everything up to the quietest moment near ~20 s.
    func take(final: Bool) -> (start: Double, samples: [Float])? {
        lock.lock(); defer { lock.unlock() }
        let avail = buffer.count
        guard avail > 16_000 * (final ? 0 : 20) else {
            guard final, avail > 8_000 else { return nil }
            let out = buffer; buffer = []; let start = Double(consumed) / 16_000; consumed += out.count
            return (start, out)
        }
        var cut = avail
        if !final {
            // Quietest 200 ms in the last 5 s of the first 25 s.
            let end = min(avail, 16_000 * 25), from = max(0, end - 16_000 * 5), win = 3_200
            var best = Float.greatestFiniteMagnitude
            var i = from
            while i + win <= end {
                var e: Float = 0
                for j in stride(from: i, to: i + win, by: 4) { e += buffer[j] * buffer[j] }
                if e < best { best = e; cut = i + win / 2 }
                i += 800
            }
        }
        let out = Array(buffer[..<cut]); buffer.removeFirst(cut)
        let start = Double(consumed) / 16_000; consumed += cut
        return (start, out)
    }

    /// Mostly silence? (the other side said nothing in this piece)
    static func silent(_ s: [Float]) -> Bool {
        var e: Float = 0
        for i in stride(from: 0, to: s.count, by: 8) { e += s[i] * s[i] }
        return e / Float(max(1, s.count / 8)) < 1e-6
    }
}

@MainActor
@Observable final class Notetaker {
    static let shared = Notetaker()

    private(set) var current: Note?
    private(set) var elapsed: Double = 0
    private(set) var finishing = false
    var lastError: String?

    @ObservationIgnored var transcribe: (([Float]) async throws -> String)?
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var mic: MicCapture?
    @ObservationIgnored private var system: SystemAudioCapture?
    @ObservationIgnored private var streams: [SpeakerStream] = []
    @ObservationIgnored private var started = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pumping = false
    @ObservationIgnored private var activity: NSObjectProtocol?

    var isRecording: Bool { current != nil && !finishing }

    func toggle(_ kind: Note.Kind) { isRecording ? stop() : start(kind) }

    func start(_ kind: Note.Kind) {
        guard current == nil else { return }
        lastError = nil
        let callApp = NSWorkspace.shared.runningApplications.first { AppKind.callApps.contains($0.bundleIdentifier ?? "") }?.localizedName
        current = Note(date: Date(), kind: kind, title: kind == .meeting ? "Meeting" : "Voice note", app: kind == .meeting ? callApp : nil)
        let you = SpeakerStream(speaker: "You")
        streams = [you]
        let m = MicCapture(); m.onSamples = { you.append($0) }
        do { try m.start(); mic = m } catch { fail("Couldn't start the microphone"); return }
        if kind == .meeting {
            let them = SpeakerStream(speaker: "Them")
            let s = SystemAudioCapture(); s.onSamples = { them.append($0) }
            do { try s.start(); system = s; streams.append(them) } catch { lastError = error.localizedDescription }
        }
        started = Date(); elapsed = 0
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Recording a note")
        Bloop.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        onChange?()
        A11y.announce(kind == .meeting ? "Recording meeting notes" : "Recording a voice note")
    }

    func stop() {
        guard current != nil, !finishing else { return }
        finishing = true
        timer?.invalidate(); timer = nil
        mic?.stop(); mic = nil
        system?.stop(); system = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        Bloop.stop()
        onChange?()
        Task {
            await pump(final: true)
            guard var note = current else { return }
            note.duration = elapsed
            note.lines.sort { $0.at < $1.at }
            if !note.lines.isEmpty {
                let d = await Digest.make(from: note)
                note.title = d.title; note.summary = d.summary; note.actions = d.actions
                Store.shared.notes.insert(note, at: 0)
            }
            current = nil; finishing = false
            onChange?()
            A11y.announce(note.lines.isEmpty ? "Nothing was recorded" : "Note saved: \(note.title)")
        }
    }

    private func tick() {
        elapsed = Date().timeIntervalSince(started)
        Task { await pump(final: false) }
    }

    private func fail(_ msg: String) {
        lastError = msg; current = nil; mic?.stop(); mic = nil; system?.stop(); system = nil; onChange?()
    }

    /// Transcribe whatever's ready, one piece at a time.
    private func pump(final: Bool) async {
        if pumping && !final { return }
        while pumping { try? await Task.sleep(for: .milliseconds(50)) }
        pumping = true; defer { pumping = false }
        for s in streams {
            while let piece = s.take(final: final) {
                if s.speaker == "Them" && SpeakerStream.silent(piece.samples) { continue }
                guard let text = try? await transcribe?(piece.samples) else { continue }
                let clean = Typer.clean(text).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                current?.lines.append(NoteLine(at: piece.start, speaker: s.speaker, text: clean))
                if !final { break }
            }
        }
    }
}

extension AppKind {
    static let callApps: Set<String> = ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime", "com.cisco.webexmeetingsapp",
                                        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"]
}

// MARK: - Summaries (Apple Intelligence, on-device)

@Generable
struct NoteDigestOutput {
    @Guide(description: "A short, specific title for the note, 3 to 7 words, no quotes")
    var title: String
    @Guide(description: "The key points, 2 to 6 short bullet sentences")
    var keyPoints: [String]
    @Guide(description: "Every commitment or follow-up anyone made, each starting with who will do it if known (\"You\" for the user), then the task and any deadline. Empty if there are none.")
    var actionItems: [String]
}

nonisolated enum Digest {
    struct Result { var title: String; var summary: [String]; var actions: [String] }

    static func make(from note: Note) async -> Result {
        let fallback = Result(title: fallbackTitle(note), summary: [], actions: [])
        guard Polisher.available else { return fallback }
        let words = note.transcript.split(separator: " ")
        // The on-device model reads ~3,000 words at a time: summarize long notes in parts first.
        var source = note.transcript
        if words.count > 2_200 {
            var parts: [String] = []
            for chunk in stride(from: 0, to: words.count, by: 1_800).map({ words[$0..<min($0 + 1_800, words.count)].joined(separator: " ") }) {
                let s = LanguageModelSession(instructions: "Summarize this part of a transcript in 3 to 6 short bullet points. Keep names, numbers, decisions and to-dos.")
                if let r = try? await s.respond(to: chunk).content { parts.append(r) }
            }
            source = parts.joined(separator: "\n")
        }
        let session = LanguageModelSession(instructions: """
        You write notes from a transcript\(note.kind == .meeting ? " of a meeting. \"You\" is the user, \"Them\" is everyone else on the call" : " of a voice memo the user recorded").
        Be faithful: only include what was actually said.
        """)
        guard let out = try? await session.respond(to: source, generating: NoteDigestOutput.self).content else { return fallback }
        let title = out.title.trimmingCharacters(in: CharacterSet(charactersIn: "\"' .")).prefix(80)
        return Result(title: title.isEmpty ? fallback.title : String(title), summary: out.keyPoints, actions: out.actionItems)
    }

    static func fallbackTitle(_ note: Note) -> String {
        let first = note.lines.first?.text.split(separator: " ").prefix(6).joined(separator: " ") ?? ""
        return first.isEmpty ? (note.kind == .meeting ? "Meeting" : "Voice note") : first
    }
}

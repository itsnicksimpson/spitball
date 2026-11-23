import AVFoundation
import CoreAudio
import Observation
import SwiftUI

/// Input devices (built-in mic, AirPods, USB mics…), via Core Audio.
nonisolated enum AudioDevices {
    struct Device: Hashable, Identifiable { let id: AudioDeviceID; let uid: String; let name: String }

    static func inputs() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            if uid.hasPrefix("CADefaultDeviceAggregate") { return nil }   // hide macOS-internal aggregates
            return Device(id: id, uid: uid, name: name)
        }
    }

    /// The device to record from:
    /// 1. the mic you picked in Settings, if it's connected;
    /// 2. otherwise, if the default input is Bluetooth headphones (AirPods), the Mac's own mic,
    ///    unless you turned that off. Recording from AirPods drops them into low-quality call
    ///    mode, pauses your music's quality, and breaks whenever they hop to your iPhone;
    /// 3. otherwise nil (= the system default).
    static var selected: AudioDeviceID? {
        if let uid = UserDefaults.standard.string(forKey: "micUID"), !uid.isEmpty,
           let picked = inputs().first(where: { $0.uid == uid })?.id { return picked }
        let avoidBT = UserDefaults.standard.object(forKey: "avoidBluetoothMic") as? Bool ?? true
        let def = defaultInput()
        // No usable default (AirPods mid-handoff report device 0, or a vanished device):
        // never record from "nothing", use the Mac's mic.
        guard let def, isAlive(def), inputs().contains(where: { $0.id == def }) else { return builtInMic() }
        if (avoidBT && isBluetooth(def)) || forceBuiltIn, let mac = builtInMic() { return mac }
        return nil
    }

    /// The real mics plus the default one, as text: changes only when hardware does.
    static func signature() -> String {
        inputs().map(\.uid).sorted().joined(separator: "|") + "→" + (defaultInput().flatMap { id in inputs().first { $0.id == id }?.uid } ?? "none")
    }

    /// Is there any mic we can record from right now?
    static func hasUsableInput() -> Bool {
        if let d = selected { return isAlive(d) }
        if let d = defaultInput() { return isAlive(d) }
        return false
    }

    static func isAlive(_ id: AudioDeviceID) -> Bool {
        guard id != 0 else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var alive = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &alive) == noErr && alive != 0
    }

    /// Set for the rest of a session when the default mic stopped answering.
    nonisolated(unsafe) static var forceBuiltIn = false

    static func defaultInput() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func transport(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var t = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t) == noErr ? t : 0
    }

    static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        let t = transport(id)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    /// The Mac's own microphone (nil on a Mac mini/Studio without one, or a closed laptop).
    static func builtInMic() -> AudioDeviceID? {
        inputs().first { transport($0.id) == kAudioDeviceTransportTypeBuiltIn }?.id
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    /// The format to tap the mic with. After `use(_:on:)` points the engine at a device
    /// other than the system default, `outputFormat` can still describe the OLD device
    /// (e.g. AirPods' rate) and installing a tap with it throws. The input side always
    /// reflects the hardware actually in use.
    static func tapFormat(_ node: AVAudioInputNode) -> AVAudioFormat {
        let hw = node.inputFormat(forBus: 0), out = node.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.sampleRate != out.sampleRate || hw.channelCount != out.channelCount else { return out }
        return AVAudioFormat(standardFormatWithSampleRate: hw.sampleRate, channels: hw.channelCount) ?? out
    }

    /// Point an engine's input at a specific device (must happen before prepare/start).
    static func use(_ device: AudioDeviceID, on engine: AVAudioEngine) {
        guard let unit = engine.inputNode.audioUnit else { return }
        var id = device
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}

/// A live input meter for Settings: is the mic actually hearing me?
@Observable final class MicMeter {
    var level: CGFloat = 0
    var running = false
    @ObservationIgnored private var engine: AVAudioEngine?

    func start() {
        stop()
        let e = AVAudioEngine()
        if let dev = AudioDevices.selected { AudioDevices.use(dev, on: e) }
        let f = AudioDevices.tapFormat(e.inputNode)
        guard f.sampleRate > 0 else { return }
        let ok = (try? Recorder.objc {
        e.inputNode.installTap(onBus: 0, bufferSize: 1024, format: f) { @Sendable [weak self] b, _ in   // audio thread
            guard let ch = b.floatChannelData?[0], b.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(b.frameLength) { sum += ch[i] * ch[i] }
            let db = 20 * log10(max(sqrt(sum / Float(b.frameLength)), 1e-7))
            let v = CGFloat(min(1, max(0, (db + 60) / 50)))
            Task { @MainActor in if let self { self.level += (v - self.level) * 0.5 } }
        }
        }) != nil
        guard ok else { return }
        var started = false
        _ = try? Recorder.objc { started = (try? e.start()) != nil }
        if started { engine = e; running = true } else { _ = try? Recorder.objc { e.inputNode.removeTap(onBus: 0) } }
    }

    func stop() {
        if let e = engine { _ = try? Recorder.objc { e.inputNode.removeTap(onBus: 0); e.stop() } }; engine = nil
        running = false; level = 0
    }
}

/// 20-segment LCD meter.
struct LevelMeter: View {
    let level: CGFloat
    let theme: RetroTheme
    var body: some View {
        Group {
            if Skin.isPro {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.07))
                        Capsule().fill(Color.black).frame(width: max(6, g.size.width * min(1, level)))
                            .animation(.easeOut(duration: 0.08), value: level)
                    }
                }
                .frame(height: 6)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { i in
                        Rectangle().fill(CGFloat(i) / 20 < level ? (i > 16 ? theme.accent : theme.bottom) : theme.bottom.opacity(0.15))
                    }
                }
                .frame(height: 12)
                .padding(4)
                .background(theme.ink)
            }
        }
        .accessibilityElement().accessibilityLabel("Microphone level").accessibilityValue("\(Int(level * 100)) percent")
    }
}

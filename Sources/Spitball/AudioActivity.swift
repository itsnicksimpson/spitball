import AppKit
import CoreAudio
import Foundation

/// "Are you on a call?" — true when any other app is actively recording from a mic
/// (FaceTime, Zoom, Meet, Teams, Discord…). Used to switch on echo + noise
/// cancellation only when it's worth its ~1 s start-up cost.
///
/// We deliberately don't key off speaker output: plenty of idle apps keep an output
/// stream open, so "output running" doesn't mean anything is audible.
nonisolated enum AudioActivity {
    static func onCall() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        return processObjects().contains { obj in
            let pid: pid_t = prop(obj, kAudioProcessPropertyPID, 0)
            let input: UInt32 = prop(obj, kAudioProcessPropertyIsRunningInput, 0)
            return pid != me && input != 0 && countsAsCall(pid)
        }
    }

    /// Real apps (Zoom, Meet in a browser, Teams, Discord, Slack…) count. FaceTime and
    /// iPhone calls run their audio in a system daemon, which only counts while the
    /// FaceTime or Phone app is open, so an idle system service can't fool us.
    private static func countsAsCall(_ pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return true }
        let callApps: Set<String> = ["com.apple.FaceTime", "com.apple.mobilephone"]
        let callAppOpen = NSWorkspace.shared.runningApplications.contains { callApps.contains($0.bundleIdentifier ?? "") }
        guard callAppOpen else { return false }
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, 256)
        let n = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return n == "avconferenced" || n == "callservicesd"
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func prop<T: BitwiseCopyable>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ fallback: T) -> T {
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value) == noErr ? value : fallback
    }
}

import Accelerate
import Foundation

/// Turns mic audio into 5 frequency bands shaped like a voice (low → high), each
/// with its own auto-gain so the bars follow *your* voice on any mic, in any room.
/// Fast attack, soft release: bars jump when you speak and settle naturally.
nonisolated final class VoiceMeter {
    static let bandCount = 5
    private let n = 1024
    private let fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window: [Float]
    private let edges: [Double] = [90, 220, 450, 900, 1800, 4000]   // Hz, speech range
    private var floorDB = [Float](repeating: -80, count: VoiceMeter.bandCount)
    private var peakDB = [Float](repeating: -40, count: VoiceMeter.bandCount)
    private var smooth = [Float](repeating: 0, count: VoiceMeter.bandCount)
    private var ring = [Float]()

    init() { window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 1024, isHalfWindow: false) }

    func reset() {
        floorDB = .init(repeating: -80, count: Self.bandCount)
        peakDB = .init(repeating: -40, count: Self.bandCount)
        smooth = .init(repeating: 0, count: Self.bandCount)
        ring.removeAll()
    }

    /// Feed mono samples; returns 0…1 per band.
    func process(_ x: UnsafePointer<Float>, count: Int, sampleRate: Double) -> [Float] {
        ring.append(contentsOf: UnsafeBufferPointer(start: x, count: count))
        if ring.count > n { ring.removeFirst(ring.count - n) }
        guard ring.count == n else { return smooth }

        var frame = vDSP.multiply(ring, window)
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeMutableBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                }
                fft.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }

        let hzPerBin = sampleRate / Double(n)
        var out = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let lo = max(1, Int(edges[b] / hzPerBin)), hi = min(n / 2 - 1, max(lo + 1, Int(edges[b + 1] / hzPerBin)))
            var e: Float = 0
            for i in lo..<hi { e += mags[i] }
            let db = 10 * log10(max(e / Float(hi - lo), 1e-12))
            // Learn this band's noise floor (drops fast, creeps up slowly) and loudness.
            floorDB[b] = db < floorDB[b] ? db : floorDB[b] + 0.04
            peakDB[b] = max(peakDB[b] - 0.12, db, floorDB[b] + 20)
            let target = min(1, max(0, (db - floorDB[b] - 5) / (peakDB[b] - floorDB[b] - 5)))
            // Fast attack, gentle release.
            smooth[b] += (target - smooth[b]) * (target > smooth[b] ? 0.6 : 0.18)
            out[b] = smooth[b]
        }
        return out
    }
}

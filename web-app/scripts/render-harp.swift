// Renders the cantor guide's harp for the web app: one recording for each
// key, struck and left to ring.
//
// The native app plays `ConcertHarp.sf2` through AVAudioUnitSampler, rendered
// offline (`SampledHarpRenderer` in HoursApp/ChantPlaybackController.swift).
// A browser has no sampler, so the same sampler is run here, with the same
// program, tuning, and velocity, and what it plays is kept. The web app then
// does to these recordings what the native renderer does to the sampler's
// output.
//
// usage: render-harp BANK.sf2 OUTPUT_DIRECTORY LOWEST_KEY HIGHEST_KEY
//
// Writes OUTPUT_DIRECTORY/<key>.flac for every key and prints, as JSON, the
// peak and length of each. The sampler streams the bank from disk and, when
// the disk is slow to answer, leaves a hole in what it renders; every key is
// therefore rendered twice and must come out the same both times.

import AVFoundation
import Foundation

/// As `HarpSoundBank` and `SampledHarpRenderer` have them.
let program: UInt8 = 0
let tuningCorrection: Float = 7
let velocity: UInt8 = 58

/// Most outputs run at this rate, and a recording at the output's own rate
/// is used as it is.
let sampleRate = 48_000.0
/// The longest note the guide sings is under a second and a quarter.
let seconds = 2.0
let attempts = 4

struct RenderError: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-harp: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 5,
      let lowest = UInt8(arguments[3]),
      let highest = UInt8(arguments[4]),
      lowest <= highest, highest <= 127 else {
    fail("usage: render-harp BANK.sf2 OUTPUT_DIRECTORY LOWEST_KEY HIGHEST_KEY")
}
let bankURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
let frameCount = Int(seconds * sampleRate)

func render(_ key: UInt8, pause: UInt32) throws -> [Float] {
    // A sampler of its own for every key, so that none hears the last.
    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    try sampler.loadSoundBankInstrument(
        at: bankURL,
        program: program,
        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
        bankLSB: UInt8(kAUSampler_DefaultBankLSB)
    )
    sampler.globalTuning = tuningCorrection
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
    guard let scratch = AVAudioPCMBuffer(
        pcmFormat: engine.manualRenderingFormat,
        frameCapacity: engine.manualRenderingMaximumFrameCount
    ) else {
        throw RenderError(description: "no buffer for key \(key)")
    }
    try engine.start()
    defer { engine.stop() }
    sampler.sendController(120, withValue: 0, onChannel: 0)
    sampler.startNote(key, withVelocity: velocity, onChannel: 0)

    var samples: [Float] = []
    samples.reserveCapacity(frameCount)
    var stalls = 0
    while samples.count < frameCount {
        let requested = AVAudioFrameCount(min(4_096, frameCount - samples.count))
        switch try engine.renderOffline(requested, to: scratch) {
        case .success:
            guard let channel = scratch.floatChannelData?[0] else {
                throw RenderError(description: "no samples for key \(key)")
            }
            samples.append(
                contentsOf: UnsafeBufferPointer(start: channel, count: Int(scratch.frameLength))
            )
            stalls = 0
            if pause > 0 { usleep(pause) }
        case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
            stalls += 1
            if stalls > 16 { throw RenderError(description: "the render of key \(key) stalled") }
        default:
            throw RenderError(description: "the render of key \(key) failed")
        }
    }
    return samples
}

/// The longest silence within the sounding part of a recording, in frames.
func longestHole(in samples: [Float]) -> Int {
    guard let last = samples.lastIndex(where: { abs($0) > 1e-4 }) else { return 0 }
    var longest = 0
    var run = 0
    for sample in samples[..<last] {
        run = sample == 0 ? run + 1 : 0
        longest = max(longest, run)
    }
    return longest
}

func verifiedRender(_ key: UInt8) throws -> [Float] {
    for attempt in 0..<attempts {
        // Give the sampler's reader more time on each new attempt.
        let pause = UInt32(attempt * 2_000)
        let first = try render(key, pause: pause)
        let second = try render(key, pause: pause)
        if first == second, longestHole(in: first) < 64 {
            return first
        }
    }
    throw RenderError(description: "key \(key) did not render the same way twice")
}

func write(_ samples: [Float], to url: URL) throws {
    // Sixteen bits hold what the sampler gave with room to spare, in a
    // quarter of the bytes the encoder spends on a float.
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatFLAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
    ]
    let file = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatInt16,
        interleaved: false
    )
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(samples.count)
    ), let channel = buffer.int16ChannelData?[0] else {
        throw RenderError(description: "no buffer to write \(url.lastPathComponent)")
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (frame, sample) in samples.enumerated() {
        channel[frame] = Int16(max(-32_768, min(32_767, (sample * 32_768).rounded())))
    }
    try file.write(from: buffer)
}

do {
    // Reading the bank through once leaves it where the sampler finds it fast.
    _ = try Data(contentsOf: bankURL)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    var keys: [[String: Any]] = []
    for key in lowest...highest {
        let samples = try verifiedRender(key)
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0.01 else {
            throw RenderError(description: "the bank is silent at key \(key)")
        }
        guard peak < 0.4 else {
            // 16 bits keep the samples as the sampler gave them only below full scale.
            throw RenderError(description: "key \(key) is louder than the web app allows for")
        }
        try write(samples, to: outputDirectory.appendingPathComponent("\(key).flac"))
        keys.append(["key": Int(key), "peak": Double(peak)])
    }
    let report: [String: Any] = [
        "sampleRate": sampleRate,
        "seconds": seconds,
        "velocity": Int(velocity),
        "tuningCorrection": Double(tuningCorrection),
        "keys": keys,
    ]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    FileHandle.standardOutput.write(json)
} catch {
    fail("\(error)")
}

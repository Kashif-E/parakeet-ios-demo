import Foundation
import MoonshineVoice

/// Moonshine on-device streaming recognizer, for the three-way compare.
/// Feed the same 16 kHz mono PCM as Parakeet; it accumulates transcript lines.
final class MoonshineTranscriber {
    private var transcriber: Transcriber?
    private var lines: [UInt64: String] = [:]   // lineId -> text
    private var order: [UInt64] = []

    /// Full accumulated transcript on each update.
    var onText: ((String) -> Void)?

    /// `modelDir` is a directory of model files (encoder/decoder .ort + tokenizer.bin).
    func start(modelDir: String, arch: ModelArch = .base) throws {
        let t = try Transcriber(modelPath: modelDir, modelArch: arch)
        transcriber = t
        try t.addListener { [weak self] event in self?.handle(event) }
        try t.start()
    }

    /// Feed PCM (any sample rate; we pass 16 kHz mono floats). Off the main thread.
    func feed(_ pcm: [Float], sampleRate: Int32 = 16000) {
        try? transcriber?.addAudio(pcm, sampleRate: sampleRate)
    }

    func stop() {
        try? transcriber?.stop()
        transcriber?.close()
        transcriber = nil
    }

    private func line(of e: TranscriptEvent) -> TranscriptLine? {
        switch e {
        case let x as LineStarted:     return x.line
        case let x as LineUpdated:     return x.line
        case let x as LineTextChanged: return x.line
        case let x as LineCompleted:   return x.line
        default:                       return nil
        }
    }

    private func handle(_ event: TranscriptEvent) {
        guard let l = line(of: event) else { return }
        if lines[l.lineId] == nil { order.append(l.lineId) }
        lines[l.lineId] = l.text
        let full = order.compactMap { lines[$0] }.joined(separator: " ")
        onText?(full)
    }
}

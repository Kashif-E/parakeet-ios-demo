import AVFoundation
import Speech

/// Apple's on-device streaming recognizer (iOS 26 SpeechAnalyzer + SpeechTranscriber),
/// for side-by-side comparison against Parakeet. Feed it the same mic buffers; it
/// publishes live (volatile) and finalized text.
@available(iOS 26.0, *)
final class AppleTranscriber {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?

    /// (text, isFinal) on each result. text is the recognizer's current best.
    var onText: ((String, Bool) -> Void)?

    func start(locale: Locale = Locale(identifier: "en-US")) async throws {
        // Speech recognition permission (separate from microphone).
        let status = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        NSLog("[apple] auth status = %ld", status.rawValue)
        guard status == .authorized else {
            throw NSError(domain: "AppleTranscriber", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech permission not granted (status \(status.rawValue))"])
        }

        // Resolve to a region-specific supported locale — the picker gives bare
        // "en", but the transcriber needs e.g. "en_US" (else: "unsupported
        // configuration"). Prefer US region, else any region of the same language.
        let supported = await SpeechTranscriber.supportedLocales
        let reqLang = locale.language.languageCode?.identifier
        let resolved = supported.first { $0.language.languageCode?.identifier == reqLang && $0.region?.identifier == "US" }
            ?? supported.first { $0.language.languageCode?.identifier == reqLang }
            ?? Locale(identifier: "en-US")
        NSLog("[apple] resolved locale = %@", resolved.identifier)

        // .progressiveTranscription = streaming volatile (partial) + final results.
        let t = SpeechTranscriber(locale: resolved, preset: .progressiveTranscription)
        transcriber = t

        let installed = await SpeechTranscriber.installedLocales.map(\.identifier)
        NSLog("[apple] installed locales = %@", "\(installed)")
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            NSLog("[apple] downloading locale model…")
            try await req.downloadAndInstall()
            NSLog("[apple] model installed")
        } else {
            NSLog("[apple] no install request (already installed or unsupported)")
        }

        let a = SpeechAnalyzer(modules: [t])
        analyzer = a
        inputFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
        guard inputFormat != nil else {
            throw NSError(domain: "AppleTranscriber", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                            "no audio format for locale \(locale.identifier) — model may not be installed/supported"])
        }

        resultsTask = Task { [weak self] in
            do {
                for try await result in t.results {
                    NSLog("[apple] result isFinal=%d text=%@", result.isFinal, String(result.text.characters))
                    self?.onText?(String(result.text.characters), result.isFinal)
                }
            } catch {
                NSLog("[apple] results stream error: %@", error.localizedDescription)
            }
        }

        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = cont
        try await a.start(inputSequence: stream)
    }

    /// Feed a mic buffer (any format) — converted to the recognizer's format. Thread-safe.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let cont = continuation, let outFmt = inputFormat else { return }
        if converter == nil || converter?.outputFormat != outFmt {
            converter = AVAudioConverter(from: buffer.format, to: outFmt)
        }
        guard let conv = converter else { return }
        let ratio = outFmt.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        if err == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
    }

    func stop() async {
        continuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        analyzer = nil; transcriber = nil; continuation = nil
    }
}

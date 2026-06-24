import AVFoundation
import SwiftUI

/// Ties the mic stream to the model and publishes UI state.
@MainActor
final class TranscriberModel: ObservableObject {
    @Published var transcript = ""
    @Published var levels: [Float] = Array(repeating: 0, count: 64)  // waveform ring
    @Published var isRecording = false
    @Published var status = "Tap to start"
    @Published var lang = "en"   // forced language; "auto" tends to mis-detect

    // Compare mode: run Apple's on-device recognizer (iOS 26) on the same mic
    // audio, side by side, to judge which transcribes better.
    @Published var compareMode = false
    @Published var appleTranscript = ""
    @Published var moonshineTranscript = ""
    private var appleFinal = ""   // committed Apple text; volatile result previews the tail
    private var moonshine: MoonshineTranscriber?
    var appleAvailable: Bool { if #available(iOS 26.0, *) { return true } else { return false } }
    private var apple: Any?   // AppleTranscriber (typed via #available)

    // Display name -> model locale token. Edit freely — an unknown token makes
    // begin() throw (surfaced in `status`).
    let languages: [(name: String, code: String)] = [
        ("Auto-detect", "auto"), ("English", "en"), ("Spanish", "es"),
        ("French", "fr"), ("German", "de"), ("Italian", "it"),
        ("Portuguese", "pt"), ("Dutch", "nl"), ("Russian", "ru"),
        ("Japanese", "ja"), ("Korean", "ko"), ("Chinese", "zh"),
        ("Arabic", "ar"), ("Hindi", "hi"), ("Turkish", "tr"),
    ]

    private let audio = AudioStreamer()
    private var session: ParakeetSession?
    private let work = DispatchQueue(label: "cpp.parakeet.feed")

    func toggle() { isRecording ? stop() : start() }

    /// Load + warm the model at app launch (off the main thread) so the first
    /// tap is instant instead of showing "Loading model…". Idempotent.
    func preload() async {
        guard session == nil else { return }
        status = "Loading model…"
        do {
            session = try await Task.detached { let s = try ParakeetSession(); s.warmup(); return s }.value
            status = "Tap to start"
        } catch {
            status = "Error: \(error)"
        }
    }

    private func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.status = "Microphone denied"; return }
                do {
                    if self.session == nil {
                        self.status = "Loading model…"
                        // Load + warm up (compile Metal kernels) off the main
                        // thread; both are heavy and hidden behind this status.
                        self.session = try await Task.detached {
                            let s = try ParakeetSession()
                            s.warmup()
                            return s
                        }.value
                    }
                    try self.session?.begin(lang: self.lang)
                    self.transcript = ""
                    self.appleTranscript = ""
                    self.moonshineTranscript = ""
                    self.audio.onPCM = { [weak self] pcm, level in self?.feed(pcm, level) }
                    self.audio.onBuffer = nil
                    // Compare mode: Moonshine on the same 16 kHz PCM as Parakeet.
                    if self.compareMode, let dir = Bundle.main.url(forResource: "base-en", withExtension: nil)?.path {
                        let m = MoonshineTranscriber()
                        m.onText = { [weak self] text in Task { @MainActor in self?.moonshineTranscript = text } }
                        do {
                            try await Task.detached { try m.start(modelDir: dir) }.value
                            self.moonshine = m
                            let parakeetFeed = self.audio.onPCM
                            self.audio.onPCM = { pcm, level in parakeetFeed?(pcm, level); m.feed(pcm) }
                        } catch {
                            self.moonshineTranscript = "⚠️ \(error.localizedDescription)"
                        }
                    }
                    // Compare mode: start Apple's recognizer on the same audio.
                    if self.compareMode, #available(iOS 26.0, *) {
                        self.appleFinal = ""
                        let a = AppleTranscriber()
                        a.onText = { [weak self] text, isFinal in
                            Task { @MainActor in
                                guard let self else { return }
                                if isFinal {
                                    // Commit this segment; clear the volatile tail.
                                    if !self.appleFinal.isEmpty { self.appleFinal += " " }
                                    self.appleFinal += text
                                    self.appleTranscript = self.appleFinal
                                } else {
                                    // Volatile: preview the in-progress segment after committed text.
                                    self.appleTranscript = self.appleFinal.isEmpty ? text : self.appleFinal + " " + text
                                }
                            }
                        }
                        self.apple = a
                        self.audio.onBuffer = { a.feed($0) }
                        do {
                            try await a.start(locale: Locale(identifier: self.lang == "auto" ? "en-US" : self.lang))
                        } catch {
                            self.appleTranscript = "⚠️ \(error.localizedDescription)"
                        }
                    }
                    // Start the engine off the main thread — AVAudioSession.setActive
                    // on main logs a UI-responsiveness warning.
                    Task.detached {
                        do {
                            try self.audio.start()
                            await MainActor.run { self.isRecording = true; self.status = "Listening…" }
                        } catch {
                            await MainActor.run { self.status = "Error: \(error)" }
                        }
                    }
                } catch {
                    self.status = "Error: \(error)"
                }
            }
        }
    }

    private func stop() {
        isRecording = false
        status = "Finishing…"
        if #available(iOS 26.0, *), let a = apple as? AppleTranscriber {
            Task { await a.stop() }
        }
        apple = nil
        moonshine?.stop()
        moonshine = nil
        work.async { [weak self] in
            guard let self else { return }
            self.audio.stop()                       // AVAudioSession.setActive(false) off the main thread
            let tail = self.session?.finalize() ?? ""
            Task { @MainActor in
                if !tail.isEmpty { self.transcript += tail }
                self.status = "Tap to start"
            }
        }
    }

    // Called on the audio thread.
    private nonisolated func feed(_ pcm: [Float], _ level: Float) {
        Task { @MainActor in self.pushLevel(level) }
        work.async { [weak self] in
            guard let self, let s = self.session else { return }
            let (raw, mask) = s.feed(pcm)
            // Strip inline language tags like "<en-US>" (EOU/EOB are already gone).
            let text = raw.contains("<")
                ? raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                : raw
            guard !text.isEmpty || mask != 0 else { return }
            Task { @MainActor in
                if !text.isEmpty { self.transcript += text }
                if mask & Int32(PARAKEET_EVENT_EOU) != 0 { self.transcript += "\n" }
            }
        }
    }

    private func pushLevel(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }
}

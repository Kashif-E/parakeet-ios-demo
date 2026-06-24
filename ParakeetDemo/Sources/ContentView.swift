import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = TranscriberModel()

    var body: some View {
        VStack(spacing: 24) {
            // Top: live audio waveform.
            Waveform(levels: model.levels)
                .frame(height: 120)
                .padding(.horizontal)

            // Middle: start / stop.
            Button(action: model.toggle) {
                Image(systemName: model.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .resizable()
                    .frame(width: 84, height: 84)
                    .foregroundStyle(model.isRecording ? .red : .accentColor)
            }
            Text(model.status).font(.footnote).foregroundStyle(.secondary)

            // Language + compare toggle — disabled while recording.
            HStack {
                Picker("Language", selection: $model.lang) {
                    ForEach(model.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                .pickerStyle(.menu)
                Toggle("Compare", isOn: $model.compareMode).fixedSize()
            }
            .disabled(model.isRecording)
            .padding(.horizontal)

            // Bottom: live transcription. In compare mode, stack the engines.
            if model.compareMode {
                VStack(spacing: 8) {
                    transcriptPane("Parakeet", model.transcript)
                    if model.appleAvailable {
                        transcriptPane("Apple", model.appleTranscript)
                    }
                    transcriptPane("Moonshine", model.moonshineTranscript)
                }
                .padding(.horizontal)
            } else {
                transcriptPane(nil, model.transcript).padding(.horizontal)
            }
        }
        .padding(.vertical)
        .task { await model.preload() }   // load + warm at launch; first tap is instant
    }

    @ViewBuilder
    private func transcriptPane(_ title: String?, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(text.isEmpty)
                .font(.caption)
            }
            ScrollView {
                Text(text.isEmpty ? "…" : text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Minimal bar waveform driven by the level ring buffer. Native Canvas, no deps.
struct Waveform: View {
    let levels: [Float]
    var body: some View {
        Canvas { ctx, size in
            let n = levels.count
            guard n > 0 else { return }
            let w = size.width / CGFloat(n)
            for (i, lvl) in levels.enumerated() {
                let h = max(2, CGFloat(lvl) * size.height)
                let x = CGFloat(i) * w
                let rect = CGRect(x: x + 1, y: (size.height - h) / 2, width: w - 2, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.accentColor))
            }
        }
    }
}

import FluidAudio
import MecoScribeCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: TranscriptionSettings

    var body: some View {
        Form {
            Section("Diarization") {
                Picker("Mode", selection: $settings.diarizationMode) {
                    Text("Offline").tag(ScribeProcessor.DiarizationMode.offline)
                    Text("Streaming").tag(ScribeProcessor.DiarizationMode.streaming)
                }
                HStack {
                    Text("Threshold")
                    Slider(value: $settings.threshold, in: 0.3...0.9)
                    Text(String(format: "%.2f", settings.threshold))
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("Transcription") {
                Picker("ASR Model", selection: $settings.modelVersion) {
                    Text("v3 — Multilingual").tag(AsrModelVersion.v3)
                    Text("v2 — English only").tag(AsrModelVersion.v2)
                }
                TextField("Models directory (optional)", text: $settings.modelsDirectory)
                TextField("Local ASR model directory (optional)", text: $settings.modelDir)
            }

            Section("Speaker Names") {
                TextField("Comma-separated names", text: Binding(
                    get: { settings.presetSpeakerNames.joined(separator: ", ") },
                    set: {
                        settings.presetSpeakerNames = $0
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
        .padding()
    }
}

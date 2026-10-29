import MecoScribeCore
import SwiftUI

struct NewTranscriptionView: View {
    let workspace: Workspace
    @Bindable var setup: TranscriptionSetup
    @State private var isDropTargeted = false
    @AppStorage(Preferences.modelsDirectory) private var modelsDirectory = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Audio") {
                    LabeledContent("File") {
                        HStack {
                            if let audio = setup.audioURL {
                                Label(audio.lastPathComponent, systemImage: "waveform")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(audio.path)
                            } else {
                                Text("Drop an audio file here or choose one")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Choose…") {
                                if let url = FilePanels.chooseAudio() { setup.audioURL = url }
                            }
                        }
                    }
                    LabeledContent("Save transcript to") {
                        HStack {
                            Text(outputLabel)
                                .foregroundStyle(setup.outputDirectory == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            if setup.outputDirectory != nil {
                                Button("Reset") { setup.outputDirectory = nil }
                            }
                            Button("Choose…") {
                                if let url = FilePanels.chooseDirectory(
                                    title: "Output Folder",
                                    startingAt: setup.resolvedOutputDirectory
                                ) {
                                    setup.outputDirectory = url
                                }
                            }
                        }
                    }
                }

                if let existing = setup.existingTranscript {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                "A transcript already exists: \(existing.lastPathComponent)",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                            Text(existingHelp(existing))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Open Existing") { workspace.open(existing) }
                        }
                    }
                }

                Section("Speakers") {
                    Picker("Diarization", selection: $setup.diarizationMode) {
                        ForEach(ScribeProcessor.DiarizationMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    LabeledContent {
                        HStack {
                            Slider(value: $setup.threshold, in: 0.1...0.95, step: 0.05)
                            Text(setup.threshold, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                        }
                    } label: {
                        Text("Threshold")
                        Text(thresholdHelp)
                    }
                    TextField(
                        "Speaker names",
                        text: $setup.speakerNamesText,
                        prompt: Text("Optional, e.g. Alice, Bob, Carol")
                    )
                }

                Section("Speech Recognition") {
                    Picker("Model", selection: $setup.asrChoice) {
                        ForEach(ASRChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    if setup.asrChoice == .nemotron3 {
                        LabeledContent("Language") {
                            HStack {
                                TextField("Language", text: $setup.language, prompt: Text("auto"))
                                    .labelsHidden()
                                Menu {
                                    ForEach(NemotronOptions.languages, id: \.self) { code in
                                        Button(code) { setup.language = code }
                                    }
                                } label: {
                                    Image(systemName: "globe")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                        Picker("Chunk size", selection: $setup.chunkMs) {
                            ForEach(NemotronOptions.chunkTiers, id: \.self) { tier in
                                Text("\(tier) ms").tag(tier)
                            }
                        }
                    }
                }

                Section("Models") {
                    LabeledContent("Model cache") {
                        HStack {
                            Text(Preferences.modelsDirectoryURL.path(percentEncoded: false))
                                .lineLimit(1)
                                .truncationMode(.head)
                                .help(Preferences.modelsDirectoryURL.path)
                            Spacer()
                            if !modelsDirectory.isEmpty {
                                Button("Reset") { modelsDirectory = "" }
                            }
                            Button("Choose…") {
                                if let url = FilePanels.chooseDirectory(
                                    title: "Model Cache Folder",
                                    startingAt: Preferences.modelsDirectoryURL
                                ) {
                                    modelsDirectory = url.path
                                }
                            }
                        }
                    }
                    LabeledContent("Local ASR models") {
                        HStack {
                            Text(setup.localModelDirectory?.path(percentEncoded: false) ?? "None (download automatically)")
                                .foregroundStyle(setup.localModelDirectory == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            if setup.localModelDirectory != nil {
                                Button("Clear") { setup.localModelDirectory = nil }
                            }
                            Button("Choose…") {
                                setup.localModelDirectory = FilePanels.chooseDirectory(title: "Local ASR Model Folder")
                            }
                        }
                    }
                    Text("Models download from Hugging Face on first use and are reused afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { workspace.showWelcome() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(setup.existingTranscript == nil ? "Transcribe" : "Transcribe Again") {
                    if let request = setup.makeRequest() {
                        workspace.startTranscription(request)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(setup.audioURL == nil)
            }
            .padding()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            FileDrop.loadFirstURL(from: providers) { url in
                if ProjectLoader.isAudio(url) { setup.audioURL = url }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private func existingHelp(_ url: URL) -> String {
        if ProjectLoader.isProject(url) {
            return "Open it, or transcribe again and replace it."
        }
        return "Open it (it is converted to a .mscribe project), or transcribe again to create a new project."
    }

    private var outputLabel: String {
        if let directory = setup.outputDirectory {
            return directory.path(percentEncoded: false)
        }
        return "Same folder as the audio file"
    }

    private var thresholdHelp: String {
        setup.diarizationMode == .nemotron3
            ? "Speaker activity threshold"
            : "Speaker clustering threshold"
    }
}

struct TranscriptionProgressView: View {
    let workspace: Workspace
    let job: TranscriptionJob

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: job.errorMessage == nil)
                Text(job.request.audioURL.lastPathComponent)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimelineView(.periodic(from: job.startedAt, by: 1)) { context in
                    Text("Elapsed \(TextExporter.formatTime(context.date.timeIntervalSince(job.startedAt)))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(TranscriptionStage.allCases) { stage in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        stageIcon(stage)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stage.title)
                                .foregroundStyle(stage.rawValue > job.stage.rawValue ? .secondary : .primary)
                            if stage.isModelStage {
                                modelDetail(stage)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 380, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            if let error = job.errorMessage {
                VStack(spacing: 12) {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .frame(maxWidth: 520)
                    HStack {
                        Button("Back") { backToSetup() }
                        Button("Try Again") { job.start() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                Text("The first run downloads models from Hugging Face, which can take several minutes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Cancel") { backToSetup() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// "Downloading 42% · 3 of 7 files", "Already on this Mac", …
    @ViewBuilder
    private func modelDetail(_ stage: TranscriptionStage) -> some View {
        let status = job.modelStatus[stage]
        let isActive = stage == job.stage && job.errorMessage == nil
        if stage.rawValue < job.stage.rawValue {
            Text(status?.downloaded == true ? "Downloaded" : "Already on this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isActive {
            switch status?.progress?.phase {
            case .downloading(let completed, let total):
                let fraction = status?.progress?.fractionCompleted ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: min(max(fraction, 0), 1))
                        .frame(width: 280)
                    Text("Downloading \(Int((fraction * 100).rounded()))%" + (total > 0 ? " · \(min(completed + 1, total)) of \(total) files" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            case .listing:
                Text("Checking Hugging Face for models…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .compiling:
                Text(status?.downloaded == true ? "Preparing downloaded models for this Mac…" : "Loading models…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case nil:
                Text("Loading models…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stageIcon(_ stage: TranscriptionStage) -> some View {
        if stage.rawValue < job.stage.rawValue {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if stage == job.stage {
            if job.errorMessage != nil {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            } else {
                ProgressView().controlSize(.small)
            }
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    private func backToSetup() {
        let setup = TranscriptionSetup(audioURL: job.request.audioURL)
        if job.request.outputDirectory != job.request.audioURL.deletingLastPathComponent() {
            setup.outputDirectory = job.request.outputDirectory
        }
        setup.speakerNamesText = job.request.speakerNames
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.value)
            .joined(separator: ", ")
        workspace.cancelTranscription(returningTo: setup)
    }
}

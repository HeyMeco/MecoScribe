import SwiftUI

struct SpeakersPanel: View {
    let model: TranscriptEditorModel

    var body: some View {
        WrapLayout(spacing: 8, lineSpacing: 8) {
            ForEach(model.speakerIds, id: \.self) { id in
                SpeakerChip(model: model, speakerId: id)
            }
            Button {
                model.requestAddSpeaker()
            } label: {
                Label("Add Speaker", systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpeakerChip: View {
    let model: TranscriptEditorModel
    let speakerId: String

    var body: some View {
        let color = SpeakerPalette.color(model.speakerIndex(speakerId))
        let count = model.utteranceCount(for: speakerId)
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(model.speakerName(speakerId))
                .lineLimit(1)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(count == 1 ? "1 transcription" : "\(count) transcriptions")
            Button("Rename") { model.speakerSheet = .rename(speakerId) }
                .buttonStyle(.borderless)
                .font(.caption)
            if model.speakerIds.count > 1 {
                Button("Merge") { model.mergeSourceSpeaker = speakerId }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
        .contextMenu {
            Button("Rename…") { model.speakerSheet = .rename(speakerId) }
            if model.speakerIds.count > 1 {
                Button("Merge Speaker…") { model.mergeSourceSpeaker = speakerId }
            }
            Divider()
            Button("Delete Speaker…", role: .destructive) { model.deleteCandidateSpeaker = speakerId }
        }
    }
}

// MARK: - Sheets

struct SpeakerNameSheet: View {
    let model: TranscriptEditorModel
    let sheet: SpeakerSheet
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isAdding ? "Add Speaker" : "Rename Speaker")
                .font(.headline)
            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isAdding ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            switch sheet {
            case .rename(let id): name = model.speakerName(id)
            case .add: name = model.nextDefaultSpeakerName
            }
            focused = true
        }
    }

    private var isAdding: Bool {
        if case .add = sheet { return true }
        return false
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch sheet {
        case .rename(let id): model.renameSpeaker(id, to: name)
        case .add(let indices): model.addSpeaker(named: name, assigning: indices)
        }
        dismiss()
    }
}

struct MergeSpeakerSheet: View {
    let model: TranscriptEditorModel
    let sourceId: String
    @State private var targetId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let name = model.speakerName(sourceId)
        VStack(alignment: .leading, spacing: 14) {
            Text("Merge Speaker")
                .font(.headline)
            Text("Move \(name)’s transcriptions into another speaker. \(name) will be removed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(model.speakerIds.filter { $0 != sourceId }, id: \.self, selection: $targetId) { id in
                HStack(spacing: 8) {
                    Circle()
                        .fill(SpeakerPalette.color(model.speakerIndex(id)))
                        .frame(width: 10, height: 10)
                    Text(model.speakerName(id))
                }
                .tag(id)
            }
            .frame(height: 180)
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Merge") {
                    if let targetId { model.mergeSpeaker(sourceId, into: targetId) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(targetId == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

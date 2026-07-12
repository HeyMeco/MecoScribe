import MecoScribeCore
import SwiftUI

struct SpeakerAssignMenu: View {
    let speakerIds: [String]
    let speakerNames: [String: String]
    let onSelect: (String) -> Void
    let onAddSpeaker: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assign to speaker")
                .font(.headline)
            ForEach(speakerIds, id: \.self) { speakerId in
                Button {
                    onSelect(speakerId)
                    dismiss()
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: SpeakerPalette.color(for: speakerId, speakerIds: speakerIds)))
                            .frame(width: 10, height: 10)
                        Text(SpeakerPalette.displayName(for: speakerId, speakerNames: speakerNames))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            Divider()
            Button("Add speaker…", action: onAddSpeaker)
        }
        .padding()
        .frame(width: 260)
    }
}

struct SpeakerNameSheet: View {
    let title: String
    let initialName: String
    let onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(title: String, initialName: String, onCommit: @escaping (String) -> Void) {
        self.title = title
        self.initialName = initialName
        self.onCommit = onCommit
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("Speaker name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onCommit(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

struct DeleteSpeakerSheet: View {
    let speakerName: String
    let canDelete: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(speakerName)?")
                .font(.headline)
            if canDelete {
                Text("This speaker has no assigned words and can be removed.")
                    .foregroundStyle(.secondary)
            } else {
                Text("This speaker still has transcribed words and cannot be deleted.")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .disabled(!canDelete)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

struct UtteranceEditSheet: View {
    let text: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var editedText: String
    @Environment(\.dismiss) private var dismiss

    init(text: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.text = text
        self.onCommit = onCommit
        self.onCancel = onCancel
        _editedText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Utterance").font(.headline)
            TextEditor(text: $editedText)
                .font(.body)
                .frame(minHeight: 120)
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                Button("Save") {
                    onCommit(editedText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, height: 240)
    }
}

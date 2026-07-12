import MecoScribeCore
import SwiftUI

struct TranscriptionProgressView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 28) {
            header

            progressSection

            stepsList
                .frame(maxWidth: 420)

            footerNote

            actionButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .animation(.easeInOut(duration: 0.25), value: appModel.transcriptionPhase)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "waveform.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(isFailed ? .orange : .accentColor)
                .symbolEffect(.pulse, isActive: !isFailed)

            Text(isFailed ? "Transcription Failed" : "Transcribing Audio")
                .font(.title2.weight(.semibold))

            if let url = appModel.transcribingAudioURL {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)

            HStack {
                Text(currentStepTitle)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(progressFraction * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)

            if let detail = currentDetail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420, alignment: .leading)
            }
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(TranscriptionStep.allCases, id: \.self) { step in
                StepRow(step: step, status: status(for: step))
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var footerNote: some View {
        if isModelLoadingStep {
            Text("First run may take several minutes while models download from Hugging Face.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        } else if case .failed(_, let message) = appModel.transcriptionPhase {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private var actionButton: some View {
        Group {
            if isFailed {
                Button("Dismiss") {
                    appModel.transcriptionPhase = .idle
                    appModel.transcribingAudioURL = nil
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel", role: .cancel) {
                    appModel.cancelTranscription()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = appModel.transcriptionPhase { return true }
        return false
    }

    private var currentStep: TranscriptionStep? {
        switch appModel.transcriptionPhase {
        case .inProgress(let step, _):
            return step
        case .failed(let step, _):
            return step
        case .idle:
            return nil
        }
    }

    private var currentStepTitle: String {
        if case .failed = appModel.transcriptionPhase {
            return "Something went wrong"
        }
        return currentStep?.title ?? "Starting…"
    }

    private var currentDetail: String? {
        switch appModel.transcriptionPhase {
        case .inProgress(_, let detail):
            return detail ?? currentStep?.detail
        case .failed, .idle:
            return nil
        }
    }

    private var progressFraction: Double {
        switch appModel.transcriptionPhase {
        case .inProgress(let step, _):
            return TranscriptionStep.fractionCompleted(for: step)
        case .failed, .idle:
            return 0
        }
    }

    private var isModelLoadingStep: Bool {
        switch appModel.transcriptionPhase {
        case .inProgress(let step, _):
            return step == .loadingDiarizerModels || step == .loadingSpeechModels
        default:
            return false
        }
    }

    fileprivate enum StepStatus {
        case completed
        case current
        case pending
        case failed
    }

    private func status(for step: TranscriptionStep) -> StepStatus {
        switch appModel.transcriptionPhase {
        case .failed(let failedStep, _):
            if let failedStep, step == failedStep {
                return .failed
            }
            if let failedStep, step < failedStep {
                return .completed
            }
            return .pending
        case .inProgress(let current, _):
            if step < current { return .completed }
            if step == current { return .current }
            return .pending
        case .idle:
            return .pending
        }
    }
}

private struct StepRow: View {
    let step: TranscriptionStep
    let status: TranscriptionProgressView.StepStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .symbolEffect(.pulse, isActive: status == .current)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(status == .current ? .semibold : .regular))
                    .foregroundStyle(titleColor)

                if status == .current {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .opacity(status == .pending ? 0.45 : 1)
    }

    private var iconName: String {
        switch status {
        case .completed:
            return "checkmark.circle.fill"
        case .current:
            return "arrow.right.circle.fill"
        case .pending:
            return "circle"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .completed:
            return .green
        case .current:
            return .accentColor
        case .pending:
            return .secondary
        case .failed:
            return .red
        }
    }

    private var titleColor: Color {
        switch status {
        case .pending:
            return .secondary
        default:
            return .primary
        }
    }
}

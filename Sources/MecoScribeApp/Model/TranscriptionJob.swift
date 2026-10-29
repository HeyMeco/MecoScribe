import Foundation
import MecoScribeCore
import Observation

struct TranscriptionRequest: Sendable {
    var audioURL: URL
    var outputDirectory: URL
    var options: ScribeProcessor.Options
    var speakerNames: [String: String]

    var project: ProjectFile {
        ProjectFile(
            directory: outputDirectory,
            baseName: audioURL.deletingPathExtension().lastPathComponent
        )
    }
}

enum TranscriptionStage: Int, CaseIterable, Identifiable, Sendable {
    case diarizationModels
    case diarizing
    case transcriptionModels
    case transcribing
    case aligning
    case saving

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .diarizationModels: return "Speaker detection models"
        case .diarizing: return "Identifying speakers"
        case .transcriptionModels: return "Speech recognition models"
        case .transcribing: return "Transcribing speech"
        case .aligning: return "Aligning words to speakers"
        case .saving: return "Saving project"
        }
    }

    var isModelStage: Bool { self == .diarizationModels || self == .transcriptionModels }

    init(_ stage: ScribeProcessor.Stage) {
        switch stage {
        case .preparingDiarizationModels: self = .diarizationModels
        case .diarizing: self = .diarizing
        case .preparingTranscriptionModels: self = .transcriptionModels
        case .transcribing: self = .transcribing
        case .aligning: self = .aligning
        }
    }
}

/// What happened while a model stage ran.
struct ModelStageStatus: Equatable {
    var progress: ScribeProcessor.ModelProgress?
    var downloaded = false
}

/// Runs the same pipeline as the CLI, off the main actor, and saves a `.mscribe`.
@MainActor
@Observable
final class TranscriptionJob {
    let request: TranscriptionRequest
    private(set) var startedAt = Date()
    private(set) var stage: TranscriptionStage = .diarizationModels
    private(set) var modelStatus: [TranscriptionStage: ModelStageStatus] = [:]
    private(set) var errorMessage: String?

    @ObservationIgnored var onSuccess: ((ProjectFile) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    init(request: TranscriptionRequest) {
        self.request = request
    }

    func start() {
        errorMessage = nil
        stage = .diarizationModels
        modelStatus = [:]
        startedAt = Date()
        let request = request
        // A stream keeps events in order; separate main-actor tasks per event would not.
        let (events, continuation) = AsyncStream.makeStream(of: JobEvent.self)
        let worker = Task.detached(priority: .userInitiated) { () throws -> ProjectFile in
            defer { continuation.finish() }
            return try await Self.run(request) { continuation.yield($0) }
        }
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
        task = Task { [weak self] in
            do {
                let project = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                await self?.eventsTask?.value
                guard let self, !Task.isCancelled else { return }
                self.onSuccess?(project)
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        eventsTask?.cancel()
        eventsTask = nil
    }

    private func handle(_ event: JobEvent) {
        guard task != nil else { return }
        switch event {
        case .stage(let next):
            if next.rawValue > stage.rawValue { stage = next }
        case .models(let progress):
            guard stage.isModelStage else { return }
            var status = modelStatus[stage] ?? ModelStageStatus()
            status.progress = progress
            if case .downloading = progress.phase { status.downloaded = true }
            modelStatus[stage] = status
        }
    }

    enum JobEvent: Sendable {
        case stage(TranscriptionStage)
        case models(ScribeProcessor.ModelProgress)
    }

    private nonisolated static func run(
        _ request: TranscriptionRequest,
        report: @escaping @Sendable (JobEvent) -> Void
    ) async throws -> ProjectFile {
        try FileManager.default.createDirectory(
            at: request.options.modelsDirectory,
            withIntermediateDirectories: true
        )
        let result = try await ScribeProcessor.process(
            audioPath: request.audioURL.path,
            options: request.options
        ) { event in
            switch event {
            case .stage(let stage): report(.stage(TranscriptionStage(stage)))
            case .models(let progress): report(.models(progress))
            }
        }
        try Task.checkCancellation()

        report(.stage(.saving))
        let project = request.project
        try FileManager.default.createDirectory(at: project.directory, withIntermediateDirectories: true)
        try MScribeFile.write(
            result,
            speakerNames: request.speakerNames,
            audioPath: request.audioURL.path,
            to: project.url,
            generator: AppInfo.generator
        )
        return project
    }
}

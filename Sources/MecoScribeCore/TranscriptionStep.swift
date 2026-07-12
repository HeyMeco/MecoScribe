import Foundation

public enum TranscriptionStep: Int, CaseIterable, Sendable, Comparable {
    case preparing = 0
    case loadingDiarizerModels
    case diarizing
    case loadingSpeechModels
    case transcribing
    case aligning
    case saving

    public static func < (lhs: TranscriptionStep, rhs: TranscriptionStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .preparing:
            return "Preparing"
        case .loadingDiarizerModels:
            return "Loading speaker models"
        case .diarizing:
            return "Identifying speakers"
        case .loadingSpeechModels:
            return "Loading speech models"
        case .transcribing:
            return "Transcribing audio"
        case .aligning:
            return "Aligning speakers"
        case .saving:
            return "Saving transcript"
        }
    }

    public var detail: String {
        switch self {
        case .preparing:
            return "Checking audio file and model cache"
        case .loadingDiarizerModels:
            return "Downloading or loading diarization models"
        case .diarizing:
            return "Detecting who spoke when"
        case .loadingSpeechModels:
            return "Downloading or loading speech recognition models"
        case .transcribing:
            return "Converting speech to text with word timings"
        case .aligning:
            return "Matching words to speakers"
        case .saving:
            return "Writing transcript files"
        }
    }

    /// Relative weight for overall progress (sums to 1.0).
    public var progressWeight: Double {
        switch self {
        case .preparing: return 0.02
        case .loadingDiarizerModels: return 0.08
        case .diarizing: return 0.30
        case .loadingSpeechModels: return 0.08
        case .transcribing: return 0.42
        case .aligning: return 0.05
        case .saving: return 0.05
        }
    }

    public static func fractionCompleted(for step: TranscriptionStep) -> Double {
        var total = 0.0
        for candidate in allCases where candidate < step {
            total += candidate.progressWeight
        }
        total += step.progressWeight * 0.5
        return min(total, 1.0)
    }
}

public struct TranscriptionProgressUpdate: Sendable {
    public let step: TranscriptionStep
    public let detail: String?

    public init(step: TranscriptionStep, detail: String? = nil) {
        self.step = step
        self.detail = detail
    }
}

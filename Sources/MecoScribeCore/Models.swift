import Foundation

public struct WordTiming: Codable, Sendable, Hashable {
    public let word: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float

    public init(word: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

public struct DiarizedWord: Codable, Sendable, Hashable {
    public var word: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var confidence: Float
    public var speakerId: String

    public init(
        word: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float,
        speakerId: String
    ) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speakerId = speakerId
    }
}

public struct DiarizedUtterance: Codable, Sendable, Hashable {
    public var speakerId: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var words: [DiarizedWord]

    public init(
        speakerId: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        words: [DiarizedWord]
    ) {
        self.speakerId = speakerId
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.words = words
    }
}

public struct ScribeResult: Codable, Sendable {
    public let audioFile: String
    public let durationSeconds: TimeInterval
    public let speakerCount: Int
    public let utterances: [DiarizedUtterance]
    public let speakerIds: [String]

    public init(
        audioFile: String,
        durationSeconds: TimeInterval,
        speakerCount: Int,
        utterances: [DiarizedUtterance],
        speakerIds: [String]
    ) {
        self.audioFile = audioFile
        self.durationSeconds = durationSeconds
        self.speakerCount = speakerCount
        self.utterances = utterances
        self.speakerIds = speakerIds
    }
}

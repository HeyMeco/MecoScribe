import Foundation

struct WordTiming: Codable, Sendable {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
}

struct DiarizedWord: Codable, Sendable {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    let speakerId: String
}

struct DiarizedUtterance: Codable, Sendable {
    let speakerId: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let words: [DiarizedWord]
}

struct ScribeResult: Codable, Sendable {
    let audioFile: String
    let durationSeconds: TimeInterval
    let speakerCount: Int
    let utterances: [DiarizedUtterance]
    let speakerIds: [String]
}

import Foundation
import MecoScribeCore
import Testing

@testable import MecoScribeApp

/// Runs the full pipeline. Opt-in: set MECOSCRIBE_TEST_AUDIO (and MECOSCRIBE_MODELS_DIR
/// to reuse downloaded models).
@MainActor
struct TranscriptionJobTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MECOSCRIBE_TEST_AUDIO"] != nil))
    func transcribesAndOpens() async throws {
        Preferences.registerDefaults()
        let audio = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MECOSCRIBE_TEST_AUDIO"]!)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("mecoscribe-job-\(UUID().uuidString)", isDirectory: true)
        let setup = TranscriptionSetup(audioURL: audio)
        setup.outputDirectory = output
        setup.speakerNamesText = "Alice, Bob"
        let request = try #require(setup.makeRequest())

        let job = TranscriptionJob(request: request)
        var finished = false
        let project: ProjectFile = try await withCheckedThrowingContinuation { continuation in
            job.onSuccess = {
                finished = true
                continuation.resume(returning: $0)
            }
            job.start()
            Task {
                while job.errorMessage == nil, !finished { try? await Task.sleep(for: .milliseconds(200)) }
                if !finished { continuation.resume(throwing: CancellationError()) }
            }
        }
        #expect(job.stage == .saving)
        #expect(project.url.pathExtension == "mscribe")
        let entries = try ZipArchive.read(contentsOf: project.url)
        #expect(Set(entries.keys) == ["manifest.json", "transcript.txt", "transcript.mecoscribe.json", "transcript.html"])
        let editor = try TranscriptEditorModel(project: project)
        #expect(editor.totalWords > 10)
        #expect(editor.speakerName("speaker_0") == "Alice")
        #expect(editor.audioURL == audio.standardizedFileURL)
        editor.close()
    }
}

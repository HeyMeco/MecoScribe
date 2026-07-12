import Foundation

public enum FileConflictAction: Sendable {
    case reload
    case keepLocal
}

@Observable
public final class TranscriptFileWatcher: @unchecked Sendable {
    public private(set) var hasExternalChange = false

    private let txtURL: URL
    private let sidecarURL: URL
    private var txtModDate: Date?
    private var sidecarModDate: Date?
    private var pollTask: Task<Void, Never>?

    public init(txtURL: URL) {
        self.txtURL = txtURL
        sidecarURL = URL(fileURLWithPath: TimingsSidecar.path(forTxtPath: txtURL.path))
        refreshModDates()
    }

    public func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.checkForChanges()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func acknowledgeLocalSave() {
        refreshModDates()
        hasExternalChange = false
    }

    public func dismissConflict() {
        hasExternalChange = false
        refreshModDates()
    }

    private func checkForChanges() {
        let currentTxt = modificationDate(for: txtURL)
        let currentSidecar = modificationDate(for: sidecarURL)

        if let txtModDate, let currentTxt, currentTxt > txtModDate {
            hasExternalChange = true
        } else if let sidecarModDate, let currentSidecar, currentSidecar > sidecarModDate {
            hasExternalChange = true
        }

        txtModDate = currentTxt ?? txtModDate
        sidecarModDate = currentSidecar ?? sidecarModDate
    }

    private func refreshModDates() {
        txtModDate = modificationDate(for: txtURL)
        sidecarModDate = modificationDate(for: sidecarURL)
        hasExternalChange = false
    }

    private func modificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}

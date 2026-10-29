import CoreGraphics

/// Word positions inside the transcript scroll content, used to hit-test mouse drags
/// (range selection and moving words). Deliberately not observable: it is written
/// during layout and read during gestures, and must never trigger a re-render.
@MainActor
final class TranscriptFrames {
    struct Hit {
        let row: Int
        let word: Int
        let rect: CGRect
    }

    /// Rows currently materialized by the lazy stack.
    var visibleRows: Set<Int> = []
    /// Frame of each row's word-flow container, in transcript content coordinates.
    var containerFrames: [Int: CGRect] = [:]
    /// Word rects relative to their row's word-flow container.
    var wordRects: [Int: [CGRect]] = [:]

    /// Forgets rows at or past `count`, after the transcript lost lines.
    func discardRows(from count: Int) {
        containerFrames = containerFrames.filter { $0.key < count }
        wordRects = wordRects.filter { $0.key < count }
        visibleRows = visibleRows.filter { $0 < count }
    }

    private func visibleHits() -> [Hit] {
        var hits: [Hit] = []
        for row in visibleRows {
            guard let container = containerFrames[row], let rects = wordRects[row] else { continue }
            for (word, rect) in rects.enumerated() where !rect.isNull {
                hits.append(Hit(row: row, word: word, rect: rect.offsetBy(dx: container.minX, dy: container.minY)))
            }
        }
        return hits
    }

    func rect(row: Int, word: Int) -> CGRect? {
        guard let container = containerFrames[row], let rects = wordRects[row], rects.indices.contains(word) else {
            return nil
        }
        let rect = rects[word]
        return rect.isNull ? nil : rect.offsetBy(dx: container.minX, dy: container.minY)
    }

    /// The word directly under `point`, if any.
    func exactHit(at point: CGPoint) -> Hit? {
        visibleHits().first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }
    }

    /// The word closest to `point`, preferring words on the same text line.
    func nearestHit(to point: CGPoint) -> Hit? {
        let hits = visibleHits()
        guard !hits.isEmpty else { return nil }

        let sameLine = hits.filter { point.y >= $0.rect.minY - 2 && point.y <= $0.rect.maxY + 2 }
        if !sameLine.isEmpty {
            return sameLine.min { horizontalDistance(point, $0.rect) < horizontalDistance(point, $1.rect) }
        }
        return hits.min { distance(point, $0.rect) < distance(point, $1.rect) }
    }

    private func horizontalDistance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        if point.x < rect.minX { return rect.minX - point.x }
        if point.x > rect.maxX { return point.x - rect.maxX }
        return 0
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

import SmaltiCore
import Testing

/// Tolerance, in points, when comparing computed frames with board values.
let frameTolerance = 0.01

func expectFrame(
    _ frame: Rect?, x: Double, y: Double, width: Double, height: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let frame else {
        Issue.record("missing frame", sourceLocation: sourceLocation)
        return
    }
    #expect(abs(frame.minX - x) < frameTolerance, sourceLocation: sourceLocation)
    #expect(abs(frame.minY - y) < frameTolerance, sourceLocation: sourceLocation)
    #expect(abs(frame.size.width - width) < frameTolerance, sourceLocation: sourceLocation)
    #expect(abs(frame.size.height - height) < frameTolerance, sourceLocation: sourceLocation)
}

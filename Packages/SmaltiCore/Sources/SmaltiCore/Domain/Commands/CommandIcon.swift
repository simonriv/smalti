/// A palette icon as geometry, in the boards' 16×16 viewBox units with y growing down: an optional rounded frame
/// and stroked polylines. Views only translate it; each layout declares its own, so a new layout needs no view change.
public struct CommandIcon: Hashable, Sendable {
    public static let viewBoxSize = 16.0

    public let frame: Rect?
    public let frameRadius: Double
    public let strokes: [[Point]]

    public init(frame: Rect?, frameRadius: Double, strokes: [[Point]]) {
        self.frame = frame
        self.frameRadius = frameRadius
        self.strokes = strokes
    }

    /// The layout icons' window: `rect x=1.5 y=2 width=13 height=12 rx=2` (Paleta.dc.html).
    static func layoutFrame(strokes: [[Point]]) -> CommandIcon {
        CommandIcon(frame: Rect(x: 1.5, y: 2, width: 13, height: 12), frameRadius: 2, strokes: strokes)
    }

    /// "Igualar tamaños de paneles": two bars with arrows pointing at each other.
    static let equalize = CommandIcon(
        frame: nil, frameRadius: 0,
        strokes: [
            [Point(x: 2, y: 5), Point(x: 14, y: 5)], [Point(x: 2, y: 11), Point(x: 14, y: 11)],
            [Point(x: 5, y: 2.5), Point(x: 2, y: 5), Point(x: 5, y: 7.5)],
            [Point(x: 11, y: 8.5), Point(x: 14, y: 11), Point(x: 11, y: 13.5)],
        ])

    /// F8.5: a folder with a dot (the mockup's project icon), as polylines.
    public static let projectFolder = CommandIcon(
        frame: nil, frameRadius: 0,
        strokes: [
            [
                Point(x: 1.8, y: 4.2), Point(x: 3, y: 3), Point(x: 6, y: 3), Point(x: 7.5, y: 4.6),
                Point(x: 13, y: 4.6), Point(x: 14.2, y: 5.8), Point(x: 14.2, y: 12), Point(x: 13, y: 13.2),
                Point(x: 3, y: 13.2), Point(x: 1.8, y: 12), Point(x: 1.8, y: 4.2),
            ],
            [
                Point(x: 7.2, y: 8.2), Point(x: 8.8, y: 8.2), Point(x: 8.8, y: 9.8), Point(x: 7.2, y: 9.8),
                Point(x: 7.2, y: 8.2),
            ],
        ])

    /// F8.5: a clock, for "Proyectos recientes…": a round frame and its hands.
    public static let recentProjects = CommandIcon(
        frame: Rect(x: 2.4, y: 2.4, width: 11.2, height: 11.2), frameRadius: 5.6,
        strokes: [[Point(x: 8, y: 5), Point(x: 8, y: 8.2), Point(x: 10.2, y: 9.6)]])

    /// F8.5: a floppy disk, for "Guardar layout del proyecto" (the mockup's save icon).
    public static let saveProject = CommandIcon(
        frame: nil, frameRadius: 0,
        strokes: [
            [
                Point(x: 3, y: 2.5), Point(x: 11, y: 2.5), Point(x: 13.5, y: 5), Point(x: 13.5, y: 13.5),
                Point(x: 3, y: 13.5), Point(x: 3, y: 2.5),
            ],
            [Point(x: 5.5, y: 2.5), Point(x: 5.5, y: 6), Point(x: 10.5, y: 6), Point(x: 10.5, y: 2.5)],
            [Point(x: 5.5, y: 13.5), Point(x: 5.5, y: 9.5), Point(x: 10.5, y: 9.5), Point(x: 10.5, y: 13.5)],
        ])
}

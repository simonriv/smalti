/// Converts a view's size in points to the pixel size libghostty expects. Never returns 0:
/// a zero-sized surface is invalid for the renderer.
public enum SurfaceSizing {
    public static func pixelSize(points: (width: Double, height: Double), scale: Double) -> (
        width: UInt32, height: UInt32
    ) {
        (pixels(points.width, scale), pixels(points.height, scale))
    }

    private static func pixels(_ points: Double, _ scale: Double) -> UInt32 {
        let value = (points * scale).rounded(.down)
        return value < 1 ? 1 : UInt32(clamping: Int(value))
    }
}

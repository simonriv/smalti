// Turns the thin-stroke SVG icons (16-unit grid, stroke 1.4, round caps and joins) into filled outlines with
// CoreGraphics, and prints them as JSON for build-symbols-font.py. Only what the icons use is read: `<path d>` with
// M L H V C Z (absolute or relative) and `<circle>`.
// Usage: swift outline-icons.swift <icons-dir> <icons.txt> > icons.json
import CoreGraphics
import Foundation

let strokeWidth: CGFloat = 1.4

func numbers(_ text: Substring) -> [CGFloat] {
    text.matches(of: #/-?(?:\d+\.?\d*|\.\d+)/#).compactMap { Double($0.output).map { CGFloat($0) } }
}

func addPath(_ data: String, to path: CGMutablePath) {
    var current = CGPoint.zero
    var start = CGPoint.zero
    for command in data.matches(of: #/([MmLlHhVvCcZz])([^MmLlHhVvCcZz]*)/#) {
        let letter = Character(String(command.output.1))
        let values = numbers(command.output.2)
        let relative = letter.isLowercase
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        switch letter.uppercased() {
        case "M":
            for index in stride(from: 0, to: values.count - 1, by: 2) {
                let next = point(values[index], values[index + 1])
                if index == 0 {
                    path.move(to: next)
                    start = next
                } else {
                    path.addLine(to: next)
                }
                current = next
            }
        case "L":
            for index in stride(from: 0, to: values.count - 1, by: 2) {
                current = point(values[index], values[index + 1])
                path.addLine(to: current)
            }
        case "H":
            for value in values {
                current = CGPoint(x: relative ? current.x + value : value, y: current.y)
                path.addLine(to: current)
            }
        case "V":
            for value in values {
                current = CGPoint(x: current.x, y: relative ? current.y + value : value)
                path.addLine(to: current)
            }
        case "C":
            for index in stride(from: 0, to: values.count - 5, by: 6) {
                let control1 = point(values[index], values[index + 1])
                let control2 = point(values[index + 2], values[index + 3])
                let end = point(values[index + 4], values[index + 5])
                path.addCurve(to: end, control1: control1, control2: control2)
                current = end
            }
        default:
            path.closeSubpath()
            current = start
        }
    }
}

func attribute(_ name: String, in element: Substring) -> String? {
    for match in element.matches(of: #/([a-z]+)="([^"]*)"/#) where match.output.1 == name {
        return String(match.output.2)
    }
    return nil
}

func outline(of svg: String) -> [[[String: Any]]] {
    let path = CGMutablePath()
    for element in svg.matches(of: #/<(path|circle)\b[^>]*>/#) {
        let tag = element.output.0
        if element.output.1 == "path", let data = attribute("d", in: tag) {
            addPath(data, to: path)
        } else if let x = attribute("cx", in: tag).flatMap(Double.init),
            let y = attribute("cy", in: tag).flatMap(Double.init), let r = attribute("r", in: tag).flatMap(Double.init)
        {
            path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }
    let stroked = path.copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    var contours: [[[String: Any]]] = []
    stroked.applyWithBlock { element in
        let points = element.pointee.points
        func xy(_ index: Int) -> [Double] { [Double(points[index].x), Double(points[index].y)] }
        switch element.pointee.type {
        case .moveToPoint: contours.append([["op": "move", "p": [xy(0)]]])
        case .addLineToPoint: contours[contours.count - 1].append(["op": "line", "p": [xy(0)]])
        case .addQuadCurveToPoint: contours[contours.count - 1].append(["op": "quad", "p": [xy(0), xy(1)]])
        case .addCurveToPoint: contours[contours.count - 1].append(["op": "cubic", "p": [xy(0), xy(1), xy(2)]])
        case .closeSubpath: contours[contours.count - 1].append(["op": "close", "p": [] as [[Double]]])
        @unknown default: break
        }
    }
    return contours
}

let arguments = CommandLine.arguments
let directory = URL(filePath: arguments[1])
let names = try String(contentsOf: URL(filePath: arguments[2]), encoding: .utf8).split(whereSeparator: \.isWhitespace)
var icons: [[String: Any]] = []
for name in names {
    let svg = try String(contentsOf: directory.appending(path: "\(name).svg"), encoding: .utf8)
    icons.append(["name": String(name), "contours": outline(of: svg)])
}
let json = try JSONSerialization.data(withJSONObject: icons, options: [.sortedKeys])
print(String(decoding: json, as: UTF8.self))

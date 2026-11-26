import Foundation
import SmaltiCore

/// What the timeline paints, already worded (`TimelinePresenter`); the view only lays it out.
struct TimelineScreen: Equatable {
    enum Mode: Equatable {
        case session, search
    }

    struct SessionInfo: Equatable {
        let dot: StatusDotStyle
        let line: String
        let title: String
        let figures: String
    }

    struct Recent: Equatable {
        let title: String
        let meta: String
        let isLive: Bool
    }

    enum SearchItem: Equatable {
        case group(title: String, meta: String, count: Int)
        case hit(who: String, time: String, snippet: String, match: NSRange)
    }

    enum Body: Equatable {
        case loading(String)
        case session(info: SessionInfo, banner: String?, rows: [TimelineRow])
        case empty(title: String, body: String, recentTitle: String, recent: [Recent])
        case failed(String)
        case search(query: String, scope: String, root: String, summary: String, items: [SearchItem])
    }

    let mode: Mode
    let body: Body
    /// The row, hit or recent session chosen: its index in what the body lists.
    let selected: Int?
    let keys: [(key: String, label: String)]

    static func == (lhs: TimelineScreen, rhs: TimelineScreen) -> Bool {
        lhs.mode == rhs.mode && lhs.body == rhs.body && lhs.selected == rhs.selected
            && lhs.keys.map(\.key) == rhs.keys.map(\.key) && lhs.keys.map(\.label) == rhs.keys.map(\.label)
    }
}

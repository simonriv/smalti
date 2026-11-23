public enum WindowSetError: Error, Equatable, Sendable {
    /// The last window closes the app instead (⌘Q), so the set never becomes empty.
    case lastWindow
}

/// The app's windows, in opening order, and which one is in front.
///
/// Invariant: there is at least one window and `frontID` is one of them.
public struct WindowSet: Equatable, Sendable {
    public private(set) var windows: [WindowState]
    public private(set) var frontID: WindowID

    public init(first: WindowState) {
        windows = [first]
        frontID = first.id
    }

    public var front: WindowState {
        // Every mutation keeps `frontID` pointing at an existing window, so a miss is a bug here.
        guard let found = windows.first(where: { $0.id == frontID }) else {
            preconditionFailure("WindowSet invariant broken: front window \(frontID) is missing")
        }
        return found
    }

    public var allPanes: [Pane] { windows.flatMap(\.allPanes) }

    /// What a user changes on purpose, window by window (`WorkspaceSet.structure`); frames are left out.
    public var structure: [[String]] { windows.flatMap { [[$0.id.description]] + $0.workspaces.structure } }

    /// Adds `window` and puts it in front; a window already in the set changes nothing.
    public func opening(_ window: WindowState) -> WindowSet {
        guard !windows.contains(where: { $0.id == window.id }) else { return self }
        var updated = self
        updated.windows.append(window)
        updated.frontID = window.id
        return updated
    }

    /// Removes `id`; if it was in front, the window opened before it (or the first) comes to the front.
    public func closing(_ id: WindowID) throws(WindowSetError) -> WindowSet {
        guard let position = windows.firstIndex(where: { $0.id == id }) else { return self }
        guard windows.count > 1 else { throw .lastWindow }
        var updated = self
        updated.windows.remove(at: position)
        if frontID == id {
            updated.frontID = updated.windows[max(position - 1, 0)].id
        }
        return updated
    }

    public func bringingToFront(_ id: WindowID) -> WindowSet {
        guard windows.contains(where: { $0.id == id }) else { return self }
        var updated = self
        updated.frontID = id
        return updated
    }

    public func window(containing pane: PaneID) -> WindowState? {
        windows.first { $0.workspaces.workspace(containing: pane) != nil }
    }

    public func updating(_ id: WindowID, _ transform: (WindowState) -> WindowState) -> WindowSet {
        guard let position = windows.firstIndex(where: { $0.id == id }) else { return self }
        let transformed = transform(windows[position])
        // A transform that changes identity would break unique ids and `frontID`.
        guard transformed.id == id else { return self }
        var updated = self
        updated.windows[position] = transformed
        return updated
    }
}

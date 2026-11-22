import AppKit
import GhosttyKit
import SmaltiCore

/// AppKit view that hosts one libghostty surface (Metal rendering, PTY, shell) and feeds it keyboard,
/// IME and mouse input. A trimmed subset of ghostty v1.4.0
/// macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift (MIT, see ThirdParty/LICENSE-ghostty.txt):
/// no inspector, search, drag and drop, progress bar or Quick Look.
@MainActor
final class GhosttySurfaceView: NSView {
    private(set) var surface: ghostty_surface_t?
    let events: AsyncStream<TerminalEvent>
    private let continuation: AsyncStream<TerminalEvent>.Continuation
    var onCloseRequested: (() -> Void)?

    private var markedText = NSMutableAttributedString()
    /// Non-nil only while `keyDown` runs `interpretKeyEvents`; collects text committed by the input system.
    private var keyTextAccumulator: [String]?
    /// Timestamp of a ⌘/⌃ key equivalent AppKit should bounce back to `keyDown` (see `performKeyEquivalent`).
    private var lastPerformKeyEvent: TimeInterval?
    private var trackingArea: NSTrackingArea?

    init(app: ghostty_app_t, spec: TerminalSessionSpec) throws(TerminalEngineError) {
        (events, continuation) = AsyncStream.makeStream()
        // Non-zero initial frame so the renderer's layer is never zero-sized.
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityIdentifier("smalti.terminal")
        surface = Self.makeSurface(app: app, view: self, spec: spec)
        guard surface != nil else {
            throw .surfaceCreationFailed(
                workingDirectory: spec.workingDirectory.path, reason: "ghostty_surface_new returned null")
        }
        GhosttyRuntime.register(self)
        updateTrackingAreas()
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// Frees the surface (and with it the PTY and child process) and ends the event stream.
    func shutDown() {
        GhosttyRuntime.unregister(self)
        if let surface { ghostty_surface_free(surface) }
        surface = nil
        continuation.finish()
    }

    func deliver(_ event: TerminalEvent) {
        continuation.yield(event)
    }

    func requestClose() {
        onCloseRequested?()
    }

    // MARK: - Surface creation

    private static func makeSurface(app: ghostty_app_t, view: GhosttySurfaceView, spec: TerminalSessionSpec)
        -> ghostty_surface_t?
    {
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(view).toOpaque()))
        config.userdata = Unmanaged.passUnretained(view).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func cString(_ value: String) -> UnsafeMutablePointer<CChar>? {
            let pointer = strdup(value)
            if let pointer { owned.append(pointer) }
            return pointer
        }
        config.working_directory = UnsafePointer(cString(spec.workingDirectory.path))
        if case .custom(let command) = spec.command { config.command = UnsafePointer(cString(command)) }
        var environment = spec.environment.sorted { $0.key < $1.key }.map { key, value in
            ghostty_env_var_s(key: cString(key), value: cString(value))
        }
        return environment.withUnsafeMutableBufferPointer { buffer in
            config.env_vars = buffer.baseAddress
            config.env_var_count = buffer.count
            return ghostty_surface_new(app, &config)
        }
    }

    // MARK: - Size, scale and focus

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface { ghostty_surface_set_focus(surface, true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface { ghostty_surface_set_focus(surface, false) }
        return result
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sendSize(newSize)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let window, let surface else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // No scale animation of the layer contents.
        layer?.contentsScale = window.backingScaleFactor
        CATransaction.commit()
        let backing = convertToBacking(frame)
        if frame.width > 0, frame.height > 0 {
            ghostty_surface_set_content_scale(surface, backing.width / frame.width, backing.height / frame.height)
        }
        sendSize(frame.size)
    }

    private func sendSize(_ size: NSSize) {
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = SurfaceSizing.pixelSize(points: (Double(size.width), Double(size.height)), scale: Double(scale))
        ghostty_surface_set_size(surface, pixels.width, pixels.height)
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, event)
    }
    override func mouseUp(with event: NSEvent) { mouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, event) }
    override func rightMouseDown(with event: NSEvent) { mouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event) }
    override func rightMouseUp(with event: NSEvent) { mouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, event) }
    override func otherMouseDown(with event: NSEvent) { mouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE, event) }
    override func otherMouseUp(with event: NSEvent) { mouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, event) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        // libghostty uses a top-left origin.
        ghostty_surface_mouse_pos(surface, point.x, frame.height - point.y, GhosttyInput.mods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        let precise = event.hasPreciseScrollingDeltas
        let factor: CGFloat = precise ? 2 : 1  // Ghostty's trackpad speed-up.
        ghostty_surface_mouse_scroll(
            surface, event.scrollingDeltaX * factor, event.scrollingDeltaY * factor,
            GhosttyInput.scrollMods(precise: precise, momentum: event.momentumPhase))
    }

    private func mouseButton(
        _ state: ghostty_input_mouse_state_e, _ button: ghostty_input_mouse_button_e, _ event: NSEvent
    ) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, state, button, GhosttyInput.mods(event.modifierFlags))
    }
}

// MARK: - Keyboard

extension GhosttySurfaceView {
    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }
        let translationEvent = GhosttyInput.translationEvent(for: event, surface: surface)
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let hadMarkedText = markedText.length > 0

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        lastPerformKeyEvent = nil
        interpretKeyEvents([translationEvent])
        syncPreedit(clearIfNeeded: hadMarkedText)

        let composing = markedText.length > 0 || hadMarkedText
        let committed = keyTextAccumulator ?? []
        if hadMarkedText, !committed.isEmpty {
            // The input method committed its preedit (e.g. a dead key + vowel): send the text alone.
            committed.filter { !GhosttyInput.isControlInput($0, composing: composing) }
                .forEach { sendCommittedText($0, action: action) }
            return
        }
        if !committed.isEmpty {
            committed.filter { !GhosttyInput.isControlInput($0, composing: composing) }
                .forEach { sendKey(action, event: event, translationEvent: translationEvent, text: $0) }
            return
        }
        guard !GhosttyInput.isControlInput(event.characters, composing: composing) else { return }
        sendKey(
            action, event: event, translationEvent: translationEvent,
            text: GhosttyInput.characters(of: translationEvent), composing: composing)
    }

    override func keyUp(with event: NSEvent) {
        sendKey(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let modifier = GhosttyInput.modifier(forKeyCode: event.keyCode), !hasMarkedText() else { return }
        let pressed = GhosttyInput.mods(event.modifierFlags).rawValue & modifier != 0
        sendKey(pressed ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE, event: event)
    }

    /// ⌘/⌃ chords reach here before `keyDown`. Menu shortcuts (⌘Q, ⌘H) win; libghostty bindings (⌘C, ⌘V…)
    /// go to `keyDown`; everything else is bounced through AppKit once and then encoded for the terminal.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self, let surface else { return false }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
        if GhosttyInput.isBinding(event, surface: surface) {
            keyDown(with: event)
            return true
        }
        guard event.timestamp != 0, !event.modifierFlags.isDisjoint(with: [.command, .control]) else {
            lastPerformKeyEvent = nil
            return false
        }
        if lastPerformKeyEvent == event.timestamp {
            lastPerformKeyEvent = nil
            keyDown(with: event)
            return true
        }
        lastPerformKeyEvent = event.timestamp
        return false
    }

    override func doCommand(by selector: Selector) {
        // Silences NSBeep and re-dispatches ⌘/⌃ chords recorded by performKeyEquivalent.
        if let lastPerformKeyEvent, let current = NSApp.currentEvent, lastPerformKeyEvent == current.timestamp {
            NSApp.sendEvent(current)
        }
    }

    private func sendKey(
        _ action: ghostty_input_action_e, event: NSEvent, translationEvent: NSEvent? = nil, text: String? = nil,
        composing: Bool = false
    ) {
        guard let surface else { return }
        var key = GhosttyInput.keyEvent(action, event: event, translationMods: translationEvent?.modifierFlags)
        key.composing = composing
        guard let text = GhosttyInput.keyEventText(text) else {
            _ = ghostty_surface_key(surface, key)
            return
        }
        text.withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
    }

    private func sendCommittedText(_ text: String, action: ghostty_input_action_e) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = action
        key.mods = GHOSTTY_MODS_NONE
        key.consumed_mods = GHOSTTY_MODS_NONE
        text.withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let text = markedText.string
            text.withCString { ghostty_surface_preedit(surface, $0, UInt(text.utf8.count)) }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}

// MARK: - NSTextInputClient (IME and dead keys)

extension GhosttySurfaceView: @preconcurrency NSTextInputClient {
    func hasMarkedText() -> Bool { markedText.length > 0 }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange()
    }

    func selectedRange() -> NSRange { NSRange() }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString: markedText = NSMutableAttributedString(attributedString: attributed)
        case let plain as String: markedText = NSMutableAttributedString(string: plain)
        default: return
        }
        // Outside keyDown (e.g. layout switch mid-composition) the preedit must update right away.
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x = 0.0, y = 0.0, width = 0.0, height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        let viewRect = NSRect(x: x, y: frame.height - y, width: 0, height: height)
        return window.convertToScreen(convert(viewRect, to: nil))
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        let text: String
        switch string {
        case let attributed as NSAttributedString: text = attributed.string
        case let plain as String: text = plain
        default: return
        }
        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else if !text.isEmpty {
            sendCommittedText(text, action: GHOSTTY_ACTION_PRESS)
        }
    }
}

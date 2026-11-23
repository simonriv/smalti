import AppKit
import GhosttyKit
import SmaltiCore

/// Owns the libghostty app and answers its runtime callbacks (wakeup, actions, clipboard, close).
/// Adapted from ghostty v1.4.0 macos/Sources/Ghostty/Ghostty.App.swift (MIT, see ThirdParty/LICENSE-ghostty.txt).
///
/// Threads: `wakeup_cb` and `action_cb` can arrive on libghostty's renderer or IO threads; the clipboard and
/// close callbacks arrive on the main thread, inside `ghostty_app_tick`.
@MainActor
public final class GhosttyRuntime {
    let app: ghostty_app_t
    /// Smalti's generated engine config file; `apply` rewrites it.
    private let configFile: URL
    private var observers: [NSObjectProtocol] = []

    /// `ghostty_app_new` clones `config`, so the caller may release it afterwards.
    public init(config: GhosttyConfig) throws(TerminalEngineError) {
        var runtime = Self.makeRuntimeConfig()
        guard let app = ghostty_app_new(&runtime, config.handle) else {
            throw .engineStartFailed(reason: "ghostty_app_new returned null")
        }
        self.app = app
        configFile = config.file
        Self.current = app
        ghostty_app_set_focus(app, NSApp?.isActive ?? false)
        observeAppFocusAndKeyboardLayout()
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if Self.current == app { Self.current = nil }
        ghostty_app_free(app)
    }

    /// Reloads the engine with a new appearance ("Recargar configuración"): rewrites the generated config file and
    /// hands it to the app and every surface. Main thread, like every libghostty app call.
    public func apply(_ appearance: TerminalAppearance) throws(TerminalEngineError) {
        try reload(configText: GhosttyConfigText.render(appearance))
    }

    /// Validates `configText` from a temporary file next to the engine config and replaces the config only when
    /// libghostty accepts it, so a rejected reload leaves the file in effect untouched.
    func reload(configText: String) throws(TerminalEngineError) {
        let candidate = configFile.deletingLastPathComponent()
            .appending(path: ".\(configFile.lastPathComponent).\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: candidate) }
        let config = try GhosttyConfig.load(text: configText, writingTo: candidate)
        try Self.replace(configFile, with: candidate)
        // libghostty derives the surfaces' settings synchronously and clones the app-level config ("the caller
        // owns the param", embedded.zig), so `config` is freed when it goes out of scope, as Ghostty.App does.
        ghostty_app_update_config(app, config.handle)
    }

    /// `rename(2)` swaps the file atomically within one directory, replacing any existing target.
    private static func replace(_ target: URL, with candidate: URL) throws(TerminalEngineError) {
        guard rename(candidate.path(percentEncoded: false), target.path(percentEncoded: false)) == 0 else {
            let reason = String(cString: strerror(errno))
            throw .configurationInvalid(
                diagnostics: ["cannot replace \(target.path(percentEncoded: false)): \(reason)"])
        }
    }

    /// The app that pending wakeups tick; nil once its runtime is gone.
    static var currentApp: ghostty_app_t? { current }

    private func observeAppFocusAndKeyboardLayout() {
        let center = NotificationCenter.default
        // Safe: the observers run on .main and are removed in deinit, before the app is freed.
        nonisolated(unsafe) let app = app
        for (name, isActive) in [
            (NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false),
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { ghostty_app_set_focus(app, isActive) }
                })
        }
        // libghostty rebuilds its keymap when the input source changes (e.g. Latin American ↔ US).
        observers.append(
            center.addObserver(
                forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { ghostty_app_keyboard_changed(app) }
            })
    }

    // MARK: - Callbacks (libghostty calls these from C)

    /// Built outside any actor: closures written inside the @MainActor init would inherit main-actor
    /// isolation and trap when libghostty calls them from its renderer or IO threads.
    nonisolated private static func makeRuntimeConfig() -> ghostty_runtime_config_s {
        ghostty_runtime_config_s(
            userdata: nil,
            supports_selection_clipboard: false,
            wakeup_cb: { _ in GhosttyRuntime.scheduleTick() },
            action_cb: { _, target, action in GhosttyRuntime.handle(action, target: target) },
            read_clipboard_cb: { userdata, location, state, mimes, count, _ in
                GhosttyRuntime.readClipboard(userdata, location: location, state: state, mimes: mimes, count: count)
            },
            confirm_read_clipboard_cb: { userdata, confirm, state, request in
                GhosttyRuntime.confirmClipboard(userdata, confirm: confirm, state: state, request: request)
            },
            write_clipboard_cb: { _, location, content, count, confirm in
                GhosttyRuntime.writeClipboard(location: location, content: content, count: count, confirm: confirm)
            },
            close_surface_cb: { userdata, _ in GhosttyRuntime.closeSurface(userdata) })
    }

    /// Written only on the main thread (init/deinit) and read on the main thread inside `scheduleTick`'s
    /// dispatched block, so the unchecked access never races.
    nonisolated(unsafe) private static var current: ghostty_app_t?

    nonisolated private static func scheduleTick() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let app = current { ghostty_app_tick(app) }
            }
        }
    }

    /// Called from the main thread (inside `ghostty_app_tick`) and from the renderer thread, so the event is
    /// mapped here and delivered on the main thread.
    nonisolated private static func handle(_ action: ghostty_action_s, target: ghostty_target_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface,
            let event = GhosttyActionMapper.event(for: action)
        else { return false }
        // Resolve the view now, while libghostty guarantees the surface is alive; deliver only if the same view
        // still owns the same surface when the main thread gets to it.
        guard let userdata = ghostty_surface_userdata(surface) else { return false }
        let viewAddress = Int(bitPattern: userdata)
        let surfaceAddress = Int(bitPattern: surface)
        let deliver: @MainActor @Sendable () -> Void = {
            liveView(at: viewAddress, surfaceAddress: surfaceAddress)?.deliver(event)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(deliver)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(deliver) }
        }
        return true
    }

    /// `close_surface_cb`: main thread, inside `ghostty_app_tick` (after a child exit, or a close binding). The view
    /// turns it into `.exited` or `.closeRequested` and delivers it on the next main loop turn.
    nonisolated private static func closeSurface(_ userdata: UnsafeMutableRawPointer?) {
        // Safe: called on the main thread inside ghostty_app_tick, so the pointer never crosses threads.
        nonisolated(unsafe) let userdata = userdata
        MainActor.assumeIsolated { view(from: userdata)?.requestClose() }
    }

    /// Paste: serves `text/plain` from the general pasteboard.
    nonisolated private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?,
        mimes: UnsafePointer<UnsafePointer<CChar>?>?, count: Int
    ) -> ghostty_clipboard_read_result_e {
        // Safe: called on the main thread inside ghostty_app_tick; the pointers are used before returning.
        nonisolated(unsafe) let (userdata, state, mimes) = (userdata, state, mimes)
        return MainActor.assumeIsolated {
            guard location == GHOSTTY_CLIPBOARD_STANDARD, let surface = view(from: userdata)?.surface else {
                return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED
            }
            let wantsText = (0..<count).contains { index in
                mimes?[index].map { String(cString: $0) } == "text/plain"
            }
            guard wantsText, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE
            }
            complete(surface, text: text, state: state, confirmed: false)
            return GHOSTTY_CLIPBOARD_READ_STARTED
        }
    }

    /// Unsafe pastes ask the user (asynchronously, outside ghostty_app_tick); every other request is denied.
    nonisolated private static func confirmClipboard(
        _ userdata: UnsafeMutableRawPointer?, confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
        state: UnsafeMutableRawPointer?, request: ghostty_clipboard_request_e
    ) {
        // Safe: called on the main thread inside ghostty_app_tick. The borrowed payload is copied before
        // returning; libghostty keeps `state` alive until the request is completed or denied.
        nonisolated(unsafe) let (userdata, state) = (userdata, state)
        let text = confirm.flatMap { ClipboardConfirmation.pasteText(from: $0.pointee) }
        MainActor.assumeIsolated {
            guard let view = view(from: userdata), let surface = view.surface else { return }
            guard ClipboardConfirmation.decision(for: request) == .askUser, let text else {
                ghostty_surface_deny_clipboard_request(surface, state)
                return
            }
            let viewAddress = Int(bitPattern: userdata)
            let surfaceAddress = Int(bitPattern: surface)
            nonisolated(unsafe) let pendingState = state
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let approved = ClipboardConfirmation.userApprovesPaste(of: text)
                    // The pane may have closed while the alert was open.
                    guard let surface = liveView(at: viewAddress, surfaceAddress: surfaceAddress)?.surface else {
                        return
                    }
                    if approved {
                        complete(surface, text: text, state: pendingState, confirmed: true)
                    } else {
                        ghostty_surface_deny_clipboard_request(surface, pendingState)
                    }
                }
            }
        }
    }

    /// Copy: writes `text/plain`. Writes that need confirmation (OSC 52) are dropped in F0.
    nonisolated private static func writeClipboard(
        location: ghostty_clipboard_e, content: UnsafePointer<ghostty_clipboard_content_s>?, count: Int, confirm: Bool
    ) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD, !confirm, let content else { return }
        let text = (0..<count).lazy.map { content[$0] }.first { String(cString: $0.mime) == "text/plain" }
            .flatMap { entry in
                entry.data.map { String(decoding: UnsafeRawBufferPointer(start: $0, count: entry.len), as: UTF8.self) }
            }
        guard let text else { return }
        MainActor.assumeIsolated {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private static func complete(
        _ surface: ghostty_surface_t, text: String, state: UnsafeMutableRawPointer?, confirmed: Bool
    ) {
        let bytes = Array(text.utf8)
        "text/plain".withCString { mime in
            bytes.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map { base in
                    // Safe: UInt8 and CChar have the same size and alignment; the buffer outlives the call.
                    base.withMemoryRebound(to: CChar.self, capacity: bytes.count) { data in
                        var content = ghostty_clipboard_content_s(mime: mime, data: data, len: bytes.count)
                        withUnsafePointer(to: &content) { contents in
                            var payload = ghostty_clipboard_complete_s(
                                contents: contents, contents_len: 1, available: nil, available_len: 0,
                                confirmed: confirmed, remember: false)
                            ghostty_surface_complete_clipboard_request(surface, &payload, state)
                        }
                    }
                }
            }
        }
    }

    private static func view(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        // Safe: every surface is created with an unretained pointer to its GhosttySurfaceView as userdata,
        // and the view frees its surface in shutDown() or, at the latest, in its deinit.
        userdata.map { Unmanaged<GhosttySurfaceView>.fromOpaque($0).takeUnretainedValue() }
    }

    // MARK: - Live views

    /// Live views (address → address of their surface). Asynchronous deliveries go only to a view still
    /// registered with the same surface, so a reused address never receives a stale event.
    private static var liveViews: [Int: Int] = [:]

    static var liveViewCount: Int { liveViews.count }

    static func register(_ view: GhosttySurfaceView) {
        liveViews[address(of: view)] = view.surfaceAddress
    }

    static func unregister(_ view: GhosttySurfaceView) {
        liveViews[address(of: view)] = nil
    }

    static func liveView(at viewAddress: Int, surfaceAddress: Int) -> GhosttySurfaceView? {
        guard liveViews[viewAddress] == surfaceAddress, let userdata = UnsafeMutableRawPointer(bitPattern: viewAddress)
        else { return nil }
        return view(from: userdata)
    }

    private static func address(of view: GhosttySurfaceView) -> Int {
        Int(bitPattern: Unmanaged.passUnretained(view).toOpaque())
    }
}

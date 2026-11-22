import AppKit
import GhosttyKit
import SmaltiCore

/// Owns the libghostty app and answers its runtime callbacks (wakeup, actions, clipboard, close).
/// Adapted from ghostty v1.4.0 macos/Sources/Ghostty/Ghostty.App.swift (MIT, see ThirdParty/LICENSE-ghostty.txt).
@MainActor
public final class GhosttyRuntime {
    let app: ghostty_app_t
    private let config: GhosttyConfig  // libghostty keeps referencing it for the app's lifetime.

    public init(config: GhosttyConfig) throws(TerminalEngineError) {
        self.config = config
        var runtime = Self.makeRuntimeConfig()
        guard let app = ghostty_app_new(&runtime, config.handle) else {
            throw .engineStartFailed(reason: "ghostty_app_new returned null")
        }
        self.app = app
        Self.current = app
        ghostty_app_set_focus(app, NSApp.isActive)
        observeAppFocusAndKeyboardLayout()
    }

    private func observeAppFocusAndKeyboardLayout() {
        let center = NotificationCenter.default
        nonisolated(unsafe) let app = app  // Observers run on .main, where libghostty expects these calls.
        for (name, isActive) in [
            (NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ghostty_app_set_focus(app, isActive) }
            }
        }
        // libghostty rebuilds its keymap when the input source changes (e.g. Latin American ↔ US).
        center.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ghostty_app_keyboard_changed(app) }
        }
    }

    isolated deinit {
        ghostty_app_free(app)
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
            confirm_read_clipboard_cb: { userdata, _, state, _ in GhosttyRuntime.denyClipboard(userdata, state: state)
            },
            write_clipboard_cb: { _, location, content, count, confirm in
                GhosttyRuntime.writeClipboard(location: location, content: content, count: count, confirm: confirm)
            },
            close_surface_cb: { userdata, _ in GhosttyRuntime.closeSurface(userdata) })
    }

    /// The single app of this process; read by `scheduleTick`, which libghostty may call from any thread.
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
        // Resolve the view now, while libghostty guarantees the surface is alive, and check on the main
        // thread that it was not closed in between.
        guard let userdata = ghostty_surface_userdata(surface) else { return false }
        let viewAddress = Int(bitPattern: userdata)
        let deliver: @MainActor @Sendable () -> Void = {
            guard liveViews.contains(viewAddress), let userdata = UnsafeMutableRawPointer(bitPattern: viewAddress)
            else { return }
            view(from: userdata)?.deliver(event)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(deliver)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(deliver) }
        }
        return true
    }

    nonisolated private static func closeSurface(_ userdata: UnsafeMutableRawPointer?) {
        // libghostty calls every callback except wakeup on the main thread, inside ghostty_app_tick.
        nonisolated(unsafe) let userdata = userdata
        MainActor.assumeIsolated { view(from: userdata)?.requestClose() }
    }

    /// Paste: serves `text/plain` from the general pasteboard.
    nonisolated private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?,
        mimes: UnsafePointer<UnsafePointer<CChar>?>?, count: Int
    ) -> ghostty_clipboard_read_result_e {
        nonisolated(unsafe) let (userdata, state, mimes) = (userdata, state, mimes)
        return MainActor.assumeIsolated {
            guard location == GHOSTTY_CLIPBOARD_STANDARD, let surface = view(from: userdata)?.surface else {
                return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED
            }
            let wantsText = (0..<count).contains { index in
                mimes?[index].map { String(cString: $0) } == "text/plain"
            }
            guard wantsText, let text = NSPasteboard.general.string(forType: .string) else {
                return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE
            }
            complete(surface, text: text, state: state)
            return GHOSTTY_CLIPBOARD_READ_STARTED
        }
    }

    /// F0 denies every read that needs confirmation (OSC 52 reads by programs).
    nonisolated private static func denyClipboard(_ userdata: UnsafeMutableRawPointer?, state: UnsafeMutableRawPointer?)
    {
        nonisolated(unsafe) let (userdata, state) = (userdata, state)
        MainActor.assumeIsolated {
            if let surface = view(from: userdata)?.surface { ghostty_surface_deny_clipboard_request(surface, state) }
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

    private static func complete(_ surface: ghostty_surface_t, text: String, state: UnsafeMutableRawPointer?) {
        let bytes = Array(text.utf8)
        "text/plain".withCString { mime in
            bytes.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map { base in
                    base.withMemoryRebound(to: CChar.self, capacity: bytes.count) { data in
                        var content = ghostty_clipboard_content_s(mime: mime, data: data, len: bytes.count)
                        withUnsafePointer(to: &content) { contents in
                            var payload = ghostty_clipboard_complete_s(
                                contents: contents, contents_len: 1, available: nil, available_len: 0,
                                confirmed: false, remember: false)
                            ghostty_surface_complete_clipboard_request(surface, &payload, state)
                        }
                    }
                }
            }
        }
    }

    private static func view(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        // Safe: every surface is created with an unretained pointer to its GhosttySurfaceView as userdata,
        // and the view frees the surface before it is deallocated.
        userdata.map { Unmanaged<GhosttySurfaceView>.fromOpaque($0).takeUnretainedValue() }
    }

    /// Addresses of views whose surface is alive; guards events delivered asynchronously.
    private static var liveViews: Set<Int> = []

    static func register(_ view: GhosttySurfaceView) {
        liveViews.insert(Int(bitPattern: Unmanaged.passUnretained(view).toOpaque()))
    }

    static func unregister(_ view: GhosttySurfaceView) {
        liveViews.remove(Int(bitPattern: Unmanaged.passUnretained(view).toOpaque()))
    }
}

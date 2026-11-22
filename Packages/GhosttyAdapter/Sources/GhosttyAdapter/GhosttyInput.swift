import AppKit
import GhosttyKit

/// NSEvent → libghostty input translation.
/// Adapted from ghostty v1.4.0 macos/Sources/Ghostty/NSEvent+Extension.swift and Ghostty.Input.swift
/// (MIT, see ThirdParty/LICENSE-ghostty.txt).
@MainActor
enum GhosttyInput {
    static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        let raw = flags.rawValue
        if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(mods)
    }

    static func flags(_ mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    /// Bit 0: precise (trackpad); bits 1–3: momentum phase.
    static func scrollMods(precise: Bool, momentum: NSEvent.Phase) -> ghostty_input_scroll_mods_t {
        let phase: Int32 =
            switch momentum {
            case .began: 1
            case .stationary: 2
            case .changed: 3
            case .ended: 4
            case .cancelled: 5
            case .mayBegin: 6
            default: 0
            }
        return (precise ? 1 : 0) | (phase << 1)
    }

    static func modifier(forKeyCode keyCode: UInt16) -> UInt32? {
        switch keyCode {
        case 0x39: GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: GHOSTTY_MODS_SUPER.rawValue
        default: nil
        }
    }

    /// PRESS or RELEASE for a modifier key event, telling left from right: releasing right Shift while left
    /// Shift is still held is a release, even though the Shift flag stays set. Nil for non-modifier keys.
    static func modifierAction(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> ghostty_input_action_e? {
        guard let modifier = modifier(forKeyCode: keyCode) else { return nil }
        guard mods(flags).rawValue & modifier != 0 else { return GHOSTTY_ACTION_RELEASE }
        let raw = flags.rawValue
        let sidePressed: Bool =
            switch keyCode {
            case 0x38: raw & UInt(NX_DEVICELSHIFTKEYMASK) != 0
            case 0x3C: raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3B: raw & UInt(NX_DEVICELCTLKEYMASK) != 0
            case 0x3E: raw & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3A: raw & UInt(NX_DEVICELALTKEYMASK) != 0
            case 0x3D: raw & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x37: raw & UInt(NX_DEVICELCMDKEYMASK) != 0
            case 0x36: raw & UInt(NX_DEVICERCMDKEYMASK) != 0
            default: true
            }
        return sidePressed ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    }

    /// Arrow keys that commit a preedit still move the cursor; plain ← is left out because AppKit already
    /// leaves the caret in place after some IMEs commit (Ghostty's rule).
    static func shouldReplayAfterCommittingPreedit(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 124, 125, 126: true
        case 123: !modifiers.isDisjoint(with: [.shift, .control, .option, .command])
        default: false
        }
    }

    /// The key changed the input source (and was not part of a composition): it must not reach the terminal.
    static func isInputSourceSwitch(hadMarkedText: Bool, layoutBefore: String?, layoutAfter: String?) -> Bool {
        !hadMarkedText && layoutBefore != layoutAfter
    }

    /// Applies libghostty's translation modifiers (option-as-alt) while keeping the event's hidden bits,
    /// which dead keys depend on. The original event must be reused when nothing changes (Korean IME).
    static func translationEvent(for event: NSEvent, surface: ghostty_surface_t) -> NSEvent {
        let translated = flags(ghostty_surface_key_translation_mods(surface, mods(event.modifierFlags)))
        var modifiers = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translated.contains(flag) { modifiers.insert(flag) } else { modifiers.remove(flag) }
        }
        guard modifiers != event.modifierFlags else { return event }
        return NSEvent.keyEvent(
            with: event.type, location: event.locationInWindow, modifierFlags: modifiers,
            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
            characters: event.characters(byApplyingModifiers: modifiers) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat, keyCode: event.keyCode) ?? event
    }

    static func keyEvent(
        _ action: ghostty_input_action_e, event: NSEvent, translationMods: NSEvent.ModifierFlags?
    ) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = mods(event.modifierFlags)
        // ⌃ and ⌘ never produce text on macOS; assume every other held modifier did.
        key.consumed_mods = mods((translationMods ?? event.modifierFlags).subtracting([.control, .command]))
        if event.type == .keyDown || event.type == .keyUp,
            let scalar = event.characters(byApplyingModifiers: [])?.unicodeScalars.first
        {
            key.unshifted_codepoint = scalar.value
        }
        return key
    }

    /// Text for a key event: control characters go without ⌃ (libghostty encodes them) and
    /// function keys (private-use range) send no text.
    static func characters(of event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            if (0xF700...0xF8FF).contains(scalar.value) { return nil }
        }
        return characters
    }

    /// Text to attach to a key event, or nil when libghostty must encode the key from its keycode:
    /// text starting with an ASCII control character (synthesized spaces arrive as "\0", Return as "\r").
    static func keyEventText(_ text: String?) -> String? {
        guard let text, let first = text.unicodeScalars.first else { return nil }
        return first.value < 0x20 || first.value == 0x7F ? nil : text
    }

    /// A lone control character produced while an input method is composing belongs to the IME.
    static func isControlInput(_ text: String?, composing: Bool) -> Bool {
        guard composing, let text, text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else {
            return false
        }
        return scalar.value < 0x20
    }

    static func isBinding(_ event: NSEvent, surface: ghostty_surface_t) -> Bool {
        var key = keyEvent(GHOSTTY_ACTION_PRESS, event: event, translationMods: nil)
        var flags = ghostty_binding_flags_e(0)
        return (event.characters ?? "").withCString { pointer in
            key.text = pointer
            return ghostty_surface_key_is_binding(surface, key, &flags)
        }
    }
}

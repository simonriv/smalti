/// The prompt studio (spec F5): edits a draft shown in the board's three situations; "Aplicar a todos los paneles"
/// writes it at once. The app then sends `RenderPrompt.styleMessage()` to every shell.
@MainActor
public final class EditPrompt {
    public var draft: PromptConfig
    private let appearance: ChangeAppearance
    private let copy: PromptCopy

    public init(appearance: ChangeAppearance, copy: PromptCopy) {
        self.appearance = appearance
        self.copy = copy
        draft = appearance.document.prompt
    }

    public func preview(_ situation: PreviewSituation) -> [[PreviewRun]] {
        let theme = ThemeCatalog.apply(appearance.document.appearance).theme
        return PromptPreview.lines(draft, context: situation.context(copy), theme: theme)
    }

    public func apply() {
        appearance.apply { $0.prompt = draft }
        appearance.saveNow()
    }

    /// Moves an active module up (negative) or down by `offset` places; the others keep their order, and past either
    /// end it stops there (block 5 review, I2).
    public func move(_ id: PromptModuleID, by offset: Int) {
        guard let index = draft.modules.firstIndex(of: id) else { return }
        let target = min(max(index + offset, 0), draft.modules.count - 1)
        draft.modules.remove(at: index)
        draft.modules.insert(id, at: target)
    }

    /// Off removes it; on adds it at the end.
    public func toggle(_ id: PromptModuleID) {
        if let index = draft.modules.firstIndex(of: id) {
            draft.modules.remove(at: index)
        } else {
            draft.modules.append(id)
        }
    }

    /// The studio's list: active modules in order, then the others in the board's order.
    public var moduleList: [ModuleRow] {
        let inactive = PromptModuleID.allCases.filter { !draft.modules.contains($0) }
        return draft.modules.map { ModuleRow(id: $0, isActive: true) }
            + inactive.map { ModuleRow(id: $0, isActive: false) }
    }
}

public struct ModuleRow: Equatable, Sendable {
    public let id: PromptModuleID
    public let isActive: Bool
}

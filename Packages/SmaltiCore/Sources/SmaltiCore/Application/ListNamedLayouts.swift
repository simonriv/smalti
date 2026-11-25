/// The saved layouts as the palette lists them. One that cannot be read is left out; one a newer Smalti saved is
/// listed with its format, so the user sees why it does not open (F7.6).
@MainActor
public struct ListNamedLayouts {
    private let layouts: any NamedLayouts

    public init(layouts: any NamedLayouts) {
        self.layouts = layouts
    }

    public func execute() -> [NamedLayoutSummary] {
        layouts.names().compactMap(summary)
    }

    private func summary(_ name: LayoutName) -> NamedLayoutSummary? {
        do {
            return NamedLayoutSummary(name: name, layout: try layouts.layout(named: name))
        } catch .newerFormat(_, let version) {
            return NamedLayoutSummary(name: name, newerFormat: version)
        } catch {
            return nil
        }
    }
}

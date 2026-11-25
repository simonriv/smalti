import SmaltiCore

/// In-memory `AppUpdates`: counts the checks and keeps the automatic flag.
@MainActor
public final class FakeAppUpdates: AppUpdates {
    public private(set) var checks = 0
    public private(set) var isAutomatic: Bool

    public init(isAutomatic: Bool) {
        self.isAutomatic = isAutomatic
    }

    public func checkNow() { checks += 1 }

    public func setAutomatic(_ isOn: Bool) { isAutomatic = isOn }
}

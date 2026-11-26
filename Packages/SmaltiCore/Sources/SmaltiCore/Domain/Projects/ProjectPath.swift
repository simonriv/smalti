/// A path as the projects show it: `~` for this home.
public enum ProjectPath {
    public static func display(_ path: String, home: String) -> String { PortablePaths(home: home).portable(path) }
}

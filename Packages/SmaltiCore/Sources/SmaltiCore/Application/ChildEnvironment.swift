/// Environment variables every pane's process receives so tools can detect they run inside Smalti.
public enum ChildEnvironment {
    public static func smalti(version: String) -> [String: String] {
        ["SMALTI": "1", "SMALTI_VERSION": version]
    }
}

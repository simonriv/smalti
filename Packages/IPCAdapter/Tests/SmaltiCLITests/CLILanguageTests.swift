import Foundation
import SmaltiCore
import Testing

@testable import smalti

/// F7.7: the CLI speaks the app's language, which the app exports to every pane as `SMALTI_LANGUAGE`.
@Suite("CLI language")
struct CLILanguageTests {
    @Test(arguments: [
        (["SMALTI_LANGUAGE": "en"], ["es-CO"], InterfaceLanguage.english),
        (["SMALTI_LANGUAGE": "es"], ["en-US"], .spanish),
        (["SMALTI_LANGUAGE": "fr"], ["es-CO"], .spanish),
        (["SMALTI_LANGUAGE": ""], ["en-GB"], .english),
        ([:], ["es-419"], .spanish),
        ([:], ["fr-FR"], .english),
    ])
    func environmentFirstThenTheSystem(environment: [String: String], preferred: [String], expected: InterfaceLanguage)
    {
        #expect(CLILanguage.resolve(environment: environment, preferred: preferred) == expected)
    }

    @Test func guardReasonFollowsTheLanguage() throws {
        let input = Data(#"{"tool_name":"Read","tool_input":{"file_path":"/p/.env"},"cwd":"/p"}"#.utf8)

        let english = EventCommand.preToolUseOutput(input, environment: ["SMALTI_LANGUAGE": "en", "HOME": "/Users/x"])
        let spanish = EventCommand.preToolUseOutput(input, environment: ["SMALTI_LANGUAGE": "es", "HOME": "/Users/x"])

        #expect(english.contains("Smalti blocks reading secret files"))
        #expect(spanish.contains("Smalti bloquea la lectura de archivos de secretos"))
    }

    @Test func usageIsInTheLanguage() {
        #expect(TerminalTexts.english.cliUsage.hasPrefix("usage: smalti event <Hook>"))
        #expect(TerminalTexts.spanish.cliUsage.hasPrefix("uso: smalti event <Hook>"))
    }
}

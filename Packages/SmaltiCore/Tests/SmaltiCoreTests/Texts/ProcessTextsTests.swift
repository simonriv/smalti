import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("ProcessTexts")
struct ProcessTextsTests {
    @Test func bothLanguagesAreComplete() {
        let problems = TextCatalogAudit.problems(spanish: ProcessTexts.spanish, english: ProcessTexts.english)

        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func confirmationOfTheSpec() {
        let es = ProcessTexts.spanish

        #expect(es.confirmTitle(["name": "python3", "pid": "50112"]) == "¿Forzar el cierre de python3 (50112)?")
        #expect(
            ProcessTexts.english.confirmBody(["seconds": "3"])
                == "It did not respond to “Stop” within 3 s. Forcing it (SIGKILL) ends it without letting it save anything."
        )
    }

    @Test func pluralsOfTheCards() {
        #expect(ProcessTexts.spanish.ports(1) == "1 puerto")
        #expect(ProcessTexts.english.openToNetwork(2) == "2 open to the network")
        #expect(ProcessTexts.spanish.processes(312) == "312 procesos")
    }
}

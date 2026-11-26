import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("ProjectTexts")
struct ProjectTextsTests {
    @Test func bothLanguagesAreComplete() {
        let problems = TextCatalogAudit.problems(spanish: ProjectTexts.spanish, english: ProjectTexts.english)

        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func confirmationOfTheSpec() {
        #expect(ProjectTexts.spanish.openTitle(["name": "rizaria"]) == "¿Abrir el proyecto “rizaria”?")
        #expect(ProjectTexts.english.openTitle(["name": "rizaria"]) == "Open the project “rizaria”?")
        #expect(
            ProjectTexts.spanish.firstTime == "Es la primera vez que abres este layout. Al abrirlo ejecutará:")
        #expect(
            ProjectTexts.spanish.source(["root": "~/dev/rizaria"])
                == "Viene de ~/dev/rizaria/.smalti/layout.json. Sin aprobar no se ejecuta nada; Smalti recuerda lo que apruebes, nunca en el repo."
        )
    }

    @Test func fileErrorsSayWhy() {
        #expect(
            ProjectFileError.missing(root: "~/dev/x").message(.spanish, layout: .spanish)
                == "~/dev/x ya no tiene .smalti/layout.json")
        #expect(
            ProjectFileError.invalid(.outsideProject(pane: 2, path: "/etc")).message(.english, layout: .english)
                == "pane 2 is outside the project: /etc")
    }
}

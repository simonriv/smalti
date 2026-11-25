import SmaltiCore
import Testing

/// The commands of the three incidents the roadmap names (spec F7.5, «Incidentes»).
enum IncidentCommands {
    static let replit = "npm run db:push"
    static let replitEnvironmentHost = "ep-x.neon.tech"
    static let dataTalks = "terraform destroy -auto-approve"
    static let pocketOS = #"""
        curl -X POST https://backboard.railway.app/graphql/v2 -H "Authorization: Bearer $RAILWAY_TOKEN" -H "Content-Type: application/json" -d '{"query":"mutation { volumeDelete(volumeId: \"vol_1\") }"}'
        """#
}

@Suite("Incident commands")
struct IncidentCommandsTests {
    @Test func replitDbPush() {
        let finding = guardFindings(IncidentCommands.replit, environmentHosts: [IncidentCommands.replitEnvironmentHost])
            .first

        #expect(finding?.rule == "npm run db:push")
        #expect(finding?.environment.label == "PROD")
        #expect(finding?.environment.detail == "host no reconocido")
    }

    @Test func dataTalksTerraformDestroy() {
        let finding = guardFindings(IncidentCommands.dataTalks).first

        #expect(finding?.rule == "terraform destroy")
        #expect(finding?.environment.label == "PROD")
        #expect(finding?.environment.detail == "no determinado")
    }

    @Test func pocketOSRailwayVolumeDelete() {
        #expect(guardFindings(IncidentCommands.pocketOS).map(\.rule) == ["API de Railway (POST)"])
    }
}

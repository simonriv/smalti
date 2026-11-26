import SmaltiCore
import Testing

/// What the guard finds in a command line, with the given settings and hosts from the hook's environment.
func guardFindings(
    _ text: String, settings: GuardSettings = .standard, environmentHosts: [String] = []
) -> [GuardFinding] {
    DestructiveCommandRules.findings(
        in: text, context: GuardContext(settings: settings, environmentHosts: environmentHosts, texts: .spanish),
        home: "/Users/u")
}

@Suite("Destructive command rules")
struct DestructiveRulesTests {
    @Test(arguments: [
        ("supabase db push", "supabase db push"), ("supabase db reset", "supabase db reset"),
        ("supabase projects delete abc", "supabase projects delete"),
        ("supabase branches delete dev", "supabase branches delete"),
        ("prisma migrate reset --force", "prisma migrate reset"), ("npx prisma db push", "prisma db push"),
        ("drizzle-kit push", "drizzle-kit push"), ("pnpm dlx drizzle-kit drop", "drizzle-kit drop"),
        ("npm run db:push", "npm run db:push"), ("pnpm db:reset", "pnpm db:reset"), ("yarn db:push", "yarn db:push"),
        ("bun run db:push", "bun run db:push"), ("npm run database-drop", "npm run database-drop"),
        ("npm run prisma:reset", "npm run prisma:reset"), ("npm run db:migrate:reset", "npm run db:migrate:reset"),
        ("terraform destroy", "terraform destroy"), ("terraform apply -auto-approve", "terraform apply"),
        ("tofu destroy", "tofu destroy"), ("terragrunt run-all apply", "terragrunt apply"),
        ("terraform -chdir=infra destroy", "terraform destroy"),
        ("/opt/homebrew/bin/terraform destroy", "terraform destroy"),
        ("railway volume delete vol_1", "railway volume delete"), ("railway down", "railway down"),
        ("psql -c \"DROP TABLE users\"", "psql con DROP"), ("psql -c 'drop table a'", "psql con DROP"),
        ("mysql -e 'TRUNCATE t'", "mysql con TRUNCATE"), ("psql -f x.sql", "psql sin SQL visible"),
        ("psql < x.sql", "psql sin SQL visible"), ("cat x.sql | psql", "psql sin SQL visible"),
        ("dropdb app", "dropdb"),
    ])
    func detects(command: String, rule: String) {
        #expect(guardFindings(command).map(\.rule).contains(rule))
    }

    @Test(arguments: [
        "supabase db diff", "supabase start", "terraform plan", "terraform init", "prisma generate",
        "prisma migrate dev", "drizzle-kit generate", "npm run dev", "npm run db:generate", "npm run push",
        "pnpm install", "railway logs", "railway up", "psql -c \"select 1\"", "psql -c 'select drop_column from t'",
        "psql --version", "curl https://api.vercel.com/v2/user", "curl -G https://api.vercel.com/x --data a=1",
        "curl -X GET https://api.supabase.com/v1/projects", "curl -I https://api.fly.io/x", "git push",
        "echo terraform destroy", "ls",
    ])
    func ignoresNearbyInnocentCommands(command: String) {
        #expect(guardFindings(command).isEmpty)
    }

    @Test(arguments: [
        "bash -c 'terraform destroy'", "sudo terraform destroy", "env X=1 terraform destroy",
        "echo $(terraform destroy)", "ssh ops 'terraform destroy'", "cd infra && terraform destroy",
        "make x; terraform destroy", "true | terraform destroy",
    ])
    func detectsWrappedAndChained(command: String) {
        #expect(guardFindings(command).map(\.rule) == ["terraform destroy"])
    }

    @Test(arguments: [
        ("curl -X DELETE https://api.vercel.com/v9/projects/x", "API de Vercel (DELETE)"),
        ("curl --request=PATCH https://api.supabase.com/v1/projects/x", "API de Supabase (PATCH)"),
        ("curl -XPOST https://api.fly.io/graphql", "API de Fly (POST)"),
        ("curl -d '{}' https://api.render.com/v1/services/x/suspend", "API de Render (POST)"),
        ("curl --json '{}' https://backboard.railway.com/graphql/v2", "API de Railway (POST)"),
        ("curl -F a=@x https://api.netlify.com/api/v1/sites", "API de Netlify (POST)"),
        ("curl -T x https://s3.amazonaws.com/b/k", "API de AWS (PUT)"),
        ("wget --method=DELETE https://api.heroku.com/apps/x", "API de Heroku (DELETE)"),
        ("wget --post-data=x https://api.digitalocean.com/v2/droplets", "API de DigitalOcean (POST)"),
        ("http DELETE api.fly.io/v1/apps/x", "API de Fly (DELETE)"),
        ("xh POST https://api.cloudflare.com/client/v4/zones name=x", "API de Cloudflare (POST)"),
        ("http api.planetscale.com/v1/x name=y", "API de PlanetScale (POST)"),
        ("curl -X DELETE https://compute.googleapis.com/x", "API de Google Cloud (DELETE)"),
        ("curl -X DELETE https://console.neon.tech/api/v2/projects/x", "API de Neon (DELETE)"),
        ("curl -X DELETE https://management.azure.com/x", "API de Azure (DELETE)"),
    ])
    func detectsProviderAPIWrites(command: String, rule: String) {
        #expect(guardFindings(command).map(\.rule) == [rule])
    }

    @Test func providerHostsFromSettings() {
        var settings = GuardSettings.standard
        settings.providerAPIHosts = ["*.example-cloud.com"]

        #expect(
            guardFindings("curl -X DELETE https://api.example-cloud.com/x", settings: settings).map(\.rule) == [
                "API de api.example-cloud.com (DELETE)"
            ])
        #expect(guardFindings("curl -X DELETE https://api.example-cloud.com/x").isEmpty)
    }

    @Test func databaseURLRuleNeedsARemoteHost() {
        let remote = "DATABASE_URL=postgres://u:p@db.abc.supabase.co:5432/app node seed.js"
        var settings = GuardSettings.standard
        settings.nonProductionHosts = ["db.abc.supabase.co"]

        #expect(guardFindings(remote).map(\.rule) == ["URL de base de datos"])
        #expect(guardFindings("node seed.js postgres://localhost/app").isEmpty)
        #expect(guardFindings(remote, settings: settings).isEmpty)
    }

    @Test func supabaseLocalFlagIsLocal() {
        #expect(guardFindings("supabase db reset --local").first?.environment.kind == .local)
    }

    @Test func supabaseDbURLUsesItsHost() {
        let finding = guardFindings("supabase db push --db-url postgres://u:p@db.x.supabase.co/postgres").first

        #expect(
            finding?.environment
                == DetectedEnvironment(kind: .production, host: "db.x.supabase.co", cause: .unrecognizedHost))
    }

    @Test func supabaseDefaultIsLinkedProject() {
        let environment = guardFindings("supabase db push").first?.environment

        #expect(environment?.kind == .production)
        #expect(environment?.detail(.spanish) == "proyecto enlazado")
    }

    @Test func databaseCommandsUseTheEnvironmentHost() {
        let environment = guardFindings("npm run db:push", environmentHosts: ["localhost"]).first?.environment

        #expect(environment?.kind == .local)
    }

    @Test func commandURLBeatsTheEnvironment() {
        let text = "DATABASE_URL=postgres://u@localhost/x prisma migrate reset"

        #expect(guardFindings(text, environmentHosts: ["db.prod.example.com"]).first?.environment.kind == .local)
    }

    @Test func psqlHostOption() {
        #expect(guardFindings("psql -h db.x.com -c 'drop table a'").first?.environment.host == "db.x.com")
    }
}

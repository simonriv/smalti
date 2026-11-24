# F5 · Apariencia y prompt — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (modo nativo, `.claude/rules/workflow.md`: revisión por bloque con un revisor nuevo). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cambiar tema, vidrio, colores, botones de ventana, tipografía y prompt desde la app, con vista en vivo, y que `theme.toml` y la UI digan siempre lo mismo. Además: el fantasma a 4.5:1 con "Proteger legibilidad" y la GPU en reposo (#5).

**Architecture:**
- **Dominio puro** (`SmaltiCore`):
  - en `Domain/Theme`: `ThemeCatalog` con los cuatro temas, `ANSIPalette` con diferencias por tema, `ContrastRatio` y `LegibilityGuard`;
  - en `Domain/Prompt`: `PromptConfig`, un tipo por módulo (`PromptModule`), un tipo por estilo (`PromptStyle`), `ZshPromptRenderer` y `StarshipPreset`.
- **Puertos nuevos:** `AppearanceStore` (`save`) y `PromptFacts` (`facts(for:)`). Casos de uso `ChangeAppearance`, `EditPrompt` y `RenderPrompt`. Mensajes nuevos del canal de F4: `context`, `prompt` y `promptstyle`.
- **Adaptadores:**
  - `TOMLConfigAdapter`: lee `theme.toml` encima de `config.toml`, lo escribe entero y genera el texto de `starship.toml`;
  - `ProjectContextAdapter`: cambios de git, raíz del repo y versiones de runtime;
  - `GhosttyAdapter`: config del motor por tema, `font-codepoint-map` hacia `SmaltiSymbols` y el script de zsh del prompt.
- **App (AppKit):**
  - capas de legibilidad;
  - botones de ventana;
  - superposiciones de Apariencia y del Estudio de prompt, que encogen la zona de paneles;
  - prompt conectado al `InputCoordinator`;
  - contexto en la cabecera para "Solo símbolo".

**Tech Stack:** Swift 6.4 (Xcode 27.2), AppKit, Swift Testing, XCUITest, libghostty v1.4.0, zsh 5.9, fontTools 4.60 (solo para generar la fuente; el `.ttf` se versiona), `scripts/mutation/mutate.py`.

**Spec:** `docs/specs/F5-apariencia-prompt.md` (aprobada 2026-11-23) · Maquetas: `docs/specs/F5-assets/mockup-{themes,buttons,prompt,legibility}.png` y `generate-mockups.py` (`THEMES`, tabla fuente de los colores) · Diseño: `docs/design/Apariencia.dc.html`, `Prompt.dc.html`, `README.md` · Convenciones: `CLAUDE.md`, `.claude/rules/`

## Global Constraints

- **Aislamiento:**
  - `SmaltiCore` solo usa `Foundation` para tipos de valor. La guarda de imports no se toca.
  - Solo `GhosttyAdapter` importa GhosttyKit. Solo `TOMLConfigAdapter` lee y escribe TOML.
  - Solo `ProjectContextAdapter` lanza `git` y los ejecutables de runtime.
  - La app nunca escribe `config.toml` (C14).
- **Atajos:** ⌘, abre Apariencia (`appearance.open`), ⇧⌘P el Estudio (`prompt.studio`) y ⌥⌘, el TOML (`config.open`).
- **Ids nuevos sin atajo** (tal cual): `theme.open`, `theme.next`, `ansi.reset`, `prompt.apply`, `prompt.export`, `legibility.toggle`.
- **Valores fijados por la spec:**
  - opacidad del vidrio de 0.30 a 0.95; desenfoque de 0 a 48 px;
  - contraste mínimo 4.5; mezcla del fantasma en pasos del 1 %;
  - peor escritorio: blanco para los temas oscuros y negro para Niebla;
  - pareja de fondo excluida de la protección: ANSI 0 y 8 en los temas oscuros, 7 y 15 en Niebla;
  - botones de ventana: margen de 72 px; fundido de 150 ms, que se quita con "Reducir movimiento";
  - guardado de Apariencia 300 ms después del último cambio;
  - `git status --porcelain=v2 --untracked-files=no` con un máximo de 300 ms;
  - duración visible desde 2 s; píldoras con su color al 16 % mezclado en opaco;
  - `SmaltiSymbols` en U+E900–U+E91F;
  - mensajes del canal de menos de 2000 bytes;
  - GPU en reposo ≤ 10 % (C6);
  - `MARKETING_VERSION = 0.5.0`.
- **`theme.toml`:** las claves y valores del bloque de la spec, tal cual: `theme` (`obsidiana`, `niebla`, `ambar-nocturno`, `bosque`), `protect_legibility`, `[appearance.ansi.<tema>]`, `[window] buttons` (`hidden`, `hover`, `visible`), `[prompt] source`, `style` (`clean`, `pills`, `symbol-only`), `layout` (`two-lines`, `one-line`), `modules` (`directory`, `git-branch`, `git-status`, `runtime`, `duration`, `agents`, `time`, `cloud`), `icons` (`thin`, `nerd`, `none`) y `symbol` (`›`, `❯`, `λ`, `$`). Por defecto: `obsidiana`, `true`, `hidden`, `smalti`, `clean`, `two-lines`, los seis primeros módulos, `thin` y `›`.
- **Textos:** los de los tableros tal cual, más los de "Textos nuevos" de la spec. En la UI, "Estado del agente del panel" pasa a "Agentes que esperan".
- **Tokens:** todos salen de `ThemeCatalog`, sin valores sueltos en las vistas. Los colores de Niebla, Ámbar nocturno y Bosque salen de `THEMES` en `generate-mockups.py`.
- **Swift:**
  - Swift 6 estricto, con errores `throws(Tipo)` que llevan operación, dato y causa;
  - prohibido `!`, `try!`, `as!` y `unsafe*` sin un comentario que justifique por qué es seguro;
  - 3 parámetros como máximo;
  - `struct` y `enum` por defecto;
  - módulos y estilos como tipos que implementan un protocolo, nunca un `switch` por tipo (OCP).
- **Pruebas:**
  - Swift Testing, en Arrange/Act/Assert, un concepto por prueba, con TDD;
  - contratos compartidos nuevos: `AppearanceStoreContract` (`InMemoryAppearanceStore` y `TOMLAppearanceStore`) y `PromptFactsContract` (`FakePromptFacts` y `FilePromptFacts`).
- **UI tests:**
  - `isolatedSmalti()` (`/bin/zsh -f`), o `isolatedSmaltiWithIntegration()` (`/bin/zsh -d` con ZDOTDIR temporal) en las del prompt;
  - `theme.toml` y el destino de la exportación, temporales;
  - `PasteboardGuard`;
  - una sola corrida: `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/check-daily-untouched.sh scripts/test-ui.sh <Clase …>`, solo con lo afectado.
- **Apps GUI lanzadas a mano:** siempre con `env -i`.
- **Mutación:** durante la fase, `mutate.py --package Packages/SmaltiCore --changed-since develop`; la completa, solo en T20.

## Review Focus

1. **Un `theme.toml` editado a mano mientras la UI está abierta,** o con una clave inválida, o con `[appearance.ansi.bosque] 16 = "#fff"`. Se espera:
   - la UI muestra lo del archivo al recargar;
   - un valor inválido no se aplica y se avisa con el archivo, la línea y la clave;
   - el guardado de la UI no pisa la edición a mano.

   Lo cubren T9 (`invalidAnsiIndexNamesLine`, `saveMergesExternalEditFirst`) y T16 (`handEditShowsInPanelAfterReload`).
2. **Nombres hostiles en el prompt:** una rama `$(touch pwned)%F{red}`, un directorio con `%`, `\` o un salto de línea, o un `AWS_PROFILE` con tab. Se muestran literales, nunca se ejecutan y no rompen el canal. Lo cubren T6 (`branchWithSubstitutionStaysLiteral`, `percentInDirectoryIsEscaped`, `newlineInNameIsReplaced`) y T11 (`hostileBranchDoesNotRunWithPromptSubst`).
3. **Smalti mudo o caído a mitad de sesión:** el servidor deja de leer, o la app se cierra con shells vivos en otra terminal. El shell nunca espera, queda la última inmediata y nunca muere por SIGPIPE. Lo cubre T11 (`silentServerDoesNotDelayPrompt`, `closedChannelKeepsLastImmediatePrompt`).
4. **Una paleta ANSI editada que no llega a 4.5:1** (negro sobre Obsidiana), o la opacidad al 30 %. Con protección, cada color se pinta a ≥ 4.5:1 y el TOML guarda lo elegido. Sin protección, se pinta tal cual. Lo cubren T2 (`unreachableUserColorIsAdjusted`, `adjustedColorsAreCounted`) y T3 (`lowestOpacityStillProtected`).
5. **Envío espontáneo de "Agentes que esperan" que llega tarde:** el usuario ya ejecutó otro comando, o está a mitad de escribir. Un `prompt` con un `seq` viejo se descarta, y uno vigente no toca `BUFFER` ni el fantasma. Lo cubren T7 (`spontaneousPromptUsesLastContextSeq`) y T11 (`staleSpontaneousPromptIsDropped`, `spontaneousPromptKeepsBuffer`).

## Mapa de archivos

| Ruta | Responsabilidad |
| --- | --- |
| `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Theme/{ThemeID,ThemeCatalog,Theme+Niebla,Theme+Amber,Theme+Forest,ANSIPalette,ContrastRatio,LegibilityGuard,ProtectedSurfaces}.swift` | Temas, contraste y protección |
| `…/Domain/Theme/{Theme,Theme+Obsidian}.swift` | `Theme.applying` con tema, paleta y protección; Obsidiana entra al catálogo |
| `…/Domain/Prompt/{PromptConfig,PromptModule,PromptModules,PromptStyle,PromptStyles,PromptContext,PromptSegment,PromptIcons,DirectoryLabel,HeaderContext,ZshPromptRenderer,ZshEscaping,StarshipPreset}.swift` | Modelo y render del prompt |
| `…/Domain/Config/{SmaltiConfig,CommandID,Keymap}.swift`, `…/Domain/Terminal/CloseGuard.swift` (`WindowSettings`), `…/Domain/Commands/CommandCatalog.swift`, `…/Domain/Help/HelpCatalog.swift` | Ajustes, ids, atajos, ⌘K y ayuda |
| `…/Domain/Input/InputProtocol.swift` | `context`, `prompt` y `promptstyle` |
| `…/Application/{AppearancePorts,ChangeAppearance,EditPrompt,RenderPrompt}.swift` | Puertos `AppearanceStore` y `PromptFacts` y casos de uso |
| `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/{InMemoryAppearanceStore,AppearanceStoreContract,FakePromptFacts,PromptFactsContract}.swift` | Fakes y contratos |
| `Packages/TOMLConfigAdapter/Sources/TOMLConfigAdapter/{ThemeReader,TOMLAppearanceStore,TOMLWriter,StarshipText}.swift` + `TOMLConfigStore.swift` | `theme.toml`, escritor y `starship.toml` |
| `Packages/ProjectContextAdapter/Sources/ProjectContextAdapter/{FilePromptFacts,GitStatusReader,RuntimeVersions}.swift` | `PromptFacts` |
| `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{GhosttyConfigText,SmaltiInputScript,SmaltiPromptScript,SmaltiZshEnv,GhosttyTerminalEngine}.swift` | Config por tema, script del prompt, carga independiente del input |
| `scripts/fonts/{icons/*.svg,outline-icons.swift,build-symbols-font.py,test_build_symbols_font.py}` + `App/Smalti/Fonts/SmaltiSymbols.ttf` | Fuente de iconos |
| `scripts/measure-gpu-idle.sh` | C6 |
| `App/Smalti/{SmaltiWindow,WindowGlass,WindowComposition,AppComposition,Theme+AppKit,AppFonts,PaneContainerView,PaneHeaderView,WorkspaceStripView,StatusBarView}.swift` | Capas de legibilidad, botones, tema en vivo, cabecera |
| `App/Smalti/Appearance/{AppearancePanelController,AppearancePanelView,ThemeCardView,SliderRow,ANSISwatchGrid,SegmentedRow}.swift` | Panel Apariencia |
| `App/Smalti/PromptStudio/{PromptStudioController,PromptStudioView,PromptPreviewView,TemplateCardView,ModuleListView,StarshipExportFlow}.swift` | Estudio de prompt |
| `App/Smalti/Input/InputCoordinator.swift` | Mensajes del prompt y envío espontáneo |
| `App/SmaltiUITests/{AppearanceTests,WindowButtonsTests,LegibilityTests,PromptStudioTests,PromptTests}.swift` | E2E |

---

## Bloque 1 · Verificaciones y dominio de apariencia

### Task 1: Verificar `font-codepoint-map` y medir la GPU (#5)

Puerta de la fase. Hay dos riesgos de la spec que se miden antes de construir encima:
- si una fuente registrada solo para el proceso no se alcanza por `font-codepoint-map`, se para y se elige el plan B con Simón;
- si la causa de #5 es el desenfoque privado, se para y se le lleva el dato.

**Files:**
- Test: `Packages/GhosttyAdapter/Tests/GhosttyAdapterTests/LibghosttyF5ApiTests.swift`
- Create: `scripts/measure-gpu-idle.sh`
- Modify: `App/Smalti/SmaltiWindow.swift` (argumento de lanzamiento solo en Debug, `-SmaltiGlassProbe none|noMask|noShadow|noBlur`, que quita una pieza cada vez)

**Interfaces:**
- Produces: hechos anotados en `progress.md`:
  - si `font-codepoint-map = U+E900-U+E91F=SmaltiSymbols` pinta el glifo de una fuente registrada con `CTFontManagerRegisterFontsForURL(.process)`;
  - la GPU media de cada variante (base, por defecto, `noMask`, `noShadow` y `noBlur`);
  - la causa elegida.

- [ ] **Step 1:** Prueba de integración `codepointMapReachesProcessFont`.
  - Arrange: registrar una fuente de prueba de un glifo (de `Tests/Fixtures`) para el proceso, configurar el map y `printf ''` en una surface real.
  - Assert: `ghostty_surface_read_text` devuelve U+E900 y el píxel de la celda no es el glifo de reemplazo, comparando la captura de la celda contra la misma con `font-codepoint-map` vacío.
- [ ] **Step 2:** Ejecutar `swift test --package-path Packages/GhosttyAdapter --filter LibghosttyF5ApiTests`. Si falla por la API, **se para** y se consulta el plan B a Simón.
- [ ] **Step 3:** `scripts/measure-gpu-idle.sh <n> [probe]`:
  - compila Debug "Smalti Dev" y lo lanza con `env -i` y `-SmaltiShellCommand "/bin/zsh -f"`;
  - espera 5 s y toma 10 muestras de 1 s de `ioreg -r -d 1 -c IOAccelerator` (`Device Utilization %`);
  - imprime `[k/n] ok <probe> <media>%` y cierra solo el proceso que lanzó.
  - Envuelto en `scripts/check-daily-untouched.sh`.
- [ ] **Step 4:** Medir la base (sin app), `none`, `noMask`, `noShadow` y `noBlur` con `kb-progress run bench`. Anotar la tabla en `progress.md`. Si solo `noBlur` baja a ≤ 10 %, **se para** y se lleva el dato a Simón.
- [ ] **Step 5:** Commit `test(ghostty): pin font-codepoint-map and measure idle GPU`.

### Task 2: Contraste y `LegibilityGuard`

**Files:**
- Create: `…/Domain/Theme/{ContrastRatio,LegibilityGuard,ProtectedSurfaces}.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Theme/{ContrastRatioTests,LegibilityGuardTests}.swift`

**Interfaces:**
- Produces:
  - `ContrastRatio.between(_ a: RGBAColor, _ b: RGBAColor) -> Double`: WCAG 2.x con los colores opacos;
  - `RGBAColor.composited(over: RGBAColor) -> RGBAColor` y `RGBAColor.mixed(toward: RGBAColor, amount: Double) -> RGBAColor`;
  - `enum Backdrop { case white, black }`;
  - `struct ProtectedSurface { let tint: RGBAColor; let colors: [RGBAColor] }`;
  - `LegibilityGuard.minimumOpacity(for: ProtectedSurface, over: RGBAColor) -> Double`: el mínimo en pasos de 0.01, o 1.0;
  - `LegibilityGuard.legible(_ color: RGBAColor, on ground: RGBAColor, toward anchor: RGBAColor) -> RGBAColor`: mezcla en pasos del 1 % hasta 4.5;
  - `static let minimumContrast = 4.5`.

- [ ] **Step 1:** Pruebas:
  - `whiteOnBlackIs21` y `sameColorIs1`;
  - `obsidianTextOnWorstPanelIs6_48`: `#d7dae0` sobre el panel al 34 % sobre el vidrio al 62 % sobre blanco, 6.48 ± 0.01;
  - `obsidianPanelNeeds65Percent`;
  - `nieblaPanelNeeds82Percent`;
  - `chromeNeeds89Percent`: `#8b919c` sobre el vidrio de Obsidiana sobre blanco da 0.89;
  - `ghostReaches4_5AfterMixing`;
  - `unreachableUserColorIsAdjusted`: ANSI `#15161e` como color de texto sale ≥ 4.5;
  - `adjustedColorsAreCounted`;
  - `alreadyLegibleColorIsUnchanged`.
- [ ] **Step 2:** Ejecutar `swift test --package-path Packages/SmaltiCore --filter "ContrastRatioTests|LegibilityGuardTests"`. Esperado: FAIL, porque los tipos no existen.
- [ ] **Step 3:** Implementar con las firmas de arriba. La luminancia es la de WCAG 2.x, linealizando sRGB con el umbral 0.04045.
- [ ] **Step 4:** Repetir el comando del paso 2. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): measure contrast and protect legibility`.

### Task 3: Catálogo de temas y `Theme.applying`

**Files:**
- Create: `…/Domain/Theme/{ThemeID,ThemeCatalog,Theme+Niebla,Theme+Amber,Theme+Forest,ANSIPalette}.swift`
- Modify: `…/Domain/Theme/{Theme,Theme+Obsidian}.swift`, `…/Domain/Config/SmaltiConfig.swift` (`AppearanceSettings`)
- Test: `…/Tests/SmaltiCoreTests/Theme/{ThemeCatalogTests,ANSIPaletteTests,ThemeApplyingTests}.swift`; actualizar `ObsidianThemeTests`

**Interfaces:**
- Consumes: T2.
- Produces:
  - `enum ThemeID: String, CaseIterable { case obsidiana, niebla, ambarNocturno = "ambar-nocturno", bosque }`, con `displayName` ("Obsidiana", "Niebla", "Ámbar nocturno", "Bosque") e `isLight`;
  - `ThemeCatalog.theme(_ id: ThemeID) -> Theme`;
  - `ANSIPalette(base: [RGBAColor], overrides: [Int: RGBAColor])` con `colors: [RGBAColor]` y `throws(ColorError)` si un índice está fuera de 0–15;
  - `AppearanceSettings` gana `theme: ThemeID`, `protectLegibility: Bool` y `ansiOverrides: [ThemeID: [Int: RGBAColor]]`; `accent` pasa a `RGBAColor?` (nil = el del tema);
  - `Theme.applying(_ appearance: AppearanceSettings) -> AppliedTheme`, donde `AppliedTheme` lleva el `theme` con los tokens finales, `effectiveOpacities: SurfaceOpacities` (panel, franja, cabecera, barra de estado, superposición) y `adjustedColorCount: Int`.

- [ ] **Step 1:** Pruebas:
  - `everyThemeProtectedColorPasses4_5OnOwnPanel`: los cuatro temas, colores protegidos según la pareja de fondo;
  - `themeColorsMatchMockupTable`: los hex de `THEMES` para Niebla, Ámbar y Bosque (texto, secundario, fantasma, acento, estados y 16 ANSI);
  - `overridesReplaceOnlyTheirIndex`; `overrideOfOtherThemeIsIgnored`; `indexSixteenIsRejected`;
  - `protectionRaisesPanelTo65InObsidian`;
  - `protectionKeepsHigherUserOpacity`: con 0.95 se queda en 0.95;
  - `withoutProtectionThemeIsExact` (C3: el fantasma de Obsidiana se queda en `#5f6672`);
  - `lowestOpacityStillProtected`: con 0.30, todos los colores protegidos llegan a ≥ 4.5;
  - `accentOverrideWinsOverTheme`.
- [ ] **Step 2:** Ejecutar `swift test --package-path Packages/SmaltiCore --filter "ThemeCatalogTests|ANSIPaletteTests|ThemeApplyingTests|ObsidianThemeTests"`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
  - Niebla usa bordes `rgba(0,0,0,…)` con las mismas opacidades que Obsidiana y la sombra al 0.18.
  - Los tokens que la tabla no da se derivan con la misma regla que Obsidiana.
  - Las superficies protegidas son las de `ProtectedSurfaces`: el panel con texto, secundario y ANSI; el chrome con texto y secundario; la superposición con el texto de la paleta.
- [ ] **Step 4:** Repetir el comando del paso 2 y la suite completa de `SmaltiCore`. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): four themes with per-theme ANSI and legibility`.

### Task 4: Ajustes, `PromptConfig`, comandos y atajos

**Files:**
- Create: `…/Domain/Prompt/PromptConfig.swift`
- Modify: `…/Domain/Config/{SmaltiConfig,CommandID,Keymap}.swift`, `…/Domain/Terminal/CloseGuard.swift` (`WindowSettings`), `…/Domain/Commands/CommandCatalog.swift`, `…/Domain/Help/HelpCatalog.swift`, `…/Domain/Commands/MenuModel.swift`
- Test: `…/Domain/{KeymapF5Tests,CommandCatalogF5Tests,PromptConfigTests}.swift`; actualizar `MenuModelTests`

**Interfaces:**
- Produces:
  - `enum WindowButtons: String { case hidden, hover, visible }` en `WindowSettings.buttons`;
  - `PromptConfig`:
    - campos `source: PromptSource (.smalti/.shell)`, `style: PromptStyleID (.clean/.pills/.symbolOnly)`, `layout: PromptLayout (.twoLines/.oneLine)`, `modules: [PromptModuleID]`, `icons: PromptIcons (.thin/.nerd/.none)` y `symbol: PromptSymbol (› ❯ λ $)`;
    - `static let standard`;
    - `template: PromptTemplate?`: la plantilla que coincide con la combinación;
    - `applying(_ template: PromptTemplate) -> PromptConfig`;
  - `PromptModuleID: String` con los ocho ids de Global Constraints;
  - `SmaltiConfig.prompt`, fuera del inicializador como `observatory`;
  - `CommandID.appearanceOpen`, `.promptStudio`, `.themeOpen`, `.themeNext`, `.ansiReset`, `.promptApply`, `.promptExport` y `.legibilityToggle`;
  - en el menú Smalti: "Apariencia…" y "Estudio de prompt…".

- [ ] **Step 1:** Pruebas:
  - `commaOpensAppearance`; `shiftCmdPOpensStudio`; `optionCmdCommaOpensConfig`;
  - `newShortcutsNeverUseOptionAlone`;
  - `everyNewCommandIsInPaletteAndHelp`;
  - `templatesMapToStyleAndLayout`: la tabla de la spec;
  - `changingLayoutMovesTemplateMark`: Línea limpia con `.oneLine` pasa a ser Una sola línea;
  - `symbolOnlyIgnoresLayout`;
  - `standardPromptMatchesBoard`: los seis módulos activos, en el orden del tablero;
  - `menuSmaltiListsAppearanceAndStudio`.
- [ ] **Step 2:** Ejecutar las pruebas (FAIL), implementar y repetirlas (PASS). La guarda `CommandCoverageGuardTests` debe seguir en verde: los comandos nuevos sin acción todavía se registran como "pendientes de la app" en la guarda, y T16 y T18 los quitan de ahí.
- [ ] **Step 3:** Commit `feat(core): F5 settings, prompt config and shortcuts`.

**Cierre del bloque 1:** revisión del diff del bloque por un revisor nuevo, mutación con `--changed-since develop`, y corrección de los hallazgos importantes antes del bloque 2.

---

## Bloque 2 · Dominio del prompt

### Task 5: Módulos, estilos y contexto

**Files:**
- Create: `…/Domain/Prompt/{PromptModule,PromptModules,PromptStyle,PromptStyles,PromptContext,PromptSegment,PromptIcons,DirectoryLabel,HeaderContext}.swift`
- Test: `…/Tests/SmaltiCoreTests/Prompt/{PromptModulesTests,DirectoryLabelTests,PromptStylesTests,HeaderContextTests}.swift`

**Interfaces:**
- Produces:
  - `PromptContext`: `directory`, `home`, `repoRoot: String?`, `branch: String?`, `changes: GitChanges?` (`modified`, `staged`), `runtime: RuntimeVersion?` (`kind`, `version`), `lastExit: Int`, `duration: Duration?`, `now: Date`, `agents: WaitingAgents` (`waiting`, `failed`, `names`), `awsProfile: String?` y `kubeContext: String?`;
  - `protocol PromptModule { var id: PromptModuleID { get }; func segment(in: PromptContext) -> PromptSegment? }`, con un tipo por id: `DirectoryModule`, `GitBranchModule`, `GitStatusModule`, `RuntimeModule`, `DurationModule`, `AgentsModule`, `TimeModule` y `CloudModule`;
  - `PromptModules.module(for: PromptModuleID) -> any PromptModule`: un diccionario, no un `switch`;
  - `PromptSegment`: `icon: PromptIcon?`, `text: String`, `color: SegmentColor` (rol del tema: `accent`, `ansi(Int)`, `secondary`, `waiting` o `failed`) e `isLocal: Bool` (lo pinta zsh al instante);
  - `protocol PromptStyle { func lines(_ segments: [PromptSegment], symbol: SymbolSegment, layout: PromptLayout) -> [[StyledRun]] }`, implementado por `CleanStyle`, `PillsStyle` y `SymbolOnlyStyle`;
  - `PromptIcons.codepoint(for: PromptIcon, set: PromptIcons) -> Character?`: `thin` en U+E900+, `nerd` con los códigos de Nerd Font y `none` sin icono;
  - `HeaderContext.text(for: [PromptSegment], maxWidth: Int) -> String`.

- [ ] **Step 1:** Pruebas:
  - `outsideRepoShowsLastTwoLevels` (`~/Downloads`; `/usr/local/bin` → `local/bin`);
  - `insideRepoShowsFromRootWithName` (`solen/apps/api`);
  - `homeIsTilde`;
  - `gitStatusShowsModifiedAndStaged` (`●2 +1`); `cleanRepoHidesGitStatus`;
  - `durationBelowTwoSecondsHidden`; `durationShowsOneDecimal` (`4.2s`);
  - `agentsWaitingShowsName` (`claude te espera`); `twoWaitingShowsCount` (`2 te esperan`); `noWaitingHidesModule`;
  - `cloudShowsProfileAndContext`;
  - `exitNonZeroColorsSymbolAndAddsExitText` (`exit 1` en secundario);
  - `pillsMixBackgroundAt16Percent` (fondo opaco = color al 16 % sobre el panel);
  - `symbolOnlyLineHasOnlySymbol`;
  - `headerContextTrimsDirectoryFromLeft`;
  - `moduleOrderFollowsConfig`.
- [ ] **Step 2:** Ejecutar las pruebas (FAIL), implementar y repetirlas (PASS).
- [ ] **Step 3:** Commit `feat(core): prompt modules, styles and header context`.

### Task 6: `ZshPromptRenderer` y escapado

**Files:**
- Create: `…/Domain/Prompt/{ZshPromptRenderer,ZshEscaping}.swift`
- Test: `…/Tests/SmaltiCoreTests/Prompt/{ZshPromptRendererTests,ZshEscapingTests}.swift`, con dorados en `Tests/SmaltiCoreTests/Prompt/Golden/*.zsh-prompt`

**Interfaces:**
- Consumes: T3 (colores protegidos del `AppliedTheme`) y T5.
- Produces:
  - `ZshPromptRenderer.render(_ config: PromptConfig, context: PromptContext, theme: AppliedTheme) -> RenderedPrompt`;
  - `RenderedPrompt`: `immediate: String`, `full: String` y `values: [String: String]`. Los valores son el texto de fuera (directorio, rama, nombres), que zsh asigna a variables `_smalti_p_<n>`; las cadenas solo las referencian como `${_smalti_p_<n>}`.
- **Escapado:**
  - en el texto de fuera, `%` pasa a `%%`, y los saltos de línea y tabs se cambian por `␤` y un espacio;
  - las cadenas usan `%F{#rrggbb}…%f` y `%K{…}…%k`; el exit, `%(?..)`; la duración, `${_smalti_duration}`.

- [ ] **Step 1:** Pruebas:
  - `cleanTwoLinesMatchesGolden`, `oneLineMatchesGolden`, `pillsMatchesGolden` y `symbolOnlyMatchesGolden`, con el contexto de "Proyecto Node con git" del tablero;
  - `immediateHasOnlyLocalSegments`;
  - `branchWithSubstitutionStaysLiteral`: `$(touch pwned)%F{red}` va a `values` con `%%`, y la cadena solo dice `${_smalti_p_1}`;
  - `percentInDirectoryIsEscaped`; `newlineInNameIsReplaced`;
  - `protectedColorsAreUsed`: con protección, el color del secundario es el ajustado;
  - `messageStaysUnder2000Bytes`: con un directorio de 1500 caracteres, el texto se recorta por la izquierda.
- [ ] **Step 2:** Ejecutar las pruebas (FAIL), implementar y repetirlas (PASS).
- [ ] **Step 3:** Commit `feat(core): render the zsh prompt with escaped values`.

### Task 7: Canal, `RenderPrompt` y `PromptFacts`

**Files:**
- Create: `…/Application/{AppearancePorts,RenderPrompt}.swift`, `SmaltiCoreTestSupport/{FakePromptFacts,PromptFactsContract}.swift`
- Modify: `…/Domain/Input/InputProtocol.swift`
- Test: `…/Input/InputProtocolTests.swift` (casos nuevos), `…/Application/RenderPromptTests.swift`, `…/Prompt/FakePromptFactsContractTests.swift`

**Interfaces:**
- Produces:
  - `ShellMessage.context(seq: Int, ShellContext)`, donde `ShellContext` lleva `pwd`, `exit`, `durationMilliseconds`, `awsProfile`, `kubeconfig` y `runtimePaths: [RuntimeKind: String]`. En el cable: `context <seq> <pwd> <exit> <ms> <aws> <kubeconfig> <node=…;bun=…;python=…;go=…>`;
  - `SmaltiMessage.prompt(seq: Int, RenderedPrompt)` y `.promptStyle(RenderedPrompt, ghost: RGBAColor)`. En el cable: `prompt <seq> <inmediata> <completa> <valores k=v separados por \x1f>` y `promptstyle <inmediata> <#ghost>`;
  - `protocol PromptFacts: Sendable { func facts(for query: PromptQuery) async -> PromptFactsResult }`. `PromptQuery` lleva `directory` y `runtimePaths`; `PromptFactsResult`, `repoRoot`, `branch`, `changes` y `runtime`. Cada campo es opcional: sin dato, el módulo no sale;
  - `RenderPrompt` (`@MainActor`):
    - `handle(_ context: ShellContext, seq: Int, pane: PaneID) async -> SmaltiMessage`;
    - `agentsChanged(in workspace: WorkspaceID) -> [(PaneID, SmaltiMessage)]`: reenvía con el último `seq` de `context` de cada shell de ese workspace que sigue en el prompt;
    - `commandStarted(pane:)`: olvida el `seq` cuando llega `exec`.

- [ ] **Step 1:** Pruebas:
  - `contextRoundTrips` y `promptRoundTrips` (`encode`/`decode`);
  - `fieldsWithTabAreEscaped`;
  - `renderUsesFactsAndLocalContext`;
  - `missingFactsDropModulesNotPrompt`;
  - `spontaneousPromptUsesLastContextSeq`; `noSpontaneousPromptAfterExec`; `onlyPanesOfSameWorkspaceAreNotified`;
  - `shellSourceSendsNothing`;
  - el contrato `PromptFactsContract`: `unknownDirectoryHasNoRepo` y `factsNeverThrow`.
- [ ] **Step 2:** Ejecutar las pruebas (FAIL), implementar y repetirlas (PASS).
- [ ] **Step 3:** Commit `feat(core): prompt channel messages and RenderPrompt`.

### Task 8: `AppearanceStore`, `ChangeAppearance`, `EditPrompt` y `StarshipPreset`

**Files:**
- Create: `…/Application/{ChangeAppearance,EditPrompt}.swift`, `…/Domain/Prompt/StarshipPreset.swift`, `SmaltiCoreTestSupport/{InMemoryAppearanceStore,AppearanceStoreContract}.swift`
- Modify: `…/Application/AppearancePorts.swift`
- Test: `…/Application/{ChangeAppearanceTests,EditPromptTests}.swift`, `…/Prompt/StarshipPresetTests.swift`, `…/Config/InMemoryAppearanceStoreContractTests.swift`

**Interfaces:**
- Produces:
  - `protocol AppearanceStore: AnyObject { @MainActor func save(_ document: AppearanceDocument) throws(ConfigError) }`. `AppearanceDocument` lleva `appearance`, `buttons` y `prompt`;
  - `ChangeAppearance.apply(_ change: (inout AppearanceDocument) -> Void) -> AppliedTheme`: aplica al instante y programa el guardado a 300 ms con un `Scheduler` inyectado;
  - `ChangeAppearance.selectTheme(_ id: ThemeID)`: quita el `accent` del documento;
  - `EditPrompt`:
    - un `draft: PromptConfig`;
    - `preview(_ situation: PreviewSituation) -> RenderedPrompt`, con las tres situaciones del tablero como `PromptContext` fijos (`.normalFolder`, `.nodeProject` y `.afterErrorWithAgent`);
    - `apply()`, que guarda y devuelve el `promptstyle` para todos los shells;
    - `move(_ id: PromptModuleID, by offset: Int)` y `toggle(_ id: PromptModuleID)`;
  - `StarshipPreset.make(from: PromptConfig, theme: AppliedTheme) -> StarshipPreset`, el modelo de tablas y claves que T9 serializa.

- [ ] **Step 1:** Pruebas:
  - `sliderDragSavesOnceAfter300ms`;
  - `selectingThemeClearsAccent`;
  - `applyWithoutChangesDoesNotSave`;
  - `draftDoesNotTouchLivePromptUntilApply`;
  - `moveModuleUpAndDown`; `moveFirstUpIsNoop`;
  - `previewSituationsMatchBoard` (`~/Downloads`, `solen/apps/api` con `feat/reminders ●2 +1 22.11`, y `rizaria/web main 4.2s ● claude te espera` con `exit 1`);
  - `starshipMapsEveryModule`: `directory.truncation_length = 2`, `truncate_to_repo = true`, `cmd_duration.min_time = 2000` y `character` con el símbolo;
  - `starshipThinIconsExportWithoutSymbols`; `starshipAgentsBecomesComment`;
  - el contrato `AppearanceStoreContract`: `savedDocumentIsReadBack`.
- [ ] **Step 2:** Ejecutar las pruebas (FAIL), implementar y repetirlas (PASS).
- [ ] **Step 3:** Commit `feat(core): appearance store, prompt editing and starship preset`.

**Cierre del bloque 2:** revisión del diff del bloque, mutación incremental y correcciones.

---

## Bloque 3 · Adaptadores

### Task 9: `TOMLConfigAdapter`: `theme.toml`, escritor y `starship.toml`

**Files:**
- Create: `Packages/TOMLConfigAdapter/Sources/TOMLConfigAdapter/{ThemeReader,TOMLAppearanceStore,TOMLWriter,StarshipText}.swift`
- Modify: `TOMLConfigStore.swift`, que pasa a recibir `init(config: URL, theme: URL)`; `AppComposition` lo usa en T14
- Test: `Tests/TOMLConfigAdapterTests/{ThemeReaderTests,TOMLAppearanceStoreTests,StarshipTextTests,TOMLAppearanceStoreContractTests}.swift` y `Fixtures/{theme-full.toml,starship-*.toml}`

**Interfaces:**
- Consumes: T3, T4 y T8.
- Produces:
  - `TOMLConfigStore.reload()`: mezcla clave a clave con el orden de precedencia defaults < `config.toml` < `theme.toml`. Además, `ConfigReload.warnings` lleva `.duplicatedKeys([String])`;
  - `TOMLAppearanceStore(file: URL)`, que implementa `AppearanceStore`:
    - escribe el archivo entero, con la cabecera de comentario de la spec y en el orden del bloque de la spec;
    - lo hace de forma atómica (archivo temporal más `replaceItemAt`);
    - si la fecha de modificación cambió desde la última lectura, primero relee y aplica el documento encima;
  - `StarshipText.render(_ preset: StarshipPreset) -> String`.

- [ ] **Step 1:** Pruebas:
  - `roundTripEveryEnumAndRangeEdge`: `parse(write(x)) == x` para todos los temas, botones, estilos, disposiciones, iconos y símbolos, y para las opacidades 0.30 y 0.95 y el desenfoque 0 y 48;
  - `themeWinsOverConfigPerKey`;
  - `duplicatedKeysAreWarned`;
  - `confirmCloseStaysInConfig`;
  - `invalidAnsiIndexNamesLine` (`theme.toml`, línea y clave `appearance.ansi.bosque.16`);
  - `unknownModuleIsRejected`;
  - `accentIsPreservedOnRewrite`;
  - `saveMergesExternalEditFirst`;
  - `writeIsAtomic`: un lector concurrente nunca ve un archivo a medias;
  - `starshipMatchesGolden` para cada plantilla; `starshipIsValidTOML`, releído con el parser;
  - el contrato compartido con T8.
- [ ] **Step 2:** Ejecutar `swift test --package-path Packages/TOMLConfigAdapter`: FAIL, implementar y PASS.
- [ ] **Step 3:** Commit `feat(config): read and write theme.toml and export starship.toml`.

### Task 10: `ProjectContextAdapter`: `PromptFacts`

**Files:**
- Create: `Packages/ProjectContextAdapter/Sources/ProjectContextAdapter/{FilePromptFacts,GitStatusReader,RuntimeVersions}.swift`
- Test: `Tests/ProjectContextAdapterTests/{FilePromptFactsTests,FilePromptFactsContractTests}.swift`

**Interfaces:**
- Consumes: T7 (`PromptFacts`, `PromptQuery`) y la rama de `FileProjectContext`.
- Produces: `FilePromptFacts(runner: ProcessRunner, clock:)`, con estas reglas:
  - **raíz del repo:** se sube buscando `.git`, sin procesos;
  - **cambios:** `git status --porcelain=v2 --untracked-files=no`, con 300 ms como máximo. Hay caché por raíz con la firma (tamaño y fecha) de `.git/index` y `.git/HEAD`;
  - **runtime:** se elige por los archivos del proyecto, en orden Node → Bun → Python → Go. La versión sale de `<ruta> --version`, con caché por ruta y fecha de modificación.

- [ ] **Step 1:** Pruebas, con un repo temporal creado en la prueba:
  - `countsModifiedAndStaged` (2 y 1);
  - `slowGitDropsChanges` (un `ProcessRunner` falso de 400 ms);
  - `indexUnchangedUsesCache`;
  - `nodeProjectReportsNodeVersion` (un ejecutable falso que imprime `v22.11.0` → `22.11`);
  - `bunLockWinsOverPackageJson`;
  - `runtimeCachedUntilBinaryChanges`;
  - `noGitDirectoryHasNoRepo`;
  - el contrato `PromptFactsContract`.
- [ ] **Step 2:** Ejecutar `swift test --package-path Packages/ProjectContextAdapter`: FAIL, implementar y PASS.
- [ ] **Step 3:** Commit `feat(context): git changes, repo root and runtime versions for the prompt`.

### Task 11: `GhosttyAdapter`: config por tema y script del prompt

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/SmaltiPromptScript.swift`
- Modify: `GhosttyConfigText.swift` (paleta, fondo y primer plano del tema, `font-codepoint-map = U+E900-U+E91F=SmaltiSymbols`), `SmaltiZshEnv.swift` y `GhosttyTerminalEngine.swift` (cargar el script si `[input] enabled` o `source = smalti`), `SmaltiInputScript.swift` (el fantasma toma `_smalti_ghost_color`, que actualiza `promptstyle`)
- Test: `Tests/GhosttyAdapterTests/{GhosttyConfigTextF5Tests,PromptScriptIntegrationTests}.swift`

**Interfaces:**
- Consumes: T6 y T7 (formato de los mensajes).
- Produces, en el script de zsh:
  - `_smalti_prompt_precmd` se pone **la última** de `precmd_functions` en cada `precmd`. Asigna `_smalti_duration`, manda `context` y aplica la inmediata guardada;
  - el manejador de `prompt` comprueba el `seq`, asigna `_smalti_p_*` con `typeset -g`, pone `PROMPT` y `RPROMPT` y hace `zle reset-prompt` sin tocar `BUFFER`, `POSTDISPLAY` ni `region_highlight`;
  - el manejador de `promptstyle` actualiza la inmediata y `_smalti_ghost_color`;
  - con `source = shell` no hay asignaciones;
  - el input apagado no instala ni los widgets ni la escritura de `line`.

- [ ] **Step 1:** Pruebas de integración con zsh real (`zsh -d`, ZDOTDIR temporal) y un servidor de socket de prueba:
  - `promptShowsImmediateThenFull`;
  - `silentServerDoesNotDelayPrompt` (C8: 20 prompts, ± 5 ms frente a sin canal);
  - `closedChannelKeepsLastImmediatePrompt`;
  - `hostileBranchDoesNotRunWithPromptSubst` (C9: con `setopt prompt_subst` y sin él, no aparece `pwned`);
  - `shellSourceKeepsUserPrompt` (C10);
  - `smaltiPromptWinsOverZshrcAndStarshipLikeHook` (C10: un hook de `precmd` que asigna `PROMPT`);
  - `staleSpontaneousPromptIsDropped`; `spontaneousPromptKeepsBuffer`;
  - `promptWorksWithInputDisabled`; `inputDisabledInstallsNoWidgets`;
  - `ghostColorChangesLive`;
  - `configTextCarriesThemePaletteAndCodepointMap`.
- [ ] **Step 2:** Ejecutar `swift test --package-path Packages/GhosttyAdapter`: FAIL, implementar y PASS.
- [ ] **Step 3:** Commit `feat(ghostty): zsh prompt from Smalti and theme-driven engine config`.

### Task 12: Fuente `SmaltiSymbols`

**Files:**
- Create:
  - `scripts/fonts/icons/{folder,branch,node,bun,python,go,clock,kubernetes,cloud,agent}.svg`: trazo de 1.4 px en una rejilla de 16. La carpeta, la rama y el hexágono se copian del tablero;
  - `scripts/fonts/outline-icons.swift`: con CoreGraphics, `copy(strokingWithWidth:)` convierte los trazos en contornos y los saca en JSON;
  - `scripts/fonts/build-symbols-font.py`: fontTools, glifos monoespacio con el avance de JetBrains Mono a 1000 UPM, U+E900 en adelante y en el orden de la lista;
  - `scripts/fonts/test_build_symbols_font.py`;
  - `App/Smalti/Fonts/SmaltiSymbols.ttf`, versionado;
  - `docs/specs/F5-assets/icons-sheet.png`, la lámina para aprobar en el PR.
- Modify: `App/Smalti/AppFonts.swift` (registra `SmaltiSymbols`) y `…/Domain/Prompt/PromptIcons.swift` (la tabla de códigos debe coincidir).

- [ ] **Step 1:** Pruebas:
  - `test_every_icon_has_codepoint_in_range`;
  - `test_advance_matches_monospace_cell`;
  - `test_font_names_family_SmaltiSymbols`;
  - en Swift, `PromptIconsTests.codepointsMatchFontOrder`, que lee la lista de `scripts/fonts/icons.txt`.
- [ ] **Step 2:** Generar con `swift scripts/fonts/outline-icons.swift scripts/fonts/icons > build/icons.json && python3 scripts/fonts/build-symbols-font.py build/icons.json App/Smalti/Fonts/SmaltiSymbols.ttf`. Después, `cd scripts/fonts && python3 -m unittest test_build_symbols_font`: PASS.
- [ ] **Step 3:** Generar la lámina de iconos con Chrome headless y adjuntarla al PR.
- [ ] **Step 4:** Commit `feat(prompt): SmaltiSymbols thin-stroke icon font`.

**Cierre del bloque 3:** revisión del diff del bloque, suites completas de los paquetes tocados y correcciones.

---

## Bloque 4 · App: vidrio, temas y ventana

### Task 13: GPU en reposo (#5)

**Files:** los que señale T1, previsiblemente `App/Smalti/{SmaltiWindow,WindowGlass}.swift`. Hay que quitar `-SmaltiGlassProbe` si no se queda como herramienta de Debug.

- [ ] **Step 1:** Aplicar la corrección de la causa medida en T1, por ejemplo una forma de esquinas sin `masksToBounds` sobre las superficies Metal, o la sombra calculada una sola vez, según el dato.
- [ ] **Step 2:** `kb-progress run bench -- scripts/check-daily-untouched.sh scripts/measure-gpu-idle.sh 5`: ≤ 10 % con la config por defecto (C6). Repetir la lista de render A9–A11 de F0 y comparar las capturas (C16 parcial).
- [ ] **Step 3:** Commit `fix(window): cut idle GPU of the glass window (#5)`.

### Task 14: Tema en vivo y capas de legibilidad

**Files:** `App/Smalti/{AppComposition,WindowComposition,SmaltiWindow,Theme+AppKit,PaneContainerView,WorkspaceStripView,StatusBarView,PaneHeaderView,OverlayBox}.swift`

**Interfaces:**
- Consumes: el `AppliedTheme` de T3, `ChangeAppearance` de T8 y `TOMLConfigStore(config:theme:)` de T9.
- Produces:
  - `AppComposition.applyAppearance(_ applied: AppliedTheme)`, que llega a todas las ventanas, paneles, motores y superposiciones;
  - la franja, la barra de estado y las cabeceras pintan un fondo con `effectiveOpacities` cuando la protección lo pide. Los huecos conservan el vidrio;
  - "Reducir movimiento" quita los fundidos (`NSWorkspace.accessibilityDisplayShouldReduceMotion`).

- [ ] **Step 1:** XCUITest en `LegibilityTests`:
  - `protectionRaisesPanelOpacityOverWhite` (C2): la app delante de una ventana blanca de prueba; se muestrea el píxel de fondo del panel y de la franja, y se comprueba que cada token protegido da ≥ 4.5 contra él;
  - `themeChangeUpdatesTwoWindowsWithoutRelaunch` (C12): el PID del shell no cambia y el color de fondo de los dos paneles sí.
- [ ] **Step 2:** Correr las dos pruebas (FAIL), implementar y volver a correrlas (PASS).
- [ ] **Step 3:** Commit `feat(app): live themes and legibility layers`.

### Task 15: Botones de ventana

**Files:** `App/Smalti/{SmaltiWindow,WorkspaceStripView}.swift`, `App/SmaltiUITests/WindowButtonsTests.swift`

- [ ] **Step 1:** XCUITest:
  - `hiddenShowsNoButtons`;
  - `visibleShowsThreeAndShiftsPills72`;
  - `hoverRevealsOnStripAndHidesOutside`;
  - `closeButtonAsksWithBusyPane` (`sleep 100`);
  - `zoomButtonZooms`;
  - `minimizeButtonMinimizes`;
  - `reduceMotionSkipsFade` (C15: con `-SmaltiReduceMotion YES`, el argumento de prueba que sustituye a la preferencia del sistema, los botones aparecen sin fundido).
- [ ] **Step 2:** Implementar:
  - `.closable` en el `styleMask`, con `windowShouldClose` → `CloseConfirmation`;
  - un área de seguimiento en la franja para `hover`;
  - el fundido de 150 ms, o ninguno con "Reducir movimiento".
- [ ] **Step 3:** Correr las pruebas (PASS) y hacer commit `feat(window): window buttons hidden, on hover or visible`.

### Task 16: Panel Apariencia

**Files:** `App/Smalti/Appearance/*` (ver el mapa), `WindowComposition.swift` (la zona de paneles se encoge), `App/SmaltiUITests/AppearanceTests.swift`

**Interfaces:**
- Consumes: `ChangeAppearance` (T8), los comandos de T4 y el `AppliedTheme` (`adjustedColorCount` y `effectiveOpacities`).
- Produces: una superposición del ancho del tablero, con:
  - tarjetas de tema;
  - deslizadores de opacidad y desenfoque, con la etiqueta "62 % · 65 % bajo el texto" cuando la protección sube;
  - la casilla "Proteger legibilidad";
  - la rejilla ANSI con `NSColorPanel`;
  - el selector de botones;
  - fuente, espacio y radio;
  - "Ajustados por legibilidad: N colores";
  - la ruta abreviada de `theme.toml`.

  Los comandos `appearance.open`, `theme.open`, `theme.next`, `ansi.reset` y `legibility.toggle` quedan conectados.

- [ ] **Step 1:** XCUITest:
  - `everyControlWritesThemeToml` (C1, UI → TOML);
  - `handEditShowsInPanelAfterReload` (C1, TOML → UI);
  - `configTomlHashUnchanged` (C14);
  - `duplicatedKeyWarningShown` (C14);
  - `commaOpensAndEscCloses`; `optionCommaOpensConfigToml` (C13; en la prueba, `NSWorkspace` abre a través de un `URLOpener` falso, como en F4.5);
  - `paneAreaShrinksAndStaysLive`;
  - `sliderMovesWithArrowsAndShift`;
  - `ansiEditOnlyAffectsCurrentTheme`;
  - `panelMatchesBoardCapture`: la captura se guarda para C4.
- [ ] **Step 2:** Correr las pruebas (FAIL), implementar y volver a correrlas (PASS). Quitar los comandos de la lista de pendientes de la guarda.
- [ ] **Step 3:** Commit `feat(app): appearance panel`.

**Cierre del bloque 4:** revisión del diff del bloque; regresión de las clases que toca el bloque (`MainWindowTests`, `WindowTests`, `CloseConfirmationTests`, `MenuTests` y `HelpTests`) en una sola corrida; correcciones.

---

## Bloque 5 · App: prompt

### Task 17: Prompt conectado y contexto en la cabecera

**Files:** `App/Smalti/Input/InputCoordinator.swift`, `App/Smalti/{AppComposition,PaneHeaderView,TilingController}.swift`

**Interfaces:**
- Consumes: `RenderPrompt` (T7), `FilePromptFacts` (T10), el estado de los agentes (F2) y `EditPrompt.apply()` (T8).
- Produces:
  - `context` → `RenderPrompt.handle` → `prompt`;
  - los cambios de estado de los agentes → `agentsChanged(in:)`;
  - `exec` → `commandStarted`;
  - un cambio del tema o del prompt → `promptstyle` a todos los shells;
  - con `SymbolOnlyStyle`, la cabecera del panel muestra `HeaderContext.text` en lugar de la ruta.

- [ ] **Step 1:** XCUITest en `PromptTests`, con `isolatedSmaltiWithIntegration()`:
  - `defaultPromptShowsDirectoryAndSymbol` (C7);
  - `gitRepoShowsBranchAndChanges`, con un repo temporal (C7);
  - `waitingAgentAppearsWithoutKeypress` (C10b: un evento de hooks grabado pone otro panel del workspace en "te espera");
  - `symbolOnlyMovesContextToHeader`;
  - `themeChangeRecolorsPromptLive` (C12).
  - Guarda (C17), en `DiagnosticsAdapter`: `noLoggerPublishesPromptText` amplía la guarda de F4.5 al prompt, las rutas y los nombres de rama.
- [ ] **Step 2:** Correr las pruebas (FAIL), implementar y volver a correrlas (PASS).
- [ ] **Step 3:** Commit `feat(app): wire the Smalti prompt and header context`.

### Task 18: Estudio de prompt

**Files:** `App/Smalti/PromptStudio/*`, `App/SmaltiUITests/PromptStudioTests.swift`

**Interfaces:**
- Consumes: `EditPrompt` (T8), `StarshipText` (T9) y `PromptIcons` (T5).
- Produces:
  - una superposición del tablero con:
    - tres vistas previas, pintadas con un `NSTextView` monoespaciado que usa los mismos colores y la fuente `SmaltiSymbols`;
    - las tarjetas de plantilla;
    - la lista de módulos, con arrastre, ⌘↑ y ⌘↓ y casillas;
    - el selector de iconos, con "Nerd Font" desactivado y "No hay una Nerd Font instalada" si `CTFontManager` no encuentra ninguna;
    - el símbolo, la disposición y el interruptor "Prompt del shell";
    - "Aplicar a todos los paneles" y "Exportar como starship.toml" (`NSSavePanel` en `~/.config` con confirmación al sobrescribir);
  - conectados los comandos `prompt.studio`, `prompt.apply` y `prompt.export`.

- [ ] **Step 1:** XCUITest:
  - `everyStudioControlWritesThemeToml` (C1);
  - `templateCardFollowsLayout`;
  - `dragAndKeyboardReorderModules`;
  - `applyUpdatesOpenShells` (C12);
  - `draftDoesNotChangeShellsBeforeApply`;
  - `exportWritesStarshipToTempDestination` (C11: el destino se pasa con `-SmaltiExportDirectory`);
  - `nerdFontOptionDisabledWithoutNerdFont`;
  - `shiftCmdPOpensStudio` (C13);
  - `studioMatchesBoardCapture` (C4).
- [ ] **Step 2:** Correr las pruebas (FAIL), implementar y volver a correrlas (PASS). Quitar los comandos de la lista de pendientes de la guarda.
- [ ] **Step 3:** Commit `feat(app): prompt studio`.

### Task 19: Capturas y comparación con los tableros

**Files:** `App/SmaltiUITests/DesignCaptureTests.swift`, `docs/specs/F5-assets/f5-*.png` y `c4-*-side-by-side.png`

- [ ] **Step 1:** Capturas de:
  - los cuatro temas;
  - Apariencia;
  - el Estudio;
  - los botones en sus tres modos;
  - "Solo símbolo";
  - la protección sobre blanco.
- [ ] **Step 2:** Superponerlas al 50 % sobre el tablero o la maqueta renderizados (C4, como C16 de F4.5) y anotar cada diferencia con su porqué para el PR.
- [ ] **Step 3:** Repetir A9–A11 de F0 con cada tema (C16).
- [ ] **Step 4:** Commit `docs(f5): design captures and side-by-side comparisons`.

**Cierre del bloque 5:** revisión del diff del bloque; regresión en una sola corrida de las clases de F4 que toca el canal (`InputTests`, `InputIsolationTests` y `CrossWindowInputTests`) y de las nuevas; correcciones.

---

## Bloque 6 · Cierre

### Task 20: Checklist, revisión final, mutación, PR y despliegue

**Files:**
- Create: `docs/specs/F5-checklist.md` (C1–C19 con la evidencia de cada uno)
- Modify: `CLAUDE.md` (puertos `AppearanceStore` y `PromptFacts`, `theme.toml`, `measure-gpu-idle.sh`, `scripts/fonts`), `progress.md` y `MARKETING_VERSION = 0.5.0`

- [ ] **Step 1:** Suites completas de los paquetes tocados y `swift format lint --strict`, con su código de salida real. XCUITest de todo lo que cambió en la fase, en una sola corrida con `kb-progress` y `check-daily-untouched.sh`.
- [ ] **Step 2:** Revisión de la rama completa por un revisor nuevo con el modelo más capaz, y una sola tanda de correcciones, cada una RED→GREEN.
- [ ] **Step 3:** `"$KB_ROOT/_system/bin/kb-progress" run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore`: 80 % o más. Los sobrevivientes se matan con pruebas nuevas.
- [ ] **Step 4:** Checklist, documentos y commit `docs(f5): record the F5 close`. Medir C6 por última vez.
- [ ] **Step 5:** `git push -u origin feature/f5-apariencia-prompt` y PR a `develop`, con las capturas junto a los tableros y la lámina de iconos. Después, PR `develop` → `main`. Simón aprueba y hace merge de los dos.
- [ ] **Step 6 (despliegue, tras el merge a `main` y con el visto bueno de Simón sobre el momento, porque cierra su Smalti diario):**
  - build Release;
  - `Smalti.app` → `Smalti.app.old`;
  - copiar el nuevo a `/Applications`;
  - abrirlo con `env -i …`;
  - comprobar la versión 0.5.0 en Acerca de.

# F5 · Apariencia y prompt — verificación

2026-11-24 · Rama `feature/f5-apariencia-prompt` · Spec `docs/specs/F5-apariencia-prompt.md` (con las enmiendas 1 y 2) · Plan `docs/plans/F5-apariencia-prompt.md`

Todas las suites de interfaz corrieron con `isolatedSmalti()` (`/bin/zsh -f`) o `isolatedSmaltiWithIntegration()` (`/bin/zsh -d` con ZDOTDIR temporal; `smaltiPrompt: true` en las del prompt), con `config.toml`, `theme.toml` y el destino de la exportación temporales, bajo `scripts/check-daily-untouched.sh` ("daily Smalti still running" y "daily state untouched" en cada corrida) y con el portapapeles guardado y restaurado. Cierre: XCUITest completo en una sola corrida, **191/191** en verde (19 omitidas a propósito: capturas y latencias a demanda); suites unitarias de los 11 paquetes y `swift format lint --strict` en verde.

## Criterios de aceptación

| # | Resultado | Evidencia |
| --- | --- | --- |
| C1 | ✅ | Ida y vuelta en el dominio y el adaptador: `TOMLAppearanceStoreTests` (incluidos `saveMergesExternalEditFirst` y `secondSaveKeepsTheHandEdit`), `ChangeAppearanceTests` (la edición a mano que se fusiona al guardar pasa al documento). UI → TOML: `AppearanceTests.testEveryControlWritesThemeToml`, `PromptStudioTests.testEveryStudioControlWritesThemeToml`. TOML → UI: `AppearanceTests.testHandEditShowsInPanelAfterReload`; una recarga que falla no deshace lo editado (`testFailedReloadKeepsPanelEdits`) y salir a los 300 ms lo guarda (`testQuitRightAfterAChangeSavesIt`) |
| C2 | ✅ | `LegibilityC2Tests` (4 temas × 6 opacidades), `ThemeApplyingTests`, `PromptLegibilityTests` (cada pieza del prompt, también las píldoras y los colores de agente, ≥ 4.5 en los cuatro temas); en pantalla, `LegibilityTests.testProtectionRaisesPanelOpacityOverWhite` con calibración por parches de gris (el perfil de la pantalla lee sRGB 40 como 53) |
| C3 | ✅ | `ThemeApplyingTests.withoutProtectionThemeIsExact` (fantasma ~3:1) |
| C4 | ✅ con desviaciones | `c4-themes`, `c4-apariencia`, `c4-prompt`, `c4-buttons`, `c4-symbol-only` y `c4-legibility` (`-side-by-side.png` en `F5-assets/`), lado a lado como en F4.5. Desviaciones abajo |
| C5 | ✅ | `WindowButtonsTests` (10): ocultos, visibles con las pastillas a 72 px, al pasar el cursor, cerrar pregunta con `sleep 100`, Zoom, Minimizar, posiciones tras redimensionar y tras pantalla completa, volver de pantalla completa, cambiar a "al pasar el cursor" con el cursor encima |
| C6 | ✅ | Causa: la sombra del sistema de una ventana no opaca, que WindowServer recalcula en cada cambio de contenido. Sombra propia en una ventana hija: **2,2 %** en reposo (2,6 % en la medición de cierre) (antes 29,5 %; base 0,2 %); con contenido moviéndose detrás, 38,5 % (antes 71,1 %; ese resto es el propio vidrio). `scripts/measure-gpu-idle.sh` (ver "GPU") |
| C7 | ✅ | `ZshPromptRendererTests`, integración en zsh real (`GhosttyAdapter`, 234 pruebas); `PromptTests.testDefaultPromptShowsDirectoryAndSymbol`, `testGitRepoShowsBranchAndChanges` (encontró que `/usr/bin/git`, el shim de xcrun, no llegaba nunca a tiempo: `GitLocator`) |
| C8 | ✅ | `silentServerDoesNotDelayPrompt` (20 prompts con servidor mudo frente a sin canal, < 100 ms en total) |
| C9 | ✅ | `ZshEscapingTests`, `branchWithSubstitutionStaysLiteral`, `percentInDirectoryIsEscaped`, `newlineInNameIsReplaced`, `hostileBranchDoesNotRunWithPromptSubst` (psvar, enmienda 1) |
| C10 | ✅ | Integración con zsh: `source = "shell"` devuelve el `PROMPT`/`RPROMPT` y `psvar` del usuario; el de Smalti gana a `.zshrc` y a un `precmd` estilo Starship |
| C10b | ⚠️ parcial | Dominio: `RenderPromptTests` (reenvío solo cuando cambian los agentes, `seq` vigente, nada tras `exec`); zsh real: `staleSpontaneousPromptIsDropped`, `spontaneousPromptKeepsBuffer`. La XCUITest con un evento de hooks quedó aplazada: ninguna de cinco simulaciones registró un agente en esa prueba (con `zsh -f` tampoco; `AgentStatusTests` sigue en verde), así que el pegamento de la app (bucle de agentes → `InputCoordinator.agentsChanged`) no tiene prueba de extremo a extremo |
| C11 | ✅ | `StarshipPresetTests` y dorados en `TOMLConfigAdapter` (TOML válido al releerlo); `PromptStudioTests.testExportWritesStarshipToTempDestination` |
| C12 | ✅ | `LegibilityTests.testThemeChangeUpdatesTwoWindowsWithoutRelaunch` (mismo PID), `AppearanceTests.testNewWindowTakesTheEditedAppearance`, `PromptTests.testThemeChangeRecolorsPromptLive`, `PromptStudioTests.testApplyUpdatesOpenShells` y `testDraftDoesNotChangeShellsBeforeApply`; estilo por panel y prompt completo reenviado tras un estilo (`RenderPromptStyleDeliveryTests`) |
| C13 | ✅ | `KeymapF5Tests`, `CommandCatalog`, `CommandCoverageGuardTests` (ningún comando de F5 pendiente); `AppearanceTests.testCommaOpensAndEscCloses`, `testOptionCommaOpensConfigToml`; `PromptStudioTests.testShiftCmdPOpensStudio`; `MenuTests.testConfigOpenCreatesTheTemplateWhenMissing` (ahora con ⌥⌘,) |
| C14 | ✅ | `AppearanceTests.testConfigTomlHashUnchanged`, `testDuplicatedKeyWarningShown` |
| C15 | ✅ | `WindowButtonsTests.testReduceMotionSkipsFade` (`-SmaltiReduceMotion`); todos los fundidos leen `Motion.isReduced` |
| C16 | ⚠️ aplazado | A9–A11 de F0 con cada tema son manuales (Claude Code, nvim, teclado Latin American): `.claude/rules/testing.md` |
| C17 | ✅ | `ImportGuardTests`, `AdapterGuardTests`; `DiagnosticsGuardTests.noLoggerPublishesPromptText` (texto del prompt, rutas, ramas, contexto de k8s y perfil de AWS, también dentro de `String(describing:)`) |
| C18 | ✅ | Ver el encabezado |
| C19 | ✅ | Ver "Mutación" |

## Verificación aplazada (manual, cuando la app esté terminada)

- A9–A11 de F0 con cada tema.
- C10b de extremo a extremo: un agente real en otro panel del workspace pasa a "te espera" y el prompt quieto lo muestra sin pulsar nada.
- Reordenar módulos del Estudio arrastrando: XCUITest no entregó a la ventana ningún evento de los arrastres (ni por elemento ni por coordenadas); el teclado (⌘↑ ⌘↓) y `EditPrompt.move` sí están probados.
- Los semáforos de macOS en pantalla completa: su barra se oculta y accesibilidad no la expone.
- El panel de color del sistema al tocar una muestra ANSI (las pruebas usan `-SmaltiPickedColor`) y el panel de guardado de la exportación (`-SmaltiExportDirectory`, solo en Debug).
- La sombra propia de la ventana en Mission Control, Stage Manager, al minimizar y con varios monitores.

## Diferencias visuales justificadas

- **Apariencia:** la ruta real abreviada ("~/.config/…/theme.toml"); fuente, espacio y radio llevan un stepper (el tablero los pinta como texto, pero C1 exige poder cambiarlos); puntos tenues de las marcas bajo los deslizadores; la nota "Vista en vivo: …" bajo los paneles no se pinta (ahí está la barra de estado).
- **Estudio:** el símbolo es una fila de cuatro segmentos y "Prompt del shell" una casilla bajo "Disposición" (textos nuevos de la spec); "Una sola línea" como texto de la disposición de una línea; los iconos ocupan una celda del terminal (más pequeños que los 14 px del tablero, ya anotado en T12); los paneles se ocultan detrás (siguen vivos).
- **Temas:** el contenido de ejemplo difiere (`ls /` frente a la salida coloreada de la maqueta); vidrio, panel y paleta coinciden.
- **Botones:** los semáforos nativos en las posiciones de `mockup-buttons`.

## GPU (C6)

`scripts/measure-gpu-idle.sh`, Smalti Dev activado delante de una ventana a pantalla completa (`scripts/gpu-backdrop.swift`), 3–5 corridas de 10 muestras:

| Escenario | por defecto | sombra del sistema | sin sombra | sin desenfoque | opaca | base |
| --- | --- | --- | --- | --- | --- | --- |
| fondo estático | **2,2 %** | 29,5 % | 1,9 % | 24,1 %¹ | 1,3 %¹ | 0,2 % |
| contenido moviéndose detrás | **38,5 %** | 71,1 % | 36,2 % | 73,6 %¹ | 33,8 %¹ | 0,8 % |

¹ Medidas con la sombra del sistema, antes del arreglo. Las cifras de T1 (9,1 %) se tomaron con la ventana detrás de la terminal y con esa terminal redibujando; el script ahora activa la app, tapa el escritorio y deja una captura por corrida.

## Mutación

`scripts/mutation/mutate.py --package Packages/SmaltiCore --changed-since origin/develop`: todos los archivos de `SmaltiCore` que cambió la rama, como en F4.5. 516 mutantes: 380 muertos, 2 sobrevivientes y 134 inválidos, **99,5 %** (mínimo 80 %). Los 2 sobrevivientes (`ChangeAppearance.reload` sin limpiar el guardado pendiente) mueren con `reloadDropsThePendingSave`, comprobado aplicando el mutante a mano. Durante la fase, las corridas incrementales dieron 98,3 % (bloque 1) y 99,4 % (bloques 2–3), con sus sobrevivientes muertos.

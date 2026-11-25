# Smalti

Terminal nativa para macOS pensada para trabajar con varios agentes de IA a la vez: tiling automático, estado de cada agente a la vista, reanudación de sesiones de Claude Code, Codex, Antigravity y OpenCode, observatorio de consumo y guardas para comandos destructivos. Swift + AppKit sobre [libghostty](https://github.com/ghostty-org/ghostty).

- Web: https://smalti.sh
- Documentación: https://smalti.sh/docs
- Gratis y de código abierto (MIT). Solo macOS 27 o posterior, en Apple Silicon.

## Instalar

### Con la DMG

1. Descarga [`Smalti.dmg`](https://github.com/simonriv/smalti/releases/latest/download/Smalti.dmg) de la [última versión](https://github.com/simonriv/smalti/releases/latest).
2. Ábrela y **arrastra Smalti a Aplicaciones**. No la abras desde la DMG: macOS la ejecutaría desde una copia temporal y no podría actualizarse.
3. Ábrela desde Aplicaciones y sigue «Primera apertura».

### Con Homebrew

```sh
brew install --cask simonriv/tap/smalti
```

Homebrew la instala en Aplicaciones con la marca de descarga de internet, así que también pide «Primera apertura».

### Desde el código

```sh
git clone --recurse-submodules https://github.com/simonriv/smalti.git
cd smalti
scripts/bootstrap
xcodebuild -project App/Smalti.xcodeproj -scheme Smalti -configuration Release -derivedDataPath build build
```

La app queda en `build/Build/Products/Release/Smalti.app`. Lo que compilas en tu Mac no lleva la marca de descarga, así que no hay aviso de primera apertura. Necesitas Xcode 27 y Homebrew (`scripts/bootstrap` instala Zig y el Metal Toolchain y compila libghostty).

## Primera apertura

Smalti no lleva firma de desarrollador de Apple (está firmada *ad hoc*) ni está **notarizada** (eso cuesta 99 USD al año y Smalti es gratis); sus actualizaciones sí van firmadas con la clave EdDSA de Smalti. La primera vez que la abras, macOS dirá que no pudo verificarla. Tienes dos formas de abrirla; las dos son de una sola vez.

**Desde Ajustes del Sistema**

1. Abre Smalti. macOS muestra el aviso; pulsa «Listo» (o «Aceptar», según tu español).
2. Ve a **Ajustes del Sistema → Privacidad y seguridad**, baja hasta «Seguridad» y pulsa **«Abrir igualmente»** junto al mensaje sobre Smalti.
3. Confirma con tu contraseña o Touch ID, y pulsa «Abrir igualmente» otra vez.

<!-- Capturas de macOS 27: docs/specs/F7.6-assets/ (se añaden al cerrar la fase) -->

**Desde la terminal**

```sh
xattr -dr com.apple.quarantine /Applications/Smalti.app
```

## Actualizaciones

Smalti busca una versión nueva una vez al día (y cuando eliges «Buscar actualizaciones…» en el menú Smalti o en ⌘K) y te pregunta antes de instalarla. Cada versión va firmada con la clave EdDSA de Smalti: una descarga que no lleve esa firma se rechaza. Las actualizaciones no vuelven a mostrar el aviso de primera apertura.

Esa comprobación es **lo único que sale de tu Mac**: Smalti no envía datos de uso ni del sistema. Puedes apagarla con ⌘K → «Desactivar actualizaciones automáticas».

Limitaciones de no estar notarizada:

- La primera apertura necesita «Abrir igualmente» o `xattr`.
- Si concedes a Smalti permisos de privacidad (Accesibilidad, Automatización, carpetas protegidas), macOS puede volver a pedirlos tras una actualización, porque cada versión tiene una firma distinta.
- Si abres Smalti sin moverla a Aplicaciones, no podrá actualizarse (te lo dirá).

## Desinstalar

Arrastra `Smalti.app` a la papelera. Su configuración y su estado viven en `~/.config/smalti` y `~/Library/Application Support/Smalti`; bórralos si quieres empezar de cero. Con Homebrew: `brew uninstall --cask smalti` (añade `--zap` para borrar también esas carpetas).

## Contribuir

Smalti acepta issues, no pull requests: ver [CONTRIBUTING.md](CONTRIBUTING.md). Para reportar un fallo o una idea desde la app: ⌘K → «Reportar un problema o una idea…».

## Apoyar

Smalti es gratis. Si te ahorra tiempo, puedes apoyarlo en https://smalti.sh/es#apoyar.

## Licencia

[MIT](LICENSE). Los componentes de terceros y sus licencias están en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), que también va dentro de la app.

# F7 · Extras — Spec

Estado: aprobada · 2026-11-25 (Simón aprobó de antemano la spec, el plan y las recomendaciones de Claude) · Roadmap: `docs/ROADMAP.md#f7--extras`
Diseño: `Observatorio.dc.html` (detalle de la sesión y pie) y `Paleta.dc.html` (grupo «Workspaces y sesiones»). Ningún tablero dibuja la línea de telemetría ni la importación: se resolvieron con las recomendaciones de Claude (ver «Diferencias con los tableros»).

## Objetivo

Dos capacidades opcionales que no tocan el rendimiento base:

1. **Layouts compartibles:** un layout con nombre (F2) sale de Smalti como archivo portátil y entra en otro Mac, o en el mismo después de reinstalar, sin rutas personales ni IDs de sesión.
2. **Receptor OTLP local:** Smalti escucha la telemetría OpenTelemetry de los Claude Code que corren en sus paneles y el Observatorio muestra lo que los transcripts no tienen: el costo que calcula el propio Claude Code, las peticiones a la API, su latencia y los errores de API.

Anti-objetivo: **F7 fracasa si algo sale de la máquina o cuesta dinero, si el receptor escucha en otra interfaz que `127.0.0.1`, si Smalti activa la telemetría de Claude cuando el usuario ya la configuró a otro destino, si importar un layout ejecuta comandos que el usuario no vio, si un layout exportado lleva IDs de sesión, scrollback o la ruta del home, si alguna medición de F0 o F4 empeora más de un 5 % con un extra encendido, o si las pruebas leen o escriben `~/.claude` o `~/.config/smalti` reales o usan un Claude real.**

## Hechos verificados (antes de diseñar)

Verificados el 2026-11-25 en la documentación oficial (`code.claude.com/docs/en/monitoring-usage`) y en las cadenas del binario instalado de Claude Code **2.1.332** (solo lectura, sin ejecutarlo).

| Tema | Hecho |
| --- | --- |
| Activación | `CLAUDE_CODE_ENABLE_TELEMETRY=1` más un exportador por señal: `OTEL_LOGS_EXPORTER`, `OTEL_METRICS_EXPORTER`, `OTEL_TRACES_EXPORTER` (`otlp`, `console`, `none`) |
| Transporte | `OTEL_EXPORTER_OTLP_PROTOCOL` y sus variantes por señal: `grpc`, `http/json`, `http/protobuf` (por defecto). Endpoint genérico `OTEL_EXPORTER_OTLP_ENDPOINT` y por señal `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` (URL completa, `…/v1/logs`), que manda sobre el genérico. Cabeceras `OTEL_EXPORTER_OTLP_LOGS_HEADERS` |
| Intervalos | Logs cada 5 s (`OTEL_LOGS_EXPORT_INTERVAL=5000`), métricas cada 60 s |
| Eventos | Log records con `body = "claude_code.<evento>"` y los atributos `event.name`, `event.timestamp` (ISO 8601), `event.sequence` y `session.id`. `api_request`: `model`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `cost_usd`, `cost_usd_micros`, `duration_ms`, `ttft_ms`, `request_id`, `speed`, `query_source`. `api_error`: `model`, `error`, `status_code` (si lo hubo), `duration_ms`, `attempt`; se emite una vez, al agotar los reintentos |
| Privacidad por defecto | No se registra el texto de los prompts, las respuestas ni los argumentos de herramientas (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS` y similares están apagados) |
| Dónde se configura | Claude ignora las variables de exportador en `.claude/settings.json` de un repo: un repo no puede activar la telemetría ni elegir destino. Sí cuentan el entorno del proceso, `~/.claude/settings.json` (`env`) y los managed settings (`/Library/Application Support/ClaudeCode/managed-settings.json`) |
| Subprocesos | Claude no pasa `OTEL_*` a sus subprocesos (Bash, hooks, MCP) |

## Decisiones (Claude, aprobadas de antemano por Simón)

| Tema | Elegido | Descartado y por qué |
| --- | --- | --- |
| Qué aporta OTLP al Observatorio | **Lo que los transcripts no tienen:** costo según Claude Code, peticiones, mediana de latencia y errores de API, en una línea del detalle de la sesión | Sustituir tokens o costo de las columnas: mezcla dos calidades de dato en la misma columna (razón de F3 para aplazarlo) y rompe la exactitud de C1 de F3 |
| Señales | **Solo logs** (eventos, cada 5 s); métricas y trazas en `none` | Métricas: llegan cada 60 s, en delta, y lo que añaden (líneas, commits, tiempo activo) no sale en ningún tablero |
| Protocolo | **`http/json`**: Foundation lo decodifica sin dependencias | `http/protobuf`: exige un decodificador protobuf; gRPC: HTTP/2 |
| Receptor | **Socket TCP propio ligado a `127.0.0.1`** en un puerto efímero, HTTP/1.1 mínimo (`POST /v1/logs`, `Content-Length`, keep-alive), con un token aleatorio por arranque en `Authorization: Bearer` | Network.framework: no permite comprobar con `getsockname` la dirección exacta; un servidor HTTP de terceros: dependencia para cuatro rutas |
| Inyección | **Variables por señal en el entorno de cada panel** (ver abajo), solo si el usuario no configuró la telemetría de Claude por su cuenta | Escribir en `~/.claude/settings.json`: Smalti no escribe la configuración de Simón; `claude --settings` solo cubriría los Claude que relanza Smalti |
| Encendido | **`[extras] otlp = true` por defecto** en `config.toml`, recargable en vivo; afecta a los paneles nuevos | Apagado por defecto: Simón pidió que la telemetría alimente el Observatorio; un toggle en ⌘K: la UI no escribe `config.toml` (F5) |
| Formato del layout compartible | **JSON portátil versionado** (`<nombre>.smalti-layout.json`), con rutas relativas a la raíz y la raíz con `~` | TOML: el árbol de splits anidado sin límite de profundidad es incómodo en TOML; reutilizar el JSON interno de F2: lleva UUIDs, IDs de sesión y rutas absolutas |
| Agentes en un layout compartible | **Solo el harness** (`"harness": "claude"`): al abrirse se relanza con `continueCommand` (el respaldo de F6) | IDs de sesión: son de una máquina y de una persona |
| Seguridad al importar | **Confirmación que lista cada comando** que el layout ejecutará al abrirse, antes de guardarlo | Importar en silencio: un archivo ajeno ejecutaría comandos al restaurarlo |

## Alcance

1. **Layouts compartibles:**
   - ⌘K «Exportar layout “<nombre>”…» por cada layout guardado: panel de guardado de macOS con `<nombre>.smalti-layout.json`.
   - ⌘K «Importar layout…»: panel de apertura, validación, confirmación con los comandos y, si la carpeta raíz no existe en este Mac, elección de la carpeta. Queda como layout guardado y aparece en «Restaurar layout “<nombre>”».
2. **Receptor OTLP local y telemetría en el Observatorio:**
   - receptor que arranca con la app si `[extras] otlp` está encendido y la telemetría de Claude no está configurada por el usuario;
   - variables inyectadas en el entorno de cada panel nuevo;
   - eventos `api_request` y `api_error` plegados por sesión en memoria;
   - línea «Telemetría» en el detalle de la sesión y pie del Observatorio con «telemetría de Claude Code».
3. **Mediciones de cierre** de F0 y F4 con cada extra apagado y encendido.

## Fuera de alcance

- La predicción por API o `claude -p` y el daemon `smaltid` (ROADMAP, «Fuera»).
- Métricas y trazas OTLP; `grpc` y `http/protobuf`; compresión `gzip` (se responde 415).
- Guardar la telemetría en disco: vive mientras la app está abierta. Los procesos de los paneles mueren con la app, así que el receptor nunca pierde a un emisor vivo.
- Telemetría de los Claude que no corren en Smalti, y de Codex, Antigravity u OpenCode.
- Cambiar el estado del panel con `api_error`: el hook `StopFailure` de F2 ya lo pone en rojo.
- Compartir layouts por la CLI, el portapapeles o arrastrando el archivo; layouts por proyecto descubiertos en el repo.
- F8.

## Diseño técnico

### Módulos

| Módulo | Qué añade |
| --- | --- |
| `SmaltiCore/Domain/Session/SharedLayout.swift` (nuevo) | `SharedLayout` (formato 1): `name`, `root` (con `~` si está bajo el home), `layout`, `focused`, `tree` (`SnapshotTree`), `panes: [SharedPane]`. `SharedPane`: `directory` relativa a la raíz (`.`, `api`) o absoluta si queda fuera, `command: [String]?`, `harness: HarnessID?`, `editor: SharedEditor?` (archivo relativo y línea). `SharedLayout(exporting:home:)` desde un `WorkspaceSnapshot`; `validated()` y `workspaceSnapshot(root:)` al importar. `SharedLayoutError` tipado |
| `SmaltiCore/Application/ShareLayoutCommands.swift` (nuevo) | `ExportLayout` (nombre → `SharedLayout` → `LayoutFiles.write`), `ImportLayout` en dos pasos: `read` (archivo → `ImportPreview` con nombre, comandos, raíz y si existe) y `confirm` (preview + raíz elegida → `NamedLayouts.save` con nombre libre: «solen-dev», «solen-dev 2»…) |
| `SmaltiCore/Application/SessionArchive.swift` | Puerto `LayoutFiles`: `write(_:to:)`, `read(from:)`. Lo implementa `FileSessionAdapter` |
| `SmaltiCore/Domain/Telemetry/` (nuevo) | `TelemetryEvent` (`apiRequest(APIRequest)`, `apiError(APIError)`), `SessionTelemetry` (desde, peticiones, errores por código, últimas 200 duraciones para la mediana, costo en micro-USD), `TelemetryLedger` (por sesión, tope de 200 sesiones; descarta la más antigua), `TelemetryEndpoint` (puerto, token) y `TelemetryEnvironment.variables(for:)` |
| `SmaltiCore/Application/TelemetryPorts.swift` (nuevo) | Puerto `TelemetryReceiver`: `start() throws(TelemetryReceiverError) -> TelemetryEndpoint`, `events() -> AsyncStream<[TelemetryEvent]>`, `stop()`. Puerto `ClaudeTelemetrySettings`: `isConfiguredByUser() -> Bool`. Caso de uso `CollectTelemetry` (decide si arranca, da las variables a `ChildEnvironment` y pliega los lotes en el `TelemetryLedger`) |
| `SmaltiCore/Application/ChildEnvironment.swift` | Recibe las variables de telemetría si `CollectTelemetry` las da |
| `SmaltiCore/Domain/Config` | `ExtrasSettings { otlp: Bool }` (`[extras]`, por defecto `true`) en `SmaltiConfig` |
| `SmaltiCore/Domain/Observatory` | `ObservatorySnapshot` gana `telemetry: [String: SessionTelemetry]`; el informe del detalle gana `telemetryLine: String?`; el pie cambia según haya telemetría |
| `OTLPReceiverAdapter` (paquete nuevo) | `LoopbackOTLPReceiver`: socket `AF_INET` ligado a `INADDR_LOOPBACK` y puerto 0, `DispatchSource` para aceptar y leer, parser HTTP/1.1, `OTLPLogsDecoder` (JSON de `ExportLogsServiceRequest` → `[TelemetryEvent]`). Único que importa `Darwin` para sockets TCP |
| `ClaudeTelemetryAdapter` | `ClaudeSettingsTelemetryCheck`: lee el bloque `env` de `<claude home>/settings.json` y de los managed settings y responde si define `CLAUDE_CODE_ENABLE_TELEMETRY` o alguna `OTEL_*` |
| `FileSessionAdapter` | `SharedLayoutFiles` (JSON con claves ordenadas y sangría; tope de lectura de 256 KB) |
| `SmaltiApp` | Entradas de ⌘K, paneles de guardar y abrir, confirmación, línea del Observatorio, composition root y flags de prueba |

### Receptor OTLP

- **Escucha:** `socket(AF_INET, SOCK_STREAM)`, `bind` a `127.0.0.1:0`, `listen`. El puerto sale de `getsockname`. Nunca `INADDR_ANY` ni IPv6.
- **Peticiones:**
  - `POST /v1/logs` con `Content-Type: application/json` y `Authorization: Bearer <token>` → 200 con `{}`;
  - sin token o con otro → 401; otra ruta → 404; otro método → 405; `Content-Encoding` distinto de `identity` → 415; sin `Content-Length` → 411; cuerpo de más de 4 MB → 413; JSON que no se entiende → 400.
  - Una conexión puede llevar varias peticiones (keep-alive). Una conexión callada 30 s se cierra; como mucho 16 conexiones a la vez.
- **Decodificación:** `resourceLogs[].scopeLogs[].logRecords[]`. El nombre sale de `event.name` o, si falta, del `body` sin el prefijo `claude_code.`. Los valores aceptan `stringValue`, `intValue` (número o texto) y `doubleValue`. Un registro sin `session.id`, de otro evento o con un campo ilegible se omite; nunca falla el lote.
- **Hilos:** el socket y el parser corren en una cola propia; los lotes llegan al `MainActor` por el `AsyncStream`.
- **Ciclo de vida:** arranca al abrir la app (o al encender `[extras] otlp` en caliente) y se detiene al cerrarla o al apagarlo. Si no puede ligar el socket, no se inyecta nada y la barra de estado lo dice una vez.

### Variables que reciben los paneles

Solo si el receptor está escuchando, en todos los paneles nuevos, después de quitar las variables heredadas de F2:

```text
CLAUDE_CODE_ENABLE_TELEMETRY=1
OTEL_LOGS_EXPORTER=otlp
OTEL_METRICS_EXPORTER=none
OTEL_TRACES_EXPORTER=none
OTEL_EXPORTER_OTLP_LOGS_PROTOCOL=http/json
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://127.0.0.1:<puerto>/v1/logs
OTEL_EXPORTER_OTLP_LOGS_HEADERS=Authorization=Bearer <token>
OTEL_LOGS_EXPORT_INTERVAL=5000
```

- **Respeto a la configuración del usuario:** si `ClaudeTelemetrySettings.isConfiguredByUser()` es cierto, Smalti no arranca el receptor ni inyecta nada; el pie del Observatorio dice «Telemetría de Claude Code configurada fuera de Smalti: no se recibe aquí.».
- **Riesgo residual (documentado):** un `.zshrc` que exporte un endpoint OTLP propio sustituiría el de Smalti dentro de ese shell. Es configuración explícita del usuario; los repos no pueden hacerlo.

### Telemetría en el Observatorio

- **Plegado:** `api_request` suma una petición, su `duration_ms` y su `cost_usd_micros` (o `cost_usd` × 10⁶); `api_error` suma un error con su `status_code`. Un evento repetido (misma sesión y `event.sequence`) cuenta una vez.
- **Línea del detalle,** debajo de la de compactación y con su mismo estilo, solo si la sesión tiene telemetría:
  - «Telemetría · desde 10:42 · 42 peticiones · mediana 1,4 s · 2 errores de API · $3.12 según Claude Code»;
  - «1 petición», «sin errores de API», y la mediana en ms por debajo de un segundo («mediana 820 ms»).
- **Pie:**
  - con telemetría recibida: «Datos: hooks, transcripts y telemetría de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado.»;
  - sin telemetría, el de F6 sin cambios;
  - con la telemetría configurada fuera de Smalti, el texto de la sección anterior.
- Las columnas, las tarjetas de resumen y el costo estimado no cambian.

### Layouts compartibles

**Formato** (`<nombre>.smalti-layout.json`):

```json
{
  "smaltiLayout": 1,
  "name": "solen-dev",
  "root": "~/Projects/solen",
  "layout": "dwindle",
  "focused": 0,
  "tree": { "...": "SnapshotTree de F2" },
  "panes": [
    { "directory": ".", "command": ["pnpm", "dev"] },
    { "directory": "api", "harness": "claude" },
    { "directory": ".", "editor": { "file": "src/reminder.ts", "line": 42 } },
    { "directory": "." }
  ]
}
```

- **Exportar:**
  - sin `id` de panel, `sessionID`, título, nombre de proceso, número de líneas ni comandos;
  - la raíz bajo el home se escribe con `~`;
  - un directorio dentro de la raíz se escribe relativo; fuera, con `~` o absoluto.
- **Importar, validación** (`SharedLayoutError` con motivo):
  - formato distinto de 1;
  - nombre que no es un `LayoutName` válido;
  - 0 o más de 9 paneles;
  - árbol con un número de hojas distinto del de paneles;
  - comando vacío o no tecleable (`RelaunchCommand.isTypeable`);
  - directorio relativo con `..`;
  - archivo de más de 256 KB o que no es JSON.
  - Un harness desconocido o un layout desconocido no invalidan el archivo: el panel queda como shell y el layout pasa a Dwindle, y la confirmación lo dice.
- **Confirmación** (alerta de macOS, como la de cerrar con procesos de F4.5):
  - título «¿Importar el layout “solen-dev”?»;
  - texto «Al abrirlo ejecutará: pnpm dev · claude --continue · nvim +42 src/reminder.ts» (uno por panel que ejecute algo) o «Al abrirlo solo abrirá shells.»;
  - botones «Importar» y «Cancelar».
- **Raíz que no existe:** tras confirmar, panel de carpeta de macOS «Elige la carpeta de “solen-dev” en este Mac». Cancelar no importa nada.
- **Nombre ocupado:** «solen-dev 2», «solen-dev 3»…; nunca se pisa un layout guardado.
- **Al terminar:** barra de estado «Layout “solen-dev” importado» o «No se pudo importar el layout: <motivo>».
- **Al restaurarlo:** el camino de F2/F6 de siempre; un panel con `harness` se relanza con `continueCommand` en su directorio.

### Configuración y flags de prueba

- `config.toml`:

  ```toml
  [extras]
  otlp = true
  ```

  Un valor que no es booleano es un error de configuración como los demás (F1).
- **Flags de las UI tests:**
  - `-SmaltiImportFile <ruta>` sustituye al panel de abrir;
  - `-SmaltiPickedFolder <ruta>` sustituye al panel de carpeta;
  - `-SmaltiExportDirectory` (F5) sirve también para exportar;
  - `-SmaltiConfirmImport yes|no` responde la confirmación;
  - `-SmaltiClaudeHome` (F3) también apunta la comprobación de `settings.json`;
  - `-SmaltiManagedSettings <ruta>` sustituye la ruta de los managed settings;
  - `-SmaltiTelemetryProbe <archivo>` escribe en un archivo temporal el puerto y si el receptor escucha, para que la prueba lo lea sin tocar la UI.
- **Emisor falso:** `scripts/otlp/fake-claude.py` lee las variables del panel, manda lotes OTLP JSON con eventos `api_request` y `api_error` como los de Claude Code 2.1.332 y termina solo. Corre en un panel con `/bin/zsh -f`, así que cubre de extremo a extremo la inyección del entorno.

### Textos nuevos (interfaz en español)

- **⌘K:** «Exportar layout “<nombre>”…», «Importar layout…».
- **Importación:** «¿Importar el layout “<nombre>”?», «Al abrirlo ejecutará: …», «Al abrirlo solo abrirá shells.», «Importar», «Cancelar», «Elige la carpeta de “<nombre>” en este Mac», «Layout “<nombre>” importado», «No se pudo importar el layout: <motivo>», «Layout “<nombre>” exportado», «No se pudo exportar el layout: <motivo>».
- **Observatorio:** la línea «Telemetría · …» y los dos pies nuevos.
- **Barra de estado:** «No se pudo arrancar el receptor de telemetría: <motivo>».

### Diferencias con los tableros (se justifican en el PR)

- La línea «Telemetría» del detalle no sale en `Observatorio.dc.html`: reutiliza la tipografía y el color de la línea de compactación, en la fila siguiente.
- Las dos entradas de ⌘K siguen el estilo de «Guardar layout actual…» de `Paleta.dc.html`.
- La confirmación y los paneles de archivo son los del sistema, como el panel de guardado de F5 y la confirmación de cierre de F4.5.

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
| --- | --- | --- |
| C1 | **Cierre del roadmap:** el receptor escucha solo en `127.0.0.1`: `getsockname` devuelve `127.0.0.1`; conectar al mismo puerto por la IPv4 no loopback de la máquina y por `::1` falla; el endpoint inyectado usa `127.0.0.1` | `OTLPReceiverAdapter` (prueba de red) + dominio (`TelemetryEnvironment`) |
| C2 | **Cierre del roadmap:** con cada extra apagado y encendido, las mediciones de F0 (A12 `cat50mb` y `seq5m`, A14 memoria, GPU en reposo de F5 C6) y de F4 (C1 del benchmark y C13 de extremo a extremo) no empeoran más de un 5 %. OTLP encendido se mide con 3 emisores falsos mandando cada 5 s | Mediciones al cierre, tabla en el checklist |
| C3 | Receptor HTTP: 200 con token, 401, 404, 405, 411, 413, 415 y 400 según la petición; keep-alive con varias peticiones; conexión callada cerrada a los 30 s; tope de 16 conexiones; un lote con registros ilegibles entrega los legibles | `OTLPReceiverAdapter` |
| C4 | Decodificación: `api_request` y `api_error` con `intValue` en número y en texto, `doubleValue`, nombre por `event.name` o por `body`; sin `session.id` u otro evento → omitido | `OTLPLogsDecoder` con fixtures JSON escritos a partir de los atributos verificados |
| C5 | Inyección: con OTLP encendido y el receptor escuchando, cada panel nuevo recibe exactamente las variables de la spec; apagado, con el receptor caído o con la telemetría configurada por el usuario (en `settings.json` o en managed settings), ninguna. Cambiar `[extras] otlp` en caliente arranca o detiene el receptor y vale para los paneles nuevos | Dominio (`CollectTelemetry`, `ChildEnvironment`) + `ClaudeSettingsTelemetryCheck` + XCUITest con el emisor falso |
| C6 | Observatorio: la línea de telemetría (plural, mediana en s y ms, «sin errores de API», costo en $), sin línea si no hay telemetría, eventos repetidos contados una vez, tope de 200 sesiones; pies según el caso; las columnas y el resumen no cambian | Dominio + XCUITest con el emisor falso en un panel |
| C7 | Exportar: el archivo no contiene `id`, `sessionID`, título, scrollback ni la ruta absoluta del home; raíz con `~`, directorios relativos; exportar e importar devuelve el mismo layout (árbol, layout, foco, comandos, harness, editor) | Dominio (`SharedLayout`) + `SharedLayoutFiles` + XCUITest |
| C8 | Importar: cada motivo de validación da su error tipado y su texto; harness o layout desconocidos degradan y lo dicen; la confirmación lista cada comando; cancelar no guarda nada; raíz inexistente → carpeta elegida; nombre ocupado → «nombre 2» | Dominio (`ImportLayout`) + XCUITest con `-SmaltiImportFile`, `-SmaltiConfirmImport` y `-SmaltiPickedFolder` |
| C9 | Aislamiento: ninguna prueba lee ni escribe `~/.claude`, `~/.config/smalti` ni los managed settings reales, ni lanza un Claude real; la telemetría de prueba sale de `fake-claude.py` | Guarda + `isolatedSmalti()` con los flags nuevos + `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID` |
| C10 | Guardas: `SmaltiCore` en Swift puro; solo `OTLPReceiverAdapter` abre sockets TCP; ningún `Logger` publica el token, cuerpos OTLP ni rutas | Pruebas de guarda |
| C11 | Sin procesos huérfanos: tras cada suite no queda ningún receptor, emisor falso ni conexión abierta lanzados por ella | Comprobación al final de cada suite + `ps` en el cierre |
| C12 | Mutación ≥ 80 % en los archivos de `SmaltiCore` que cambia la fase | `scripts/mutation/mutate.py --changed-since origin/develop` al cierre |

**Criterio de cierre del roadmap:** C1 y C2, en verde.

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| El JSON del exportador de Claude difiere de lo verificado (p. ej. `intValue` como texto) | Telemetría vacía | Decodificador tolerante (C4) y omisión por registro; la versión verificada queda anotada en los fixtures |
| Una versión futura de Claude cambia los nombres de evento | Línea de telemetría vacía | Degrada a «sin línea»: nada se rompe |
| El usuario configuró OTLP a otro destino en su shell | Smalti no recibe nada en ese shell | Documentado; los repos no pueden hacerlo |
| El receptor añade coste en reposo | Rompe C2 | Sin temporizadores: el socket solo despierta con datos; se mide al cierre |
| Un layout importado ejecuta comandos ajenos | Ejecución inesperada | Confirmación con cada comando antes de guardar; comandos no tecleables rechazados |

## Plan de pruebas y revisiones

Según `.claude/rules/`:

- **Revisiones:**
  - intermedia 1, al terminar dominio y adaptadores (`SharedLayout`, casos de uso, `TelemetryLedger`, `CollectTelemetry`, `OTLPReceiverAdapter`, `ClaudeSettingsTelemetryCheck`, `SharedLayoutFiles`);
  - intermedia 2, al terminar la app (⌘K, paneles, confirmación, Observatorio, composition root, emisor falso);
  - final de la rama, acotada y con el modelo más capaz.
- **Mutación:** una por revisión intermedia con `--changed-since`; cada sobreviviente se mata con una prueba verificada aplicando el mutante a mano. Al cierre, solo los archivos de la fase; la completa solo si la rama cambia código compartido (se decide al cierre según el diff).
- Mediciones (C2) y capturas solo al cierre.
- XCUITest en una sola corrida de `scripts/test-ui.sh` por tanda, solo lo afectado, nunca dos a la vez, siempre por `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID`. Las pruebas que abren un shell usan `-SmaltiShellCommand "/bin/zsh -f"`. Las apps GUI se lanzan con `env -i`.

## Cambios en otros documentos (con esta spec)

- `docs/ROADMAP.md`, F7: spec (esta).
- `docs/PROJECT.md`: el pilar 4 nombra la telemetría OTLP de Claude Code como fuente (solo para los paneles de Smalti); «Receptor OTLP local en F7» pasa a describir el adaptador.
- `CLAUDE.md`: puertos `TelemetryReceiver`, `ClaudeTelemetrySettings` y `LayoutFiles`; paquete `OTLPReceiverAdapter` en «Comandos» y en la línea de `swift format lint`; flags nuevos.
- `docs/design/README.md`: nota bajo `Observatorio.dc.html` (línea de telemetría y pies) y bajo `Paleta.dc.html` (exportar e importar layouts).

## Enmiendas

1. **2026-11-25 · Revisión intermedia 1, Claude.** Validación del layout importado, más estricta:
   - un panel con más de uno de `command`, `harness` y `editor` se rechaza («indica más de un programa que abrir»), porque la confirmación mostraría uno y se ejecutaría otro;
   - el archivo del editor debe ser tecleable (sin caracteres de control) y la línea ≥ 1, porque se escribe en el shell;
   - las hojas del árbol deben ser cada panel exactamente una vez;
   - la raíz debe ser `~`, `~/…` o absoluta;
   - un comando con el primer argumento vacío se rechaza.
2. **2026-11-25 · Revisión intermedia 1, Claude.** La confirmación sale de la misma regla que restaura (`PaneLaunch.saved`), así que el comando de un panel de Neovim se muestra con su ruta completa (`nvim +42 /Users/…/src/a.ts`).
3. **2026-11-25 · Revisión intermedia 1, Claude.** Al exportar, los argumentos de los comandos que empiezan por el home se escriben con `~` (C7); al importar, ese `~` se expande con el home de esta máquina, porque el shell no expande un `~` entre comillas.
4. **2026-11-25 · Revisión intermedia 1, Claude.** Un evento repetido es el de la misma sesión, el mismo `event.sequence` y la misma `event.timestamp`: `event.sequence` vuelve a empezar si Claude se relanza sobre la misma sesión (`claude --continue`).
5. **2026-11-25 · Revisión intermedia 1, Claude (decisión delegada por Simón).** Las variables de telemetría las hereda todo lo que corre en el panel, no solo Claude: un programa propio instrumentado con OpenTelemetry pierde sus métricas y trazas (`none`) y manda sus logs al receptor de Smalti, que los descarta. Se mantiene así y se documenta: `OTEL_METRICS_EXPORTER=none` y `OTEL_TRACES_EXPORTER=none` son la guarda que impide que Claude mande métricas a un endpoint genérico configurado en el shell. Quien depure con OpenTelemetry en un panel puede exportar sus propias variables en ese shell o apagar `[extras] otlp`.
6. **2026-11-25 · Revisión intermedia 1, Claude.** Robustez del receptor: sus sockets llevan `FD_CLOEXEC` (los paneles no los heredan); una petición debe llegar entera dentro del plazo de 30 s, no solo un byte cada 30 s; números fuera de rango o negativos omiten el registro y un `status_code` ilegible cuenta el error sin código.
7. **2026-11-25 · Revisión intermedia 2, Claude (decisión delegada por Simón).** Corrige el «riesgo residual»: las variables por señal de Smalti (`OTEL_EXPORTER_OTLP_LOGS_*`) mandan sobre una configuración genérica del `.zshrc` (`OTEL_EXPORTER_OTLP_ENDPOINT`), así que los eventos de Claude de ese shell llegan a Smalti y no al colector del usuario (sus métricas sí siguen yendo a él). Se mantiene así porque inyectar las variables genéricas permitiría que un endpoint remoto del `.zshrc` recibiera los logs de Claude por culpa de Smalti, y «nada sale de la máquina» manda. Para reducirlo, el entorno del propio proceso de Smalti cuenta como «configurado por el usuario» (no se inyecta nada), igual que `settings.json` y los managed settings, y la comprobación se repite en cada recarga: una configuración que aparece o desaparece en caliente gana. Quien configure OpenTelemetry solo en su `.zshrc` debe poner `[extras] otlp = false`.
8. **2026-11-25 · Revisión intermedia 2, Claude.** Si la raíz del layout importado no existe, la carpeta se elige **antes** de la confirmación, y la confirmación muestra los comandos con esa carpeta.
9. **2026-11-25 · Plan y ejecución, Claude.** Recoge dos decisiones del plan: el puerto `TelemetryReceiver` entrega los lotes con un callback `@MainActor` (`start(onBatch:)`) en vez de un `AsyncStream`, y `SharedLayout.workspaceSnapshot(root:home:)` recibe también el home para resolver `~`. La telemetría con el Observatorio abierto lo refresca como mucho una vez cada 2 s, y cada sesión recuerda las últimas 1.000 entregas para reconocer repeticiones.

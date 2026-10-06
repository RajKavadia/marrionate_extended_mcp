# JSON MCP instructions for live apps

This framework drives **Marionette** (and flutter-skill on web) through the
**Model Context Protocol**. End-to-end tests are stored as JSON; the same steps
can be exported as **JSON-RPC MCP messages** you send to a running
`flutter-e2e-mcp` server while the app is attached.

## Two JSON layers

| Layer | Purpose | Example location |
|-------|---------|------------------|
| **Scenario** | Human/agent-friendly test script (`action` + `key`) | `e2e/scenarios/*.json` |
| **MCP instructions** | Wire format for a live MCP session (`tools/call`) | `e2e/mcp-instructions/*.mcp.json` |

Scenarios are validated against `KeyRegistry` and replayed by the MCP server.
MCP instructions are what you **attach to a live application** after
`flutter run` (debug) prints a VM service URI.

## Live application flow

1. **Instrument the app** (debug only):

   ```dart
   E2eBinding.ensureInitialized(const E2eConfig());
   runApp(const MyApp());
   ```

2. **Start the app** — `flutter run -d windows` (or your target).

3. **Start the MCP server**:

   ```bash
   flutter-e2e-mcp serve --scenarios ./e2e/scenarios
   ```

4. **Connect** — replace `{{VM_SERVICE_URI}}` in the exported script with the
   URI from the console (e.g. `ws://127.0.0.1:9100/TOKEN=/ws`), then send the
   `connect_app` message.

5. **Run instructions** — send each entry in `instructions` (or one
   `execute_batch`) as JSON-RPC on stdio.

## In-app recorder (FAB)

In debug builds the demo app shows a **Record E2E** floating action button. It
records taps on widgets with `ValueKey<String>` and text when a field loses
focus, then exports:

- **MCP script** — `connect_app` + `mcp_*` `tools/call` JSON-RPC messages
- **Scenario** — the same steps in `e2e/scenarios` format

Wrap your own app the same way:

```dart
MaterialApp(
  builder: (context, child) {
    if (kReleaseMode || child == null) return child ?? const SizedBox.shrink();
    return E2eRecorderScope(
      child: Stack(
        children: [
          child,
          const Positioned(right: 16, bottom: 16, child: E2eRecorderFab()),
        ],
      ),
    );
  },
);
```

## Export scenarios → MCP JSON

From the repo root:

```bash
dart run tool/export_mcp_instructions.dart --scenarios e2e/scenarios --out e2e/mcp-instructions
```

Options:

- `--web` — emit `skill_*` tools for CDP/web instead of `mcp_*` (Marionette).
- `--batch-only` — emit `connect_app` + a single `execute_batch` instead of
  one `tools/call` per step.

## Instruction file shape (`formatVersion: 1`)

```json
{
  "format": "flutter-e2e-mcp-instructions",
  "formatVersion": 1,
  "server": "flutter-e2e-mcp",
  "scenario": "profile_submit_valid",
  "transportPreference": "marionetteFirst",
  "attachTargetPlaceholder": "{{VM_SERVICE_URI}}",
  "attach": {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "connect_app",
      "arguments": {
        "target": "{{VM_SERVICE_URI}}",
        "kind": "vmService"
      }
    }
  },
  "instructions": [
    {
      "jsonrpc": "2.0",
      "id": 2,
      "method": "tools/call",
      "params": {
        "name": "mcp_tap",
        "arguments": { "key": "home_profile" }
      }
    }
  ]
}
```

Under **Marionette-first** (native debug), interaction tools use the `mcp_`
prefix (`mcp_tap`, `mcp_enter_text`, …). Assertions such as
`assert_text_contains` map to Marionette-backed tools on the unified server.

## Scenario JSON (source format)

```json
{
  "name": "profile_submit_valid",
  "commands": [
    { "action": "tap", "key": "home_profile" },
    { "action": "enter_text", "key": "name_field", "text": "Ada Lovelace" },
    { "action": "assert_text_contains", "key": "profile_result", "text": "submitted" }
  ]
}
```

The server accepts the same steps via `execute_batch`, `replay_scenario`, or
individual `tools/call` messages after export.

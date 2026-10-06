# marrionate_extended_mcp

Unified Flutter end-to-end automation in a single package: MCP server,
app-side bindings, scenario model, replay runtime, key-injection builder, and
the vendored marionette / flutter-skill drivers behind one import.

See [doc/mcp-instructions.md](doc/mcp-instructions.md) for the MCP wire format
and how to attach exported instructions to a running debug app.

## Install

```yaml
dependencies:
  marrionate_extended_mcp: ^0.1.0
```

While it is not yet on pub.dev, depend on it by path or git:

```yaml
dependencies:
  marrionate_extended_mcp:
    path: ../marrionate_extended_mcp
    # or:
    # git:
    #   url: https://github.com/your-org/marrionate_extended_mcp.git
```

## What's inside

| Module (`lib/src/...`) | Origin | Provides |
|---|---|---|
| `flutter_e2e_toolkit` | first-party | app-side bindings, scenario model, validator, recorder |
| `flutter_e2e_mcp` | first-party | unified MCP server + replay CLI |
| `e2e_key_generator` | first-party | build_runner builder injecting `ValueKey<String>` |
| `marionette_mcp` | vendored (Apache-2.0) | MCP server, session/step logging, stdio + WS transports |
| `marionette_flutter` | vendored (Apache-2.0) | `ext.flutter.marionette.*` service extensions |
| `marionette_cli` | vendored (Apache-2.0) | command-line client |
| `marionette_logger` / `marionette_logging` | vendored (Apache-2.0) | structured logging |
| `flutter_skill` | vendored (MIT) | JS/CDP bridge for web apps |

Everything is exported from the single barrel file:

```dart
import 'package:marrionate_extended_mcp/marrionate_extended_mcp.dart';
```

Individual modules are importable as
`package:marrionate_extended_mcp/src/<module>/<file>.dart` if you need
something the barrel file hides to avoid name clashes.

### Command-line entry points

The package ships these executables (`bin/`):

```bash
dart run marrionate_extended_mcp:marionette_mcp   # MCP server (stdio)
dart run marrionate_extended_mcp:replay           # scenario replay CLI
dart run marrionate_extended_mcp:marionette       # marionette CLI
dart run marrionate_extended_mcp:server           # flutter-skill server
dart run marrionate_extended_mcp:flutter_skill    # flutter-skill CLI
```

Wire the MCP server into an agent (stdio transport by default; pass
`--sse-port N` for SSE):

```json
{
  "mcpServers": {
    "marrionate-extended-mcp": {
      "command": "dart",
      "args": ["run", "marrionate_extended_mcp:marionette_mcp"]
    }
  }
}
```

Replay recorded scenarios from the command line:

```bash
dart run marrionate_extended_mcp:replay --scenarios path/to/scenarios --format text
# --stop-on-failure, --list-only, --format {text,json,junit}
```

## Platform behaviour

Marionette registers `ext.flutter.marionette.*` service extensions and
flutter-skill registers `ext.flutter.flutter_skill.*`. Both are reached over the
Dart VM service, **which does not exist in a browser**.

| | Native (Windows/macOS/Linux/Android/iOS) | Web (Chrome) |
|---|---|---|
| Marionette tools | 18 available | withheld, `-32001` with an explanation |
| Flutter-skill tools | available | available via JS/CDP bridge |
| Transport | Dart VM service | `window.__FLUTTER_SKILL_DART_CALL__` + CDP |

`E2eBinding.ensureInitialized` installs the right transport for the target, and
`E2eCapability` reports what works so callers fail fast instead of hanging.

## The ValueKey rule

Anything a tool can interact with, or an assertion can observe, carries a stable
`ValueKey<String>`. Scenarios target keys exclusively — never text or
coordinates — so a copy change cannot silently break a test.

The `e2e_key_generator` builder injects missing keys:

```bash
dart run build_runner build
```

## Development

```bash
dart analyze      # 0 issues
flutter test      # full suite
dart pub publish --dry-run
```

## License

MIT for first-party code. Vendored dependencies keep their upstream licenses —
MIT (flutter-skill) and Apache-2.0 (marionette\_\*). See [NOTICE.md](NOTICE.md).

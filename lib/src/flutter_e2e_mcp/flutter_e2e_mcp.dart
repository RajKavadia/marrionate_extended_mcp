/// Unified MCP server for Flutter e2e automation.
///
/// Exposes marionette and flutter-skill tooling plus JSON-only scenario replay
/// behind one capability-aware interface.
library;

export 'src/cli/server.dart';
export 'src/drivers/driver_factory.dart';
export 'src/drivers/flutter_skill_driver.dart';
export 'src/drivers/live_driver.dart';
export 'src/drivers/marionette_driver.dart';
export 'src/replay/batch_executor.dart';
export 'src/replay/scenario_replayer.dart';
export 'src/report/report_formatter.dart';
export 'src/server/live_tools.dart';
export 'src/server/tool_registry.dart';
export 'src/server/unified_mcp_server.dart';

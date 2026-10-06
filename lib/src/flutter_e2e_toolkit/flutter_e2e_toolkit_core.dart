/// Scenario model, validator, key registry, recorder, and platform reporting for
/// Flutter e2e automation.
///
/// This library is deliberately free of Flutter and `dart:ui` imports so it can
/// be consumed from a plain Dart VM. The MCP server runs there (it has no
/// Flutter engine), and importing anything that pulls in `dart:ui` would make
/// the server unloadable.
///
/// App-side code that also needs the widget bindings should import
/// `package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit.dart` instead, which
/// re-exports everything here plus [E2eBinding].
///
/// ```dart
/// if (!kReleaseMode) {
///   E2eBinding.ensureInitialized(const E2eConfig(verbose: true));
/// }
/// runApp(const MyApp());
/// ```
library;

export 'src/capability/e2e_capability.dart';
export 'src/mcp/mcp_scenario_export.dart';
export 'src/keys/key_registry.dart';
export 'src/logging/e2e_log_store.dart';
export 'src/platform/e2e_platform.dart';
export 'src/recording/interaction_recorder.dart';
export 'src/recording/step_recorder.dart';
export 'src/scenario/e2e_scenario.dart';
export 'src/scenario/scenario_validator.dart';

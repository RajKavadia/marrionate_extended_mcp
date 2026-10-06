import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

import '../drivers/driver_factory.dart';
import '../drivers/live_driver.dart';
import '../replay/batch_executor.dart';
import '../server/live_tools.dart';
import '../server/tool_registry.dart';
import '../server/unified_mcp_server.dart';

/// Parsed command-line options.
class ServeOptions {
  const ServeOptions({
    this.scenariosPath,
    this.prefixPolicy = ToolPrefixPolicy.namespaced,
    this.verbose = false,
    this.listTools = false,
    this.connectTarget,
    this.connectKind,
  });

  /// Directory containing `.json` scenarios.
  final String? scenariosPath;

  final ToolPrefixPolicy prefixPolicy;
  final bool verbose;

  /// Print the tool catalogue and exit.
  final bool listTools;

  /// Target to attach to at startup.
  final String? connectTarget;

  /// Transport override for [connectTarget].
  final String? connectKind;
}

/// Parses [args] for the `serve` command.
ServeOptions parseServeArgs(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'scenarios',
      abbr: 's',
      help: 'Directory containing JSON scenario files.',
    )
    ..addOption(
      'prefix',
      allowed: ['namespaced', 'namespacedOnly', 'flat'],
      defaultsTo: 'namespaced',
      help: 'How tool names are presented.',
    )
    ..addOption(
      'connect',
      abbr: 'c',
      help: 'Attach to this target at startup: a Dart VM service URI '
          '(ws://127.0.0.1:PORT/TOKEN=/ws) or a page URL.',
    )
    ..addOption(
      'kind',
      allowed: ['vmService', 'webPage', 'cdp'],
      help: 'Override transport inference for --connect.',
    )
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Log to stderr.')
    ..addFlag('list-tools', negatable: false, help: 'Print tools and exit.');

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    throw FormatException('${e.message}\n\n${parser.usage}');
  }

  final policyName = results.option('prefix')!;
  ToolPrefixPolicy? policy;
  for (final candidate in ToolPrefixPolicy.values) {
    if (candidate.name == policyName) {
      policy = candidate;
      break;
    }
  }
  if (policy == null) {
    throw FormatException(
      'Unknown --prefix "$policyName". '
      'Allowed: ${ToolPrefixPolicy.values.map((p) => p.name).join(", ")}.\n\n'
      '${parser.usage}',
    );
  }
  return ServeOptions(
    scenariosPath: results.option('scenarios'),
    prefixPolicy: policy,
    verbose: results.flag('verbose'),
    listTools: results.flag('list-tools'),
    connectTarget: results.option('connect'),
    connectKind: results.option('kind'),
  );
}

/// Entry point for the `serve` subcommand.
///
/// Wires the registry and executor, registers the built-in tools and both live
/// tool sets, optionally attaches to an app, and serves MCP over stdio.
Future<void> runServe(List<String> args) async {
  final options = parseServeArgs(args);
  final log = options.verbose
      ? (String m) => stderr.writeln('[flutter-e2e-mcp] $m')
      : (String _) {};

  final registry = ToolRegistry();
  // Marionette is registered first so it claims the flat aliases; a bare `tap`
  // therefore means marionette, and flutter-skill is reached via `skill_`.
  registerAllLiveTools(registry);

  final executor = BatchExecutor(registry: registry);
  final server = UnifiedMcpServer(
    registry: registry,
    executor: executor,
    prefixPolicy: options.prefixPolicy,
  )..registerBuiltinTools(scenariosPath: options.scenariosPath);

  // Lets execute_batch and replay_scenario drive the same app tools/call does.
  executor.attachSessionProvider(() => server.session);

  log('tool policy: ${options.prefixPolicy.name}');
  log('registered ${registry.length} tools '
      '(${registry.list(source: ToolSource.marionette).length} marionette, '
      '${registry.list(source: ToolSource.flutterSkill).length} flutter-skill)');
  if (options.scenariosPath != null) {
    log('scenarios: ${options.scenariosPath}');
  }

  if (options.listTools) {
    for (final tool in registry.list()) {
      stdout.writeln('${tool.source.name.padRight(12)} ${tool.wireName}');
    }
    return;
  }

  final target = options.connectTarget;
  if (target != null && target.isNotEmpty) {
    DriverKind? kind;
    for (final candidate in DriverKind.values) {
      if (candidate.name == options.connectKind) kind = candidate;
    }
    try {
      final session = await server.driverFactory.connect(target, kind: kind);
      await server.adoptSession(session);
      log('connected: ${session.kind.name} -> ${session.target}');
    } on DriverException catch (e) {
      // Not fatal: the server is still useful for validation and replay
      // reporting, and connect_app can retry later.
      stderr.writeln('[flutter-e2e-mcp] could not attach to $target: $e');
    }
  }

  await server.serveStdio();
}

/// Entry point for the package binary.
Future<void> runServer(List<String> args) async {
  if (args.isEmpty || args.first == 'serve') {
    final rest = args.isEmpty ? <String>[] : args.sublist(1);
    await runServe(rest);
    return;
  }

  if (args.first == 'version' || args.first == '--version') {
    stdout.writeln('flutter-e2e-mcp 0.1.0');
    return;
  }

  stderr.writeln('usage: flutter-e2e-mcp [serve] [options]\n');
  stderr.writeln('  serve              Serve MCP over stdio (default).');
  stderr.writeln('  -s, --scenarios    Directory of JSON scenarios.');
  stderr.writeln('  -c, --connect      Attach to a VM service URI or page URL.');
  stderr.writeln('      --kind         vmService | webPage | cdp');
  stderr.writeln('      --prefix      namespaced | namespacedOnly | flat');
  stderr.writeln('      --list-tools  Print the tool catalogue and exit.');
  stderr.writeln('  -v, --verbose      Log to stderr.');
  stderr.writeln('  version            Print the version.');
  exitCode = 64; // EX_USAGE
}

import 'dart:io';

import 'package:args/args.dart';
import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';
import 'package:marrionate_extended_mcp/src/flutter_e2e_mcp/flutter_e2e_mcp.dart';

/// Replays scenario files and prints a report.
///
/// A standalone counterpart to the MCP `replay_scenario` tool, so the same
/// replay logic is reachable from CI without an MCP client.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'scenarios',
      abbr: 's',
      help: 'Directory of JSON scenario files.',
      defaultsTo: 'e2e/scenarios',
    )
    ..addOption(
      'format',
      abbr: 'f',
      allowed: ['text', 'json', 'junit'],
      defaultsTo: 'text',
      help: 'Report format.',
    )
    ..addFlag(
      'stop-on-failure',
      negatable: false,
      help: 'Halt at the first failing scenario.',
    )
    ..addFlag(
      'list-only',
      negatable: false,
      help: 'Validate and list scenarios without executing them.',
    );

  final ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(64);
  }

  final format = ReportFormat.values.firstWhere(
    (f) => f.name == options.option('format'),
    orElse: () => ReportFormat.text,
  );

  final registry = ToolRegistry();
  final executor = BatchExecutor(registry: registry);
  final replayer = ScenarioReplayer(executor: executor);

  final dir = Directory(options.option('scenarios')!);

  if (options.flag('list-only')) {
    // Validation-only mode: proves a scenario set is well-formed without
    // needing a live app, which is what CI can run on every commit.
    final loaded = E2eScenario.loadDirectorySafe(dir);
    for (final problem in loaded.skipped) {
      stderr.writeln('unparseable: $problem');
    }
    stdout.writeln('${loaded.scenarios.length} scenario(s) in ${dir.path}:');
    for (final scenario in loaded.scenarios) {
      stdout.writeln('  ${scenario.name}  (${scenario.commands.length} steps)');
    }
    if (loaded.skipped.isNotEmpty) exit(2);
    return;
  }

  final report = await replayer.replayDirectory(
    dir,
    stopOnFailure: options.flag('stop-on-failure'),
  );

  stdout.writeln(ReportFormatter.render(report, format));

  if (!report.allPassed) {
    stderr.writeln('\n${report.failed} scenario(s) failed.');
    exit(1);
  }
}

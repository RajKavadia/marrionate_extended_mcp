// Validates every scenario in e2e/scenarios against the action vocabulary and
// KeyRegistry, without needing a running app.
//
// Catches the class of mistake that otherwise only surfaces mid-run: a typo in a
// key, a missing required argument, or an unsupported action.
//
// Usage:
//   dart run tool/validate_scenarios.dart
//   dart run tool/validate_scenarios.dart <dir>
import 'dart:io';

import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';

Future<void> main(List<String> args) async {
  final scriptDir = File.fromUri(Platform.script).parent;
  final repoRoot = Directory('${scriptDir.path}${Platform.pathSeparator}..');

  final dir = args.isEmpty
      ? Directory('${repoRoot.path}${Platform.pathSeparator}e2e'
          '${Platform.pathSeparator}scenarios')
      : Directory(args.first);

  if (!dir.existsSync()) {
    stderr.writeln('validate_scenarios: no such directory: ${dir.path}');
    exit(2);
  }

  final loaded = E2eScenario.loadDirectorySafe(dir);
  const validator = ScenarioValidator();

  var scenarioCount = 0;
  var stepCount = 0;
  var problemCount = 0;

  for (final problem in loaded.skipped) {
    stderr.writeln('UNPARSEABLE  $problem');
    problemCount++;
  }

  for (final scenario in loaded.scenarios) {
    scenarioCount++;
    final result = validator.validate(scenario);
    stepCount += scenario.commands.length;

    if (result.isValid) {
      final warnings = result.issues.length;
      stdout.writeln('OK      ${scenario.name}  '
          '(${scenario.commands.length} steps'
          '${warnings > 0 ? ', $warnings warning(s)' : ''})');
      for (final issue in result.issues) {
        stdout.writeln('          warn: ${issue.message}');
      }
    } else {
      problemCount++;
      stderr.writeln('INVALID  ${scenario.name}');
      for (final issue in result.issues) {
        stderr.writeln('          ${issue.severity.name}: ${issue.message}');
      }
    }
  }

  stdout.writeln('\n$scenarioCount scenario(s), $stepCount step(s) checked.');
  if (problemCount > 0) {
    stderr.writeln('FAILED: $problemCount problem(s).');
    exit(1);
  }
  stdout.writeln('All scenarios valid.');
}

import 'dart:io';

import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';

import 'batch_executor.dart';

/// Outcome of replaying one scenario.
class ScenarioOutcome {
  const ScenarioOutcome({
    required this.name,
    required this.passed,
    this.result,
    this.error,
  });

  final String name;
  final bool passed;

  /// Present when the scenario actually executed.
  final BatchResult? result;

  /// Present when the scenario failed to load or validate.
  final String? error;

  /// The step that failed, or -1.
  int get failedStep => result?.failedStep ?? -1;

  Map<String, Object?> toJson() => {
        'name': name,
        'passed': passed,
        if (error != null) 'error': error,
        if (result != null) 'result': result!.toJson(),
      };
}

/// Aggregate outcome across scenarios.
class ReplayReport {
  const ReplayReport(this.scenarios);

  final List<ScenarioOutcome> scenarios;

  int get passed => scenarios.where((s) => s.passed).length;

  int get failed => scenarios.where((s) => !s.passed).length;

  bool get allPassed => failed == 0 && scenarios.isNotEmpty;

  /// Scenarios that failed, for terse CI output.
  List<ScenarioOutcome> get failures =>
      scenarios.where((s) => !s.passed).toList();

  int get totalSteps =>
      scenarios.fold(0, (sum, s) => sum + (s.result?.stepReports.length ?? 0));

  Map<String, Object?> toJson() => {
        'allPassed': allPassed,
        'total': scenarios.length,
        'passed': passed,
        'failed': failed,
        'totalSteps': totalSteps,
        'scenarios': scenarios.map((s) => s.toJson()).toList(),
      };

  @override
  String toString() => 'ReplayReport: $passed/${scenarios.length} scenarios '
      'passed, $totalSteps steps';
}

/// Replays scenario files through a [BatchExecutor].
class ScenarioReplayer {
  ScenarioReplayer({required this.executor});

  final BatchExecutor executor;

  /// Replays one scenario.
  Future<ScenarioOutcome> replay(E2eScenario scenario) async {
    final result = await executor.executeSteps(scenario.interpolate().commands);
    return ScenarioOutcome(
      name: scenario.name,
      passed: result.success,
      result: result,
      // Surface validation failures as a scenario-level error for readability.
      error: result.validationError
          ? 'validation failed:\n${result.validation!.issues.join("\n")}'
          : null,
    );
  }

  /// Replays several scenarios in order.
  ///
  /// With [stopOnFailure] the first failing scenario halts the run, so CI stops
  /// at the root cause instead of cascading.
  Future<ReplayReport> replayScenarios(
    List<E2eScenario> scenarios, {
    bool stopOnFailure = false,
  }) async {
    final outcomes = <ScenarioOutcome>[];
    for (final scenario in scenarios) {
      final outcome = await replay(scenario);
      outcomes.add(outcome);
      if (stopOnFailure && !outcome.passed) break;
    }
    return ReplayReport(outcomes);
  }

  /// Loads and replays every `.json` scenario in [dir].
  Future<ReplayReport> replayDirectory(Directory dir,
      {bool stopOnFailure = false}) async {
    if (!dir.existsSync()) {
      return ReplayReport([
        ScenarioOutcome(
          name: '<missing directory>',
          passed: false,
          error: 'scenario directory does not exist: ${dir.path}',
        ),
      ]);
    }

    final loaded = E2eScenario.loadDirectorySafe(dir);
    final scenarios = loaded.scenarios;

    // Unparseable files are reported as failures rather than dropped, so a
    // broken scenario can never look like a passing run.
    final outcomes = <ScenarioOutcome>[
      for (final problem in loaded.skipped)
        ScenarioOutcome(name: problem.split(':').first, passed: false, error: problem),
    ];

    if (scenarios.isEmpty) {
      outcomes.add(ScenarioOutcome(
        name: '<no scenarios>',
        passed: false,
        error: loaded.skipped.isEmpty
            ? 'no .json scenarios found in ${dir.path}'
            : 'no parseable scenarios in ${dir.path}',
      ));
      return ReplayReport(outcomes);
    }

    final run = await replayScenarios(scenarios, stopOnFailure: stopOnFailure);
    return ReplayReport([...outcomes, ...run.scenarios]);
  }

  /// Loads and replays specific files, in the order given.
  Future<ReplayReport> replayFiles(
    List<File> files, {
    bool stopOnFailure = false,
  }) async {
    final outcomes = <ScenarioOutcome>[];
    for (final file in files) {
      final String name = file.path;
      try {
        final scenario = E2eScenario.loadFile(file);
        outcomes.add(await replay(scenario));
      } on FormatException catch (e) {
        outcomes.add(ScenarioOutcome(name: name, passed: false, error: e.message));
      } on FileSystemException catch (e) {
        outcomes.add(
            ScenarioOutcome(name: name, passed: false, error: e.message));
      }
      if (stopOnFailure && outcomes.last.passed == false) break;
    }
    return ReplayReport(outcomes);
  }
}

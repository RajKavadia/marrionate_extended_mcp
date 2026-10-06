import 'dart:convert';
import 'dart:io';

import '../scenario/e2e_scenario.dart';

/// Result classification for an executed step.
enum StepOutcome {
  passed,
  failed,

  /// Not reached, because an earlier step failed and the run stopped.
  skipped,
}

/// Assertion-specific detail.
class AssertionOutcome {
  const AssertionOutcome({
    required this.passed,
    this.expected,
    this.actual,
    this.reason,
  });

  final bool passed;
  final String? expected;
  final String? actual;

  /// Why the assertion failed, when the tool supplied a reason.
  final String? reason;

  Map<String, Object?> toJson() => {
        'passed': passed,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
        if (reason != null) 'reason': reason,
      };
}

/// A step plus its execution result.
class RecordedStep {
  const RecordedStep({
    required this.step,
    required this.action,
    required this.args,
    required this.outcome,
    this.durationMs,
    this.error,
    this.assertion,
  });

  final int step;
  final String action;
  final Map<String, Object?> args;
  final StepOutcome outcome;
  final int? durationMs;
  final String? error;

  /// Present when the step was an assertion.
  final AssertionOutcome? assertion;

  Map<String, Object?> toJson() => {
        'step': step,
        'action': action,
        'args': args,
        'outcome': outcome.name,
        if (durationMs != null) 'durationMs': durationMs,
        if (error != null) 'error': error,
        if (assertion != null) 'assertion': assertion!.toJson(),
      };

  /// Converts back to an executable [E2eStep], dropping execution metadata.
  ///
  /// This is what makes a recording re-runnable: `toScenarioJson` emits a file
  /// the batch executor accepts.
  Map<String, Object?> toStepJson() => {
        'step': step,
        'action': action,
        'args': args,
      };
}

/// A completed execution of one scenario.
class E2eRecording {
  const E2eRecording({
    required this.scenarioName,
    required this.startedAt,
    required this.duration,
    required this.steps,
  });

  final String scenarioName;
  final DateTime startedAt;
  final Duration duration;
  final List<RecordedStep> steps;

  bool get passed => steps.every((s) => s.outcome == StepOutcome.passed);

  int get failedCount =>
      steps.where((s) => s.outcome == StepOutcome.failed).length;

  /// The first failing step number, or null when the run passed.
  int? get firstFailedStep {
    for (final s in steps) {
      if (s.outcome == StepOutcome.failed) return s.step;
    }
    return null;
  }

  /// Report-oriented JSON, including outcomes.
  Map<String, Object?> toJson() => {
        'scenarioName': scenarioName,
        'startedAt': startedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'passed': passed,
        'failedCount': failedCount,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  /// Re-runnable scenario JSON: the commands only, outcomes stripped.
  ///
  /// Round-trips through [E2eScenario.fromJson].
  Map<String, Object?> toScenarioJson() => {
        'name': scenarioName,
        'commands': steps
            .where((s) => s.outcome != StepOutcome.skipped)
            .map((s) => s.toStepJson())
            .toList(),
      };

  String encode({bool reRunnable = false}) => const JsonEncoder.withIndent('  ')
      .convert(reRunnable ? toScenarioJson() : toJson());

  @override
  String toString() =>
      'E2eRecording($scenarioName, ${steps.length} steps, '
      '${passed ? "passed" : "$failedCount failed"})';
}

/// Captures executed steps, including assertions.
///
/// The vendored recorder logs only interaction tools, so a recording cannot
/// reproduce the checks that made it meaningful. This recorder captures both,
/// which is what lets a run be replayed or diffed against a later one.
class StepRecorder {
  StepRecorder({this.scenarioName = 'untitled', this.outputPath});

  /// Name used in the emitted recording.
  final String scenarioName;

  /// When set, [stop] writes the recording here.
  final String? outputPath;

  final List<RecordedStep> _steps = [];
  DateTime? _startedAt;
  Stopwatch? _stopwatch;

  /// Whether [start] has been called and [stop] has not.
  bool get isRecording => _stopwatch != null;

  /// Steps captured so far.
  List<RecordedStep> get steps => List.unmodifiable(_steps);

  /// Begins a new recording, discarding any prior state.
  void start() {
    _steps.clear();
    _startedAt = DateTime.now();
    _stopwatch = Stopwatch()..start();
  }

  /// Records an interaction step.
  ///
  /// [duration] is omitted when unknown rather than guessed.
  void record(
    E2eStep step,
    StepOutcome outcome, {
    Duration? duration,
    String? error,
  }) {
    _add(RecordedStep(
      step: step.step,
      action: step.action,
      args: step.args,
      outcome: outcome,
      durationMs: duration?.inMilliseconds,
      error: error,
    ));
  }

  /// Records an assertion step.
  ///
  /// Separate from [record] because assertions carry expected/actual detail
  /// that interactions do not, and because upstream recording omits them.
  void recordAssertion(
    E2eStep step,
    AssertionOutcome outcome, {
    Duration? duration,
    String? error,
  }) {
    _add(RecordedStep(
      step: step.step,
      action: step.action,
      args: step.args,
      outcome: outcome.passed ? StepOutcome.passed : StepOutcome.failed,
      durationMs: duration?.inMilliseconds,
      error: error ?? outcome.reason,
      assertion: outcome,
    ));
  }

  /// Records a step that was never reached.
  void recordSkipped(E2eStep step) {
    _add(RecordedStep(
      step: step.step,
      action: step.action,
      args: step.args,
      outcome: StepOutcome.skipped,
    ));
  }

  /// Stops recording and returns the result.
  ///
  /// Writes to [outputPath] when configured; a write failure is reported rather
  /// than thrown so the run's outcome is not masked by an IO problem.
  E2eRecording stop() {
    final stopwatch = _stopwatch;
    final startedAt = _startedAt;
    if (stopwatch == null || startedAt == null) {
      throw StateError('StepRecorder.stop() called without start()');
    }
    stopwatch.stop();
    _stopwatch = null;

    final recording = E2eRecording(
      scenarioName: scenarioName,
      startedAt: startedAt,
      duration: stopwatch.elapsed,
      steps: List.unmodifiable(_steps),
    );

    final path = outputPath;
    if (path != null) {
      File(path).writeAsStringSync(recording.encode());
    }

    _startedAt = null;
    return recording;
  }

  void _add(RecordedStep step) {
    if (_stopwatch == null) {
      throw StateError(
        'StepRecorder.record() called without start(). Call start() before '
        'executing steps.',
      );
    }
    _steps.add(step);
  }
}

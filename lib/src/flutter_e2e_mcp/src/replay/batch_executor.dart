import 'dart:async';

import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';

import '../drivers/driver_factory.dart';
import '../report/report_formatter.dart';
import '../server/tool_registry.dart';

/// Result of one executed step.
class StepReport {
  const StepReport({
    required this.step,
    required this.action,
    required this.ok,
    required this.duration,
    this.error,
    this.actual,
    this.expected,
  });

  /// 1-based step number.
  final int step;

  /// Action that ran.
  final String action;

  /// Whether the step satisfied its assertion (or simply succeeded).
  final bool ok;

  final Duration duration;

  /// Failure detail for a failed step.
  final String? error;

  /// Observed value, for assertions.
  final String? actual;

  /// Required value, for assertions.
  final String? expected;

  /// One-line description used in text reports.
  String get summary {
    final head = ok ? 'PASS' : 'FAIL';
    final detail = ok ? '' : ' -- ${error ?? 'assertion failed'}';
    return '$head  step $step  $action$detail';
  }

  Map<String, Object?> toJson() => {
        'step': step,
        'action': action,
        'ok': ok,
        'durationMs': duration.inMilliseconds,
        if (error != null) 'error': error,
        if (actual != null) 'actual': actual,
        if (expected != null) 'expected': expected,
      };
}

/// Aggregate result of a batch.
class BatchResult {
  BatchResult({
    required this.stepReports,
    required this.stoppedEarly,
    this.validation,
  });

  /// Builds a result from a list of step reports.
  factory BatchResult.fromReports(
    List<StepReport> reports, {
    bool stoppedEarly = false,
    ValidationResult? validation,
  }) {
    return BatchResult(
      stepReports: reports,
      stoppedEarly: stoppedEarly,
      validation: validation,
    );
  }

  final List<StepReport> stepReports;

  /// Whether execution halted before running every step.
  final bool stoppedEarly;

  /// Validation findings, when the scenario was validated first.
  final ValidationResult? validation;

  /// Every step succeeded.
  bool get success =>
      !validationError && stepReports.every((r) => r.ok) && stepReports.isNotEmpty;

  /// Validation rejected the scenario before execution.
  bool get validationError => validation?.hasErrors ?? false;

  /// 1-based number of the first failing step, or -1 when all passed.
  int get failedStep {
    for (final r in stepReports) {
      if (!r.ok) return r.step;
    }
    return -1;
  }

  int get passedCount => stepReports.where((r) => r.ok).length;

  int get failedCount => stepReports.where((r) => !r.ok).length;

  /// The failing step's report, if any.
  StepReport? get firstFailure {
    for (final r in stepReports) {
      if (!r.ok) return r;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'success': success,
        'failedStep': failedStep,
        'stoppedEarly': stoppedEarly,
        'passedCount': passedCount,
        'failedCount': failedCount,
        if (validation != null && validation!.issues.isNotEmpty)
          'validationIssues':
              validation!.issues.map((i) => i.toString()).toList(),
        'stepReports': stepReports.map((r) => r.toJson()).toList(),
      };

  @override
  String toString() => success
      ? 'BatchResult: all ${stepReports.length} steps passed'
      : 'BatchResult: failed at step $failedStep '
          '(${failedCount} failed, $passedCount passed)';
}

/// Runs a list of steps through a [ToolRegistry].
///
/// Mirrors the vendored `execute_batch` contract so scenarios written for
/// either upstream run here unchanged: the step list is read from `actions` or
/// `commands`, per-step arguments may be inline or nested under `args`, and
/// `stop_on_failure` plus `step_delay_ms` are honoured.
///
/// It additionally accepts `assert_text_contains`, which the vendored executor
/// rejects in its dispatch switch because it only reads text out of editable
/// fields. That makes plain `Text` widgets observable.
class BatchExecutor {
  BatchExecutor({
    required this.registry,
    ToolContext? context,
    ScenarioValidator validator = const ScenarioValidator(),
    this.validateFirst = true,
  })  : validator = validator,
        context = context ?? const ToolContext(recorder: null);

  final ToolRegistry registry;

  /// Ambient state handed to each handler.
  final ToolContext context;

  final ScenarioValidator validator;

  /// Whether scenarios are validated before execution.
  final bool validateFirst;

  LiveSession? Function() _sessionProvider = _noSession;

  static LiveSession? _noSession() => null;

  /// Points the executor at the live session.
  ///
  /// Set by the server once it exists, so `execute_batch` and `replay_scenario`
  /// drive the same app that `tools/call` does. A provider rather than a value
  /// because the session is established after the executor is built.
  void attachSessionProvider(LiveSession? Function() provider) {
    _sessionProvider = provider;
  }

  /// The app currently attached, if any.
  ///
  /// Read through a provider rather than captured once, because a session can be
  /// established or replaced between two calls to [execute].
  LiveSession? get session => _sessionProvider();

  /// MCP-shaped entry point: `{"actions": [...]}` or `{"commands": [...]}`.
  Future<Map<String, Object?>> execute(Map<String, Object?> args) async {
    final rawSteps = args['actions'] ?? args['commands'] ?? args['steps'];
    if (rawSteps is! List) {
      return {
        'success': false,
        'error': 'expected "actions" or "commands" to be an array of steps',
      };
    }

    final steps = <E2eStep>[];
    for (var i = 0; i < rawSteps.length; i++) {
      final entry = rawSteps[i];
      if (entry is! Map) {
        return {
          'success': false,
          'error': 'step ${i + 1} is not an object',
        };
      }
      try {
        steps.add(
            E2eStep.fromJson(Map<String, Object?>.from(entry)).withStep(i + 1));
      } on FormatException catch (e) {
        return {'success': false, 'error': 'step ${i + 1}: ${e.message}'};
      }
    }

    // Per-invocation overrides of the ambient context.
    final effective = ToolContext(
      recorder: context.recorder,
      stopOnFailure: args['stop_on_failure'] as bool? ?? context.stopOnFailure,
      stepDelayMs: args['step_delay_ms'] as int? ?? context.stepDelayMs,
      platform: context.platform,
      session: context.session,
    );

    final result = await executeSteps(steps, overrideContext: effective);
    return result.toJson();
  }

  /// Executes already-parsed steps.
  Future<BatchResult> executeSteps(
    List<E2eStep> steps, {
    ToolContext? overrideContext,
  }) async {
    final ctx = (overrideContext ?? context).withSession(_sessionProvider());

    if (validateFirst) {
      final scenario = E2eScenario(name: 'batch', commands: steps);
      final validation = validator.validate(scenario);
      if (validation.hasErrors) {
        // Report and execute nothing: a malformed scenario should not half-run.
        return BatchResult.fromReports(
          const [],
          stoppedEarly: false,
          validation: validation,
        );
      }
    }

    final reports = <StepReport>[];
    var stoppedEarly = false;

    for (final step in steps) {
      if (stoppedEarly) {
        reports.add(StepReport(
          step: step.step,
          action: step.action,
          ok: false,
          duration: Duration.zero,
          error: 'skipped: an earlier step failed',
        ));
        continue;
      }

      final report = await _runStep(step, ctx);
      reports.add(report);

      if (!report.ok && ctx.stopOnFailure) {
        stoppedEarly = true;
      }
      if (ctx.stepDelayMs > 0 && !stoppedEarly) {
        await Future<void>.delayed(Duration(milliseconds: ctx.stepDelayMs));
      }
    }

    return BatchResult.fromReports(reports, stoppedEarly: stoppedEarly);
  }

  Future<StepReport> _runStep(E2eStep step, ToolContext ctx) async {
    final tool = registry.resolve(step.action);
    if (tool == null) {
      return StepReport(
        step: step.step,
        action: step.action,
        ok: false,
        duration: Duration.zero,
        error: 'unknown action "${step.action}". Known: '
            '${registry.allCallableNames.join(", ")}',
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final result = await tool.handler(step.args, ctx);
      stopwatch.stop();

      // A handler signals failure either by ok:false or by throwing.
      final ok = result['ok'] != false && result['success'] != false;
      return StepReport(
        step: step.step,
        action: step.action,
        ok: ok,
        duration: stopwatch.elapsed,
        error: ok ? null : (result['error']?.toString() ?? 'step reported failure'),
        actual: result['actual']?.toString(),
        expected: result['expected']?.toString(),
      );
    } on ToolCapabilityException catch (e) {
      stopwatch.stop();
      return StepReport(
        step: step.step,
        action: step.action,
        ok: false,
        duration: stopwatch.elapsed,
        error: e.message,
      );
    } catch (e) {
      stopwatch.stop();
      return StepReport(
        step: step.step,
        action: step.action,
        ok: false,
        duration: stopwatch.elapsed,
        error: e.toString(),
      );
    }
  }
}

/// Raised when a tool cannot run on the connected platform.
///
/// Carries a message that names the working alternative, so a web caller gets
/// guidance instead of an opaque timeout.
class ToolCapabilityException implements Exception {
  ToolCapabilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Renders a [BatchResult] as human-readable text.
String formatBatchText(BatchResult result) =>
    ReportFormatter.batchToText(result);

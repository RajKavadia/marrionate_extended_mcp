import '../keys/key_registry.dart';
import 'e2e_scenario.dart';

/// Severity of a validation finding.
enum Severity {
  /// The scenario cannot run correctly.
  error,

  /// The scenario runs but violates a project convention.
  warning,
}

/// One validation finding.
class ValidationIssue {
  const ValidationIssue({
    required this.step,
    required this.action,
    required this.severity,
    required this.message,
  });

  /// 1-based step number, or 0 for scenario-level findings.
  final int step;

  /// Action the finding relates to.
  final String action;

  final Severity severity;
  final String message;

  @override
  String toString() =>
      '${severity.name}: step $step ($action): $message';
}

/// Outcome of validating a scenario.
class ValidationResult {
  const ValidationResult(this.issues);

  final List<ValidationIssue> issues;

  bool get isValid => !hasErrors;

  bool get hasErrors => issues.any((i) => i.severity == Severity.error);

  /// Errors only, for terse output.
  List<ValidationIssue> get errors =>
      issues.where((i) => i.severity == Severity.error).toList();

  @override
  String toString() => issues.isEmpty
      ? 'valid'
      : issues.map((i) => i.toString()).join('\n');
}

/// Checks scenarios against the supported action vocabulary and [KeyRegistry].
///
/// Runs before execution so a malformed scenario fails immediately with a
/// precise message instead of surfacing as an opaque tool error mid-run.
class ScenarioValidator {
  const ScenarioValidator({this.enforceKnownKeys = true});

  /// Whether a key absent from [KeyRegistry] is an error.
  final bool enforceKnownKeys;

  /// Actions the batch executor can run.
  static const Set<String> supportedActions = {
    // interaction
    'tap',
    'enter_text',
    'scroll',
    'swipe',
    'long_press',
    'double_tap',
    'secondary_tap',
    'pinch_zoom',
    'go_back',
    'press_key',
    'wait',
    'screenshot',
    'hot_reload',
    'hot_restart',
    // assertions
    'assert_visible',
    'assert_not_visible',
    'assert_text',
    'assert_text_contains',
    'assert_element_count',
    'assert_enabled',
    'assert_batch',
    // meta
    'execute_batch',
  };

  /// Actions that must resolve to a known key.
  static const Set<String> keyTargetedActions = {
    'tap',
    'long_press',
    'double_tap',
    'secondary_tap',
    'pinch_zoom',
    'swipe',
    'enter_text',
    'scroll_to',
    'assert_visible',
    'assert_not_visible',
    'assert_text',
    'assert_text_contains',
    'assert_enabled',
    'screenshot',
  };

  /// Required argument names per action.
  static const Map<String, List<String>> requiredArgs = {
    'enter_text': ['text'],
    'pinch_zoom': ['scale'],
    'swipe': ['direction'],
    'assert_visible': ['key'],
    'assert_not_visible': ['key'],
    'assert_text': ['key', 'text'],
    'assert_text_contains': ['key', 'text'],
    'assert_element_count': ['count'],
    'assert_enabled': ['key'],
    'wait': [],
    'screenshot': [],
    'go_back': [],
  };

  /// Actions that are assertions rather than interactions.
  static bool isAssertion(String action) => action.startsWith('assert_');

  /// Validates [scenario], returning every finding rather than stopping at the
  /// first so one pass reports all problems.
  ValidationResult validate(E2eScenario scenario) {
    final issues = <ValidationIssue>[];

    if (scenario.commands.isEmpty) {
      issues.add(const ValidationIssue(
        step: 0,
        action: '',
        severity: Severity.error,
        message: 'scenario has no commands',
      ));
    }

    final seenSteps = <int>{};
    for (final step in scenario.commands) {
      issues.addAll(validateStep(step));
      if (!seenSteps.add(step.step)) {
        issues.add(ValidationIssue(
          step: step.step,
          action: step.action,
          severity: Severity.error,
          message: 'duplicate step number ${step.step}',
        ));
      }
    }

    return ValidationResult(issues);
  }

  /// Validates a single step.
  List<ValidationIssue> validateStep(E2eStep step) {
    final issues = <ValidationIssue>[];

    if (!supportedActions.contains(step.action)) {
      issues.add(ValidationIssue(
        step: step.step,
        action: step.action,
        severity: Severity.error,
        message: 'unsupported action. Supported: '
            '${(supportedActions.toList()..sort()).join(", ")}',
      ));
      // Argument checks below would be noise for an unknown action.
      return issues;
    }

    // Required arguments.
    for (final required in requiredArgs[step.action] ?? const <String>[]) {
      final value = step.args[required];
      if (value == null || (value is String && value.isEmpty)) {
        issues.add(ValidationIssue(
          step: step.step,
          action: step.action,
          severity: Severity.error,
          message: 'missing required argument "$required"',
        ));
      }
    }

    // `tap` needs some way to identify a target.
    if (step.action == 'tap') {
      final hasTarget = step.args['key'] != null ||
          step.args['text'] != null ||
          (step.args['x'] != null && step.args['y'] != null);
      if (!hasTarget) {
        issues.add(ValidationIssue(
          step: step.step,
          action: step.action,
          severity: Severity.error,
          message: 'tap needs "key" (preferred), "text", or both "x" and "y". '
              'Scenarios must target ValueKeys, not coordinates.',
        ));
      }
    }

    // `assert_element_count` needs a numeric count.
    if (step.action == 'assert_element_count') {
      final count = step.args['count'];
      if (count != null && count is! int) {
        issues.add(ValidationIssue(
          step: step.step,
          action: step.action,
          severity: Severity.error,
          message: '"count" must be an integer, got ${count.runtimeType}',
        ));
      }
    }

    // Key registry conformance.
    if (enforceKnownKeys && keyTargetedActions.contains(step.action)) {
      final key = step.args['key'];
      if (key is String && key.isNotEmpty && !KeyRegistry.isKnown(key)) {
        issues.add(ValidationIssue(
          step: step.step,
          action: step.action,
          severity: Severity.error,
          message: 'key "$key" is not in KeyRegistry. Add it to '
              'KeyRegistry.requiredKeys and give the widget a matching '
              'ValueKey<String>, or the scenario cannot target it reliably.',
        ));
      }
    }

    // Coordinate targeting is discouraged but legal.
    if (step.args.containsKey('x') || step.args.containsKey('y')) {
      issues.add(ValidationIssue(
        step: step.step,
        action: step.action,
        severity: Severity.warning,
        message: 'coordinate targeting is layout-dependent; prefer a ValueKey',
      ));
    }

    return issues;
  }
}

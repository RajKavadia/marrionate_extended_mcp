import '../scenario/e2e_scenario.dart';

/// Keys that must never appear in exported scenarios (recorder chrome itself).
const Set<String> kE2eRecorderExcludedKeys = {
  'e2e_recorder_fab',
  'e2e_recorder_panel',
};

/// Called with the full session after each change.
///
/// [snapshot] is `{scenario, recording, steps}`. Listeners must not throw
/// into the recorder; a live-session publisher is one listener.
typedef InteractionRecorderListener = void Function(
  Map<String, Object?> snapshot,
);

/// Captures user-driven steps as [E2eStep]s for scenario / MCP export.
class InteractionRecorder {
  InteractionRecorder({String scenarioName = 'recorded_session'})
      : _scenarioName = scenarioName;

  String _scenarioName;

  bool _active = false;
  final List<E2eStep> _steps = [];
  final List<InteractionRecorderListener> _listeners = [];
  String? _lastTapKey;
  DateTime? _lastTapAt;

  bool get isRecording => _active;

  List<E2eStep> get steps => List.unmodifiable(_steps);

  /// Latest session, including an empty one before [start].
  Map<String, Object?> get snapshot => {
        'scenario': _scenarioName,
        'recording': _active,
        'steps': [for (final step in _steps) step.toJson()],
      };

  void addListener(InteractionRecorderListener listener) {
    _listeners.add(listener);
  }

  void removeListener(InteractionRecorderListener listener) {
    _listeners.remove(listener);
  }

  void start({String? name}) {
    _steps.clear();
    _active = true;
    _lastTapKey = null;
    _lastTapAt = null;
    if (name != null && name.isNotEmpty) {
      _scenarioName = name;
    }
    _emit();
  }

  void stop() {
    _active = false;
    _emit();
  }

  /// Records a tap on [key] unless excluded or duplicated within [debounce].
  ///
  /// A second call inside [debounce] is dropped. A real double-tap is recorded
  /// with [recordDoubleTap], which upgrades the preceding tap.
  void recordTap(String key, {Duration debounce = const Duration(milliseconds: 400)}) {
    if (!_active) return;
    if (kE2eRecorderExcludedKeys.contains(key)) return;

    final now = DateTime.now();
    if (_lastTapKey == key &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < debounce) {
      return;
    }
    _lastTapKey = key;
    _lastTapAt = now;

    _append(E2eStep(
      step: _steps.length + 1,
      action: 'tap',
      args: {'key': key},
    ));
  }

  /// Upgrades the preceding tap on [key] into a Marionette `double_tap`.
  void recordDoubleTap(String key) {
    if (!_accept(key)) return;
    if (_steps.isNotEmpty) {
      final last = _steps.last;
      if (last.action == 'tap' && last.args['key'] == key) {
        _steps[_steps.length - 1] = E2eStep(
          step: last.step,
          action: 'double_tap',
          args: {'key': key},
        );
        _emit();
        return;
      }
    }
    _append(E2eStep(
      step: _steps.length + 1,
      action: 'double_tap',
      args: {'key': key},
    ));
  }

  /// Records a desktop secondary click (`mcp_secondary_tap`).
  void recordSecondaryTap(String key) {
    if (!_accept(key)) return;
    _append(E2eStep(
      step: _steps.length + 1,
      action: 'secondary_tap',
      args: {'key': key},
    ));
  }

  /// Records a long press (`mcp_long_press`).
  void recordLongPress(String key, {int? durationMs}) {
    if (!_accept(key)) return;
    _append(E2eStep(
      step: _steps.length + 1,
      action: 'long_press',
      args: {
        'key': key,
        if (durationMs != null) 'duration_ms': durationMs,
      },
    ));
  }

  /// Records an element swipe (`mcp_swipe`).
  ///
  /// [direction] is `left`, `right`, `up`, or `down`. [distance] is pixels.
  void recordSwipe(String key, String direction, {int? distance}) {
    if (!_accept(key)) return;
    _append(E2eStep(
      step: _steps.length + 1,
      action: 'swipe',
      args: {
        'key': key,
        'direction': direction,
        if (distance != null) 'distance': distance,
      },
    ));
  }

  /// Records a pinch (`mcp_pinch_zoom`). [scale] > 1 zooms in.
  void recordPinchZoom(String key, double scale) {
    if (!_accept(key)) return;
    if ((scale - 1).abs() < 0.05) return;
    _append(E2eStep(
      step: _steps.length + 1,
      action: 'pinch_zoom',
      args: {
        'key': key,
        'scale': double.parse(scale.toStringAsFixed(2)),
      },
    ));
  }

  /// Records [text] entry for [key] when it differs from the last recorded value.
  void recordEnterText(String key, String text) {
    if (!_active) return;
    if (kE2eRecorderExcludedKeys.contains(key)) return;
    if (text.isEmpty) return;

    final last = _steps.isNotEmpty ? _steps.last : null;
    if (last != null &&
        last.action == 'enter_text' &&
        last.args['key'] == key &&
        last.args['text'] == text) {
      return;
    }

    _append(E2eStep(
      step: _steps.length + 1,
      action: 'enter_text',
      args: {'key': key, 'text': text},
    ));
  }

  String get scenarioName => _scenarioName;

  E2eScenario toScenario({String? description}) {
    return E2eScenario(
      name: _scenarioName,
      description: description ??
          'Recorded interactively from the app (Marionette MCP export).',
      commands: List.unmodifiable(_steps),
    );
  }

  bool _accept(String key) {
    if (!_active) return false;
    if (kE2eRecorderExcludedKeys.contains(key)) return false;
    return true;
  }

  void _append(E2eStep step) {
    _steps.add(step);
    _emit();
  }

  void _emit() {
    if (_listeners.isEmpty) return;
    final current = snapshot;
    for (final listener in List<InteractionRecorderListener>.of(_listeners)) {
      try {
        listener(current);
      } catch (_) {}
    }
  }
}

import 'package:marrionate_extended_mcp/src/marionette_flutter/e2e_marionette_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'hit_test_keys.dart';
import 'interaction_recorder.dart';
import 'live_session_publisher.dart';

/// Provides an [InteractionRecorder] and listens for taps / text while recording.
///
/// Pointers are classified into Marionette actions: `tap`, `double_tap`,
/// `secondary_tap`, `long_press`, `swipe`, and `pinch_zoom`. A gesture is
/// stored only when the widget under the pointer actually handles it.
class E2eRecorderScope extends StatefulWidget {
  const E2eRecorderScope({
    super.key,
    required this.child,
    this.recorder,
    this.enabled = !kReleaseMode,
    this.autoStart = false,
    this.clock,
    this.liveSessionEndpoint,
    this.liveSessionProject,
  });

  final Widget child;

  /// When null, a default [InteractionRecorder] is created.
  final InteractionRecorder? recorder;

  /// When false, the scope is a pass-through (release builds).
  final bool enabled;

  /// If true, begins recording immediately upon mount.
  final bool autoStart;

  /// Clock for double-tap and long-press timing. Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// When set, each recording change is posted to the live-session service.
  final Uri? liveSessionEndpoint;

  /// Project name sent with each live-session snapshot.
  final String? liveSessionProject;

  static Uri? liveSessionUriOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_E2eRecorderInherited>();
    return scope?.liveSessionUri;
  }

  static InteractionRecorder of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_E2eRecorderInherited>();
    assert(scope != null, 'E2eRecorderScope not found above $context');
    return scope!.recorder;
  }

  static bool isRecording(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_E2eRecorderInherited>();
    return scope?.recorder.isRecording ?? false;
  }

  /// Commits text from the focused field before stopping a recording session.
  static void flushPendingInput(BuildContext context) {
    context
        .findAncestorStateOfType<_E2eRecorderScopeState>()
        ?._flushTextFromFocus(FocusManager.instance.primaryFocus);
  }

  @override
  State<E2eRecorderScope> createState() => _E2eRecorderScopeState();
}

class _PointerTrack {
  _PointerTrack({
    required this.down,
    required this.downAt,
    required this.buttons,
  });

  final Offset down;
  final DateTime downAt;
  final int buttons;
  Offset last = Offset.zero;
  double scale = 1;
}

class _E2eRecorderScopeState extends State<E2eRecorderScope> {
  late InteractionRecorder _recorder;
  LiveSessionPublisher? _publisher;
  FocusNode? _watchedFocus;
  String? _focusBaseline;
  final Map<int, _PointerTrack> _pointers = {};
  String? _lastTapKey;
  DateTime? _lastTapAt;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  /// Captures the frame after the gesture that was just recorded.
  Future<String?> _captureFrame() async {
    try {
      final binding = WidgetsBinding.instance;
      await _nextFrame(binding);
      binding.scheduleFrame();
      await _nextFrame(binding);
      final shots = await ScreenshotService(
        maxScreenshotSize: const Size(1100, 720),
      ).takeScreenshots();
      if (shots.isEmpty) return null;
      return shots.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _nextFrame(WidgetsBinding binding) {
    return binding.endOfFrame.timeout(
      const Duration(milliseconds: 400),
      onTimeout: () {},
    );
  }

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? InteractionRecorder();
    if (widget.enabled) {
      final endpoint = widget.liveSessionEndpoint;
      if (endpoint != null) {
        _publisher = LiveSessionPublisher(
          endpoint,
          project: widget.liveSessionProject ?? 'Untitled',
          captureFrame: _captureFrame,
        )..attach(_recorder);
      }
      FocusManager.instance.addListener(_onFocusChange);
      if (widget.autoStart) {
        _recorder.start();
      }
    }
  }

  @override
  void didUpdateWidget(covariant E2eRecorderScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recorder != null && widget.recorder != _recorder) {
      _recorder = widget.recorder!;
    }
  }

  @override
  void dispose() {
    _publisher?.detach();
    if (widget.enabled) {
      FocusManager.instance.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (!_recorder.isRecording || !mounted) return;

    final current = FocusManager.instance.primaryFocus;
    if (_watchedFocus != null && _watchedFocus != current) {
      _flushTextFromFocus(_watchedFocus);
    }
    _watchedFocus = current;
    _focusBaseline = textFromFocus(current);
  }

  void _flushTextFromFocus(FocusNode? focus) {
    if (!mounted) return;
    try {
      if (focusIsReadOnly(focus)) return;
      final key = valueKeyFromFocus(focus);
      if (key == null || kE2eRecorderExcludedKeys.contains(key)) return;
      final text = textFromFocus(focus);
      if (text == null || text == _focusBaseline) return;
      _recorder.recordEnterText(key, text);
      if (mounted) setState(() {});
    } catch (_) {
      // Safe fallback if the focus tree or element is in transition.
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = _PointerTrack(
      down: event.position,
      downAt: _now(),
      buttons: event.buttons,
    )..last = event.position;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final track = _pointers[event.pointer];
    if (track == null) return;
    track.last = event.position;
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _pointers[event.pointer] = _PointerTrack(
      down: event.position,
      downAt: _now(),
      buttons: 0,
    )..last = event.position;
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final track = _pointers[event.pointer];
    if (track == null) return;
    track.scale = event.scale;
    track.last = event.position;
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    final track = _pointers.remove(event.pointer);
    if (track == null || !_recorder.isRecording) return;
    final key = firstKeyWhere(
      keyedGesturesAt(track.down),
      (a) => a.scale,
    );
    if (key == null) return;
    _recorder.recordPinchZoom(key, track.scale);
    if (mounted) setState(() {});
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_recorder.isRecording || event is! PointerScrollEvent) return;
    final targets = keyedGesturesAt(event.position);
    if (HardwareKeyboard.instance.isControlPressed) {
      final key = firstKeyWhere(targets, (a) => a.scale);
      if (key == null) return;
      final scale = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
      _recorder.recordPinchZoom(key, scale);
      if (mounted) setState(() {});
      return;
    }
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    if (dx.abs() < 1 && dy.abs() < 1) return;
    final horizontal = dx.abs() > dy.abs();
    final key = firstKeyWhere(
      targets,
      (a) => horizontal ? a.horizontalDrag : a.verticalDrag,
    );
    if (key == null) return;
    // Wheel down moves content up, which Marionette replays as swipe up.
    final direction = horizontal
        ? (dx > 0 ? 'left' : 'right')
        : (dy > 0 ? 'up' : 'down');
    _recorder.recordSwipe(
      key,
      direction,
      distance: (horizontal ? dx.abs() : dy.abs()).round().clamp(1, 2000),
    );
    if (mounted) setState(() {});
  }

  void _handlePointerUp(PointerUpEvent event) {
    final track = _pointers.remove(event.pointer);
    if (!_recorder.isRecording || !mounted || track == null) return;
    try {
      final targets = keyedGesturesAt(track.down);
      final delta = track.last - track.down;
      final elapsed = _now().difference(track.downAt);
      final secondary = (track.buttons & kSecondaryButton) != 0;

      if (secondary) {
        final key = firstKeyWhere(targets, (a) => a.secondaryTap);
        if (key == null) return;
        _recorder.recordSecondaryTap(key);
      } else if (delta.distance > kTouchSlop) {
        final horizontal = delta.dx.abs() >= delta.dy.abs();
        final key = firstKeyWhere(
          targets,
          (a) => horizontal ? a.horizontalDrag : a.verticalDrag,
        );
        if (key == null) return;
        final direction = horizontal
            ? (delta.dx < 0 ? 'left' : 'right')
            : (delta.dy < 0 ? 'up' : 'down');
        _recorder.recordSwipe(
          key,
          direction,
          distance: delta.distance.round().clamp(1, 4000),
        );
      } else if (elapsed >= kLongPressTimeout) {
        final key = firstKeyWhere(targets, (a) => a.longPress) ??
            firstKeyWhere(targets, (a) => a.tap);
        if (key == null) return;
        if (firstKeyWhere(targets, (a) => a.longPress) != null) {
          _recorder.recordLongPress(key, durationMs: elapsed.inMilliseconds);
        } else {
          _recorder.recordTap(key);
        }
      } else {
        _recordTapLike(targets, _now());
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[e2e_recorder] tap error: $e');
      }
    }
  }

  void _recordTapLike(List<KeyedGestureTarget> targets, DateTime now) {
    final doubleKey = firstKeyWhere(targets, (a) => a.doubleTap);
    final tapKey = firstKeyWhere(targets, (a) => a.tap);
    final previous = _lastTapAt;
    final gap = previous == null ? null : now.difference(previous);
    final withinDouble = doubleKey != null &&
        _lastTapKey == doubleKey &&
        gap != null &&
        gap >= kDoubleTapMinTime &&
        gap <= kDoubleTapTimeout;

    if (withinDouble) {
      _recorder.recordDoubleTap(doubleKey);
      _lastTapKey = null;
      _lastTapAt = null;
      return;
    }

    if (gap != null &&
        gap < kDoubleTapMinTime &&
        _lastTapKey == (tapKey ?? doubleKey)) {
      return;
    }

    final key = tapKey;
    _lastTapKey = doubleKey ?? tapKey;
    _lastTapAt = now;
    if (key == null) return;
    _recorder.recordTap(key, debounce: Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return _E2eRecorderInherited(
      recorder: _recorder,
      liveSessionUri: widget.liveSessionEndpoint,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: (event) => _pointers.remove(event.pointer),
        onPointerPanZoomStart: _handlePointerPanZoomStart,
        onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
        onPointerPanZoomEnd: _handlePointerPanZoomEnd,
        onPointerSignal: _handlePointerSignal,
        child: widget.child,
      ),
    );
  }
}

class _E2eRecorderInherited extends InheritedWidget {
  const _E2eRecorderInherited({
    required this.recorder,
    required this.liveSessionUri,
    required super.child,
  });

  final InteractionRecorder recorder;
  final Uri? liveSessionUri;

  @override
  bool updateShouldNotify(_E2eRecorderInherited oldWidget) =>
      oldWidget.recorder.isRecording != recorder.isRecording ||
      oldWidget.recorder.steps.length != recorder.steps.length ||
      oldWidget.liveSessionUri != liveSessionUri;
}

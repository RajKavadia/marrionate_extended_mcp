import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'interaction_recorder.dart';

/// Posts recorder snapshots to the separate live-session service.
///
/// [endpoint] is the service origin, for example `http://127.0.0.1:8787`.
/// Snapshots are posted to `/session`. The Flutter app does not serve the
/// viewer. Failures are ignored so a stopped service cannot break recording.
class LiveSessionPublisher {
  LiveSessionPublisher(
    this.endpoint, {
    this.project = 'Untitled',
    this.captureFrame,
    Future<void> Function(Uri endpoint, String body)? post,
  }) : _post = post ?? _defaultPost;

  /// Origin of the live-session service. Open this in a browser to watch.
  static final Uri defaultEndpoint = Uri.parse('http://127.0.0.1:8787');

  final Uri endpoint;

  /// Project name stored with every session this app publishes.
  final String project;

  /// Returns a base64 PNG of the app after the latest step, or null.
  final Future<String?> Function()? captureFrame;

  final Future<void> Function(Uri endpoint, String body) _post;

  InteractionRecorder? _recorder;
  Future<void> _tail = Future<void>.value();
  final Map<int, String> _screenshots = {};
  String? _debugTarget;

  /// Completes when snapshots accepted so far have been posted.
  Future<void> get idle => _tail;

  void attach(InteractionRecorder recorder) {
    detach();
    _recorder = recorder;
    recorder.addListener(_onSnapshot);
  }

  void detach() {
    _recorder?.removeListener(_onSnapshot);
    _recorder = null;
  }

  void _onSnapshot(Map<String, Object?> snapshot) {
    final target = endpoint.replace(path: '/session');
    _tail = _tail.then((_) async {
      try {
        final payload = Map<String, Object?>.from(
          await _withScreenshots(snapshot),
        );
        payload['project'] = project;
        final vm = await _vmServiceUri();
        if (vm != null) payload['target'] = vm;
        await _post(target, jsonEncode(payload));
      } catch (_) {}
    });
  }

  Future<Map<String, Object?>> _withScreenshots(
    Map<String, Object?> snapshot,
  ) async {
    final rawSteps = snapshot['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      _screenshots.clear();
      return snapshot;
    }

    final steps = <Map<String, Object?>>[
      for (final step in rawSteps)
        if (step is Map) Map<String, Object?>.from(step),
    ];
    if (steps.isEmpty) return snapshot;

    final last = steps.last;
    final stepNo = last['step'];
    final capture = captureFrame;
    if (stepNo is int && capture != null) {
      final png = await capture();
      if (png != null && png.isNotEmpty) {
        _screenshots[stepNo] = png;
      }
    }

    final live = <int>{
      for (final step in steps)
        if (step['step'] is int) step['step'] as int,
    };
    _screenshots.removeWhere((step, _) => !live.contains(step));
    for (final step in steps) {
      final shot = _screenshots[step['step']];
      if (shot != null) step['screenshot'] = shot;
    }
    return {
      ...snapshot,
      'steps': steps,
    };
  }

  Future<String?> _vmServiceUri() async {
    if (_debugTarget != null) return _debugTarget;
    try {
      final info = await developer.Service.getInfo();
      final socket = info.serverWebSocketUri;
      if (socket != null) {
        _debugTarget = socket.toString();
      } else if (info.serverUri != null) {
        final httpUri = info.serverUri!;
        final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
        final path = httpUri.path.endsWith('/ws')
            ? httpUri.path
            : (httpUri.path.endsWith('/') ? '${httpUri.path}ws' : '${httpUri.path}/ws');
        _debugTarget = httpUri.replace(scheme: scheme, path: path).toString();
      }
    } catch (_) {}
    return _debugTarget;
  }
}

Future<void> _defaultPost(Uri endpoint, String body) {
  return http
      .post(
        endpoint,
        headers: const {'content-type': 'application/json'},
        body: body,
      )
      .timeout(const Duration(seconds: 15))
      .then((_) {});
}

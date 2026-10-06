import 'dart:convert';

import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/src/recording/interaction_recorder.dart';
import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/src/recording/live_session_publisher.dart';
import 'package:test/test.dart';

void main() {
  test('posts each snapshot to /session in order', () async {
    final bodies = <String>[];
    final publisher = LiveSessionPublisher(
      Uri.parse('http://127.0.0.1:8787'),
      post: (endpoint, body) async {
        expect(endpoint.path, '/session');
        bodies.add(body);
      },
    );
    final recorder = InteractionRecorder()..start();
    publisher.attach(recorder);
    recorder.recordTap('home_profile');
    recorder.recordEnterText('name_field', 'Raj');
    await publisher.idle;

    expect(bodies, hasLength(2));
    expect(bodies.first, contains('home_profile'));
    expect(bodies.last, contains('Raj'));
    expect(bodies.last, contains('home_profile'));
    publisher.detach();
  });

  test('keeps a screenshot on each step', () async {
    var shots = 0;
    final bodies = <String>[];
    final publisher = LiveSessionPublisher(
      Uri.parse('http://127.0.0.1:8787'),
      captureFrame: () async => 'png-${shots++}',
      post: (endpoint, body) async {
        bodies.add(body);
      },
    );
    final recorder = InteractionRecorder()..start();
    publisher.attach(recorder);
    recorder.recordTap('home_profile');
    await publisher.idle;
    recorder.recordEnterText('name_field', 'Raj');
    await publisher.idle;

    final first = jsonDecode(bodies.first) as Map;
    final second = jsonDecode(bodies.last) as Map;
    expect((first['steps'] as List).single['screenshot'], 'png-0');
    final steps = second['steps'] as List;
    expect(steps[0]['screenshot'], 'png-0');
    expect(steps[1]['screenshot'], 'png-1');
    publisher.detach();
  });
}

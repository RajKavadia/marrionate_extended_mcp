import 'dart:io';

import 'package:marrionate_extended_mcp/src/flutter_e2e_mcp/flutter_e2e_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MarionetteDriver', () {
    test('execute before connect throws DriverException', () async {
      final driver = MarionetteDriver();
      expect(driver.isConnected, isFalse);

      expect(
        () => driver.execute('tap', {'key': 'home_screen'}),
        throwsA(isA<DriverException>()),
      );
    });

    test('connect to unreachable target throws with actionable hint', () async {
      final driver = MarionetteDriver();
      await expectLater(
        driver.connect('ws://127.0.0.1:1/not-a-real-token=/ws'),
        throwsA(
          isA<DriverException>().having(
            (e) => e.hint,
            'hint',
            allOf(contains('flutter run'), contains('VM service')),
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('advertises marionette tool surface', () {
      final driver = MarionetteDriver();
      expect(driver.supportedTools, contains('tap'));
      expect(driver.supportedTools, contains('assert_text_contains'));
      expect(driver.kind, 'marionette');
    });
  });

  group('MarionetteDriver live VM', () {
    final uri = Platform.environment['E2E_VM_SERVICE_URI'];
    if (uri == null || uri.isEmpty) {
      test('skipped without E2E_VM_SERVICE_URI', () {}, skip: 'Set E2E_VM_SERVICE_URI to a running debug app.');
      return;
    }

    test('connects and lists interactive elements', () async {
      final driver = MarionetteDriver();
      final info = await driver.connect(uri);
      expect(info['ok'], isTrue);
      addTearDown(driver.disconnect);

      final result = await driver.execute('get_interactive_elements', {});
      expect(result['ok'], isTrue);
    });
  });
}

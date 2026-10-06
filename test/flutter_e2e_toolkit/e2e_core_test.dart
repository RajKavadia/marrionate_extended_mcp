import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit.dart';
import 'package:test/test.dart';

void main() {
  group('KeyRegistry', () {
    test('has no duplicate keys across screens', () {
      expect(KeyRegistry.assertComplete, returnsNormally);
    });

    test('every registered key resolves back to its screen', () {
      for (final screen in KeyRegistry.screens) {
        for (final key in KeyRegistry.keysForScreen(screen)) {
          expect(KeyRegistry.screenForKey(key), screen,
              reason: 'key "$key" should belong to "$screen"');
        }
      }
    });

    test('unknown keys are reported', () {
      expect(KeyRegistry.isKnown('submit_button'), isTrue);
      expect(KeyRegistry.isKnown('not_a_real_key'), isFalse);
      expect(KeyRegistry.unknownKeysIn(['submit_button', 'nope', 'also_nope']),
          {'nope', 'also_nope'});
    });

    test('includes the keys the plan requires', () {
      const expected = [
        'submit_button',
        'settings_notifications',
        'push_notifications_switch',
        'email_notifications_switch',
        'inapp_notifications_switch',
        'scale_text',
        'reset_zoom_button',
        'reset_secondary_button',
        'ds_tile_tappable',
        'ds_tile_static',
        'about_settings_button',
      ];
      for (final key in expected) {
        expect(KeyRegistry.isKnown(key), isTrue, reason: 'missing $key');
      }
    });
  });

  group('ScenarioValidator', () {
    const validator = ScenarioValidator();

    E2eScenario scenarioOf(List<Map<String, Object?>> commands) =>
        E2eScenario.fromJson({'name': 't', 'commands': commands});

    test('accepts a well-formed scenario', () {
      final result = validator.validate(scenarioOf([
        {'action': 'tap', 'key': 'submit_button'},
        {'action': 'assert_visible', 'key': 'submit_button'},
        {'action': 'assert_element_count', 'key': 'items_list', 'count': 3},
      ]));

      expect(result.isValid, isTrue, reason: result.toString());
    });

    test('rejects an unknown action and stops checking its args', () {
      final result = validator.validate(scenarioOf([
        {'action': 'teleport', 'key': 'submit_button'},
      ]));

      expect(result.hasErrors, isTrue);
      expect(result.errors.single.message, contains('unsupported action'));
    });

    test('rejects a missing required argument', () {
      final result = validator.validate(scenarioOf([
        {'action': 'enter_text', 'key': 'name_field'},
      ]));

      expect(result.errors.single.message, contains('"text"'));
    });

    test('rejects a key that is not in the registry', () {
      final result = validator.validate(scenarioOf([
        {'action': 'tap', 'key': 'mystery_key'},
      ]));

      expect(result.errors.single.message, contains('not in KeyRegistry'));
    });

    test('rejects a tap with no usable target', () {
      final result = validator.validate(scenarioOf([
        {'action': 'tap'},
      ]));

      expect(result.errors.single.message, contains('needs "key"'));
    });

    test('accepts a tap with coordinates but warns they are fragile', () {
      final result = validator.validate(scenarioOf([
        {'action': 'tap', 'x': 10, 'y': 20},
      ]));

      expect(result.hasErrors, isFalse);
      expect(result.issues.single.severity, Severity.warning);
      expect(result.issues.single.message, contains('coordinate targeting'));
    });

    test('rejects a non-integer count', () {
      final result = validator.validate(scenarioOf([
        {'action': 'assert_element_count', 'key': 'items_list', 'count': 'many'},
      ]));

      expect(result.errors.single.message, contains('must be an integer'));
    });

    test('rejects an empty scenario', () {
      final result = validator.validate(scenarioOf([]));

      expect(result.errors.single.message, contains('no commands'));
    });

    test('assert_text_contains is a supported action', () {
      final result = validator.validate(scenarioOf([
        {
          'action': 'assert_text_contains',
          'key': 'items_counter',
          'text': '5'
        },
      ]));

      expect(result.isValid, isTrue, reason: result.toString());
    });
  });

  group('E2eCapability', () {
    test('native exposes marionette tools', () {
      final cap = E2eCapability.forPlatform(E2ePlatform.nativeVmService);

      expect(cap.marionetteAvailable, isTrue);
      expect(cap.supports('get_interactive_elements'), isTrue);
      expect(cap.supports('take_screenshots'), isTrue);
      expect(cap.unsupportedReason('tap'), isNull);
    });

    test('web withholds marionette and explains why', () {
      final cap = E2eCapability.forPlatform(E2ePlatform.webCdpBridge);

      expect(cap.marionetteTools, isEmpty);
      expect(cap.supports('get_interactive_elements'), isFalse);

      final reason = cap.unsupportedReason('get_interactive_elements');
      expect(reason, isNotNull);
      expect(reason, contains('VM service'));
      // The message must point the caller at a working alternative.
      expect(reason, contains('assert_visible'));
    });

    test('web still exposes flutter-skill tools', () {
      final cap = E2eCapability.forPlatform(E2ePlatform.webCdpBridge);

      expect(cap.flutterSkillAvailable, isTrue);
      expect(cap.supports('assert_visible'), isTrue);
      expect(cap.supports('tap'), isTrue);
    });

    test('unknown tools are reported as unregistered, not platform-blocked', () {
      final native = E2eCapability.forPlatform(E2ePlatform.nativeVmService);

      expect(native.unsupportedReason('no_such_tool'), contains('not registered'));
    });

    test('toJson reports platform and counts', () {
      final json = E2eCapability.forPlatform(E2ePlatform.webCdpBridge).toJson();

      expect(json['platform'], 'webCdpBridge');
      expect(json['marionetteAvailable'], isFalse);
      expect((json['flutterSkillTools'] as List), isNotEmpty);
    });
  });

  group('StepRecorder', () {
    test('captures assertions, which upstream recording omits', () {
      final recorder = StepRecorder(scenarioName: 'with_asserts')..start();

      recorder.record(
        E2eStep(step: 1, action: 'tap', args: {'key': 'submit_button'}),
        StepOutcome.passed,
      );
      recorder.recordAssertion(
        E2eStep(
          step: 2,
          action: 'assert_visible',
          args: {'key': 'submit_button'},
        ),
        const AssertionOutcome(passed: false, expected: 'present', actual: 'absent'),
      );

      final recording = recorder.stop();

      expect(recording.steps, hasLength(2));
      expect(recording.passed, isFalse);
      expect(recording.failedCount, 1);
      expect(recording.firstFailedStep, 2);
      expect(recording.steps[1].assertion?.actual, 'absent');
    });

    test('emits re-runnable scenario JSON that round-trips', () {
      final recorder = StepRecorder(scenarioName: 'rerunnable')..start();
      recorder.record(
        E2eStep(step: 1, action: 'tap', args: {'key': 'items_counter'}),
        StepOutcome.passed,
      );
      recorder.recordAssertion(
        E2eStep(
          step: 2,
          action: 'assert_visible',
          args: {'key': 'items_counter'},
        ),
        const AssertionOutcome(passed: true),
      );
      final recording = recorder.stop();

      // toScenarioJson strips outcomes, so the result parses back as a scenario.
      final replayed = E2eScenario.fromJson(recording.toScenarioJson());

      expect(replayed.name, 'rerunnable');
      expect(replayed.commands.map((c) => c.action), ['tap', 'assert_visible']);
    });

    test('skipped steps are excluded from re-runnable output', () {
      final recorder = StepRecorder(scenarioName: 'partial')..start();
      recorder.record(
        E2eStep(step: 1, action: 'tap', args: {'key': 'items_counter'}),
        StepOutcome.passed,
      );
      recorder.recordSkipped(
        E2eStep(step: 2, action: 'tap', args: {'key': 'about_settings_button'}),
      );

      final replayed = E2eScenario.fromJson(recorder.stop().toScenarioJson());

      expect(replayed.commands, hasLength(1));
    });

    test('recording without start is a programming error', () {
      expect(
        () => StepRecorder().record(
          E2eStep(step: 1, action: 'tap', args: const {}),
          StepOutcome.passed,
        ),
        throwsA(isA<StateError>()),
      );
      expect(() => StepRecorder().stop(), throwsA(isA<StateError>()));
    });
  });

  group('E2eLogStore', () {
    test('evicts oldest records past capacity', () {
      final store = E2eLogStore(capacity: 3);
      for (var i = 0; i < 5; i++) {
        store.add(E2eLogRecord(
          message: 'line $i',
          level: E2eLogLevel.info,
          timestamp: DateTime.now(),
        ));
      }

      expect(store.length, 3);
      expect(store.records().first.message, 'line 2');
    });

    test('filters by level and by time', () {
      final store = E2eLogStore();
      final old = DateTime.now().subtract(const Duration(minutes: 5));
      final now = DateTime.now();

      store.add(E2eLogRecord(
          message: 'old error', level: E2eLogLevel.error, timestamp: old));
      store.add(E2eLogRecord(
          message: 'new info', level: E2eLogLevel.info, timestamp: now));

      expect(store.records(level: E2eLogLevel.error), hasLength(1));
      expect(store.records(since: now), hasLength(1));
      expect(store.drain(), hasLength(2));
      expect(store.length, 0);
    });
  });

  group('BridgeLogCollector', () {
    test('forwards to marionette only once started', () {
      final collector = BridgeLogCollector();

      // Emitting before start must not throw; marionette is not listening yet.
      collector.emit('before start');
      expect(collector.store.length, 1);

      final received = <String>[];
      collector.start(received.add);
      collector.emit('after start');

      expect(received, ['after start']);
      expect(collector.store.length, 2);

      collector.dispose();
      collector.emit('after dispose');
      expect(received, hasLength(1), reason: 'disposed collector goes quiet');
    });
  });
}

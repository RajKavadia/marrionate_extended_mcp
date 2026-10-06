import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('E2eRecorderScope records taps on widgets with ValueKey',
      (tester) async {
    final recorder = InteractionRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: E2eRecorderScope(
          recorder: recorder,
          autoStart: true,
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey<String>('test_button'),
                onPressed: () {},
                child: const Text('Click Me'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(recorder.isRecording, isTrue);
    expect(recorder.steps, isEmpty);

    // Tap the button
    await tester.tap(find.byKey(const ValueKey<String>('test_button')));
    await tester.pump();

    // Verify step was recorded
    expect(recorder.steps, hasLength(1));
    expect(recorder.steps.first.action, 'tap');
    expect(recorder.steps.first.args['key'], 'test_button');
  });

  testWidgets('E2eRecorderScope ignores widgets without ValueKey',
      (tester) async {
    final recorder = InteractionRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: E2eRecorderScope(
          recorder: recorder,
          autoStart: true,
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Unkeyed Button'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(recorder.steps, isEmpty);
  });

  testWidgets('skips keyed widgets that do not handle the gesture',
      (tester) async {
    final recorder = InteractionRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: E2eRecorderScope(
          recorder: recorder,
          autoStart: true,
          child: const Scaffold(
            body: ListTile(
              key: ValueKey<String>('settings_appearance'),
              title: Text('Appearance'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('settings_appearance')));
    await tester.pump();

    expect(recorder.steps, isEmpty);
  });

  testWidgets('records a double tap as double_tap', (tester) async {
    final recorder = InteractionRecorder();
    var now = DateTime(2026, 1, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: E2eRecorderScope(
          recorder: recorder,
          autoStart: true,
          clock: () => now,
          child: Scaffold(
            body: Center(
              child: GestureDetector(
                key: const ValueKey<String>('mouse_tap_target'),
                onDoubleTap: () {},
                onSecondaryTap: () {},
                child: const ColoredBox(
                  color: Color(0xFFCCCCCC),
                  child: SizedBox(width: 120, height: 80),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final target = find.byKey(const ValueKey<String>('mouse_tap_target'));
    await tester.tap(target);
    now = now.add(const Duration(milliseconds: 80));
    await tester.tap(target);
    await tester.pump(kDoubleTapMinTime + kDoubleTapTimeout);

    expect(recorder.steps, hasLength(1));
    expect(recorder.steps.single.action, 'double_tap');
    expect(recorder.steps.single.args['key'], 'mouse_tap_target');
  });

  testWidgets('records a secondary click as secondary_tap', (tester) async {
    final recorder = InteractionRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: E2eRecorderScope(
          recorder: recorder,
          autoStart: true,
          child: Scaffold(
            body: Center(
              child: GestureDetector(
                key: const ValueKey<String>('mouse_tap_target'),
                onSecondaryTap: () {},
                child: const ColoredBox(
                  color: Color(0xFFCCCCCC),
                  child: SizedBox(width: 120, height: 80),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('mouse_tap_target')),
      buttons: kSecondaryButton,
    );
    await tester.pump();

    expect(recorder.steps.single.action, 'secondary_tap');
  });

  testWidgets('records a horizontal drag on the scrollable ancestor',
      (tester) async {
    final recorder = InteractionRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: E2eRecorderScope(
          recorder: recorder,
          autoStart: true,
          child: Scaffold(
            body: SizedBox(
              height: 240,
              child: PageView(
                key: const ValueKey<String>('page_view'),
                children: const [
                  Center(
                    child: Text('Page', key: ValueKey<String>('page_2')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('page_2')),
      const Offset(-280, 0),
    );
    await tester.pump();

    expect(recorder.steps, hasLength(1));
    expect(recorder.steps.single.action, 'swipe');
    expect(recorder.steps.single.args['key'], 'page_view');
    expect(recorder.steps.single.args['direction'], 'left');
  });

  testWidgets('records enter_text only when the field value changes',
      (tester) async {
    final recorder = InteractionRecorder();
    final bio = TextEditingController(text: 'Pre-filled biography.');
    final name = TextEditingController();
    final readOnly = TextEditingController(text: 'read-only-value');
    addTearDown(bio.dispose);
    addTearDown(name.dispose);
    addTearDown(readOnly.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: E2eRecorderScope(
          recorder: recorder,
          autoStart: true,
          child: Scaffold(
            body: Column(
              children: [
                TextField(
                  key: const ValueKey<String>('bio_field'),
                  controller: bio,
                ),
                TextField(
                  key: const ValueKey<String>('readonly_field'),
                  readOnly: true,
                  controller: readOnly,
                ),
                TextField(
                  key: const ValueKey<String>('name_field'),
                  controller: name,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('bio_field')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('readonly_field')));
    await tester.pump();
    expect(recorder.steps.where((s) => s.action == 'enter_text'), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey<String>('name_field')),
      'Raj',
    );
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    final entered = recorder.steps.where((s) => s.action == 'enter_text');
    expect(entered, hasLength(1));
    expect(entered.single.args['key'], 'name_field');
    expect(entered.single.args['text'], 'Raj');
  });
}

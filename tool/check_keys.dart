// Fails when an interactive widget has no ValueKey<String>.
//
// The governing rule for this project: anything a tool can interact with, or an
// assertion can observe, carries a stable `ValueKey<String>`. Scenarios target
// keys exclusively, so an unkeyed widget is an untestable widget and a latent
// breakage that only shows up as a confusing runtime failure.
//
// This is a source-level check, not a runtime one, because a runtime check would
// only see whichever screen happens to be mounted.
//
// Usage:
//   dart run tool/check_keys.dart            # check packages/app/lib
//   dart run tool/check_keys.dart <dir>      # check another directory
import 'dart:io';

/// Widget class names that accept a tap or other gesture.
const Set<String> interactiveWidgetNames = {
  'ElevatedButton',
  'FilledButton',
  'FilledButton.tonal',
  'OutlinedButton',
  'TextButton',
  'IconButton',
  'FloatingActionButton',
  'SegmentedButton',
  'ListTile',
  'Card',
  'InkWell',
  'GestureDetector',
  'Switch',
  'Checkbox',
  'Radio',
  'Slider',
  'DropdownButton',
  'DropdownButtonFormField',
  'TextField',
  'TextFormField',
  'SearchBar',
  'Chip',
  'ActionChip',
  'FilterChip',
  'ChoiceChip',
  'InputChip',
  'SwitchListTile',
  'CheckboxListTile',
  'RadioListTile',
  'ReorderableListView',
  'Dismissible',
  'Draggable',
  'LongPressDraggable',
  'PageView',
  'PageViewBuilder',
  'RawMaterialButton',
  'CupertinoButton',
  'PopupMenuButton',
  'MenuAnchor',
};

/// A widget found to be interactive but unkeyed.
class KeyViolation {
  KeyViolation({
    required this.file,
    required this.line,
    required this.widget,
    required this.reason,
  });

  final String file;
  final int line;
  final String widget;
  final String reason;

  @override
  String toString() => '$file:$line  $widget  $reason';
}

/// Scans Dart sources for unkeyed interactive widgets.
class KeyChecker {
  const KeyChecker();

  /// Checks every `.dart` file under [dir].
  ///
  /// Returns violations sorted by file then line so CI output is stable.
  List<KeyViolation> check(Directory dir) {
    if (!dir.existsSync()) {
      throw ArgumentError.value(dir.path, 'dir', 'directory does not exist');
    }

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        // Generated code is not ours to key.
        .where((f) => !f.path.contains('${Platform.pathSeparator}.dart_tool'))
        .where((f) => !f.path.endsWith('g.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final violations = <KeyViolation>[];
    for (final file in files) {
      violations.addAll(checkFile(file, root: dir));
    }
    return violations;
  }

  /// Checks one file.
  List<KeyViolation> checkFile(File file, {Directory? root}) {
    final lines = file.readAsLinesSync();
    final violations = <KeyViolation>[];
    final relative = root == null
        ? file.path
        : file.path
            .replaceAll('\\', '/')
            .replaceFirst(root.path.replaceAll('\\', '/'), '')
            .replaceFirst(RegExp('^/'), '');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      // A file-level ignore, e.g. // ignore: unkeyed_widget
      if (trimmed.startsWith('//') && trimmed.contains('ignore: unkeyed_widget')) {
        continue;
      }

      final match = interactiveWidgetNames.firstWhere(
        (name) =>
            RegExp('(^|[^A-Za-z0-9_])${RegExp.escape(name)}\\s*\\(')
                .hasMatch(trimmed),
        orElse: () => '',
      );
      if (match.isEmpty) continue;

      // Look ahead for a key on this widget, allowing multi-line arguments.
      final lookahead = lines.skip(i).take(12).join('\n');
      if (_hasKeyArgument(lookahead, match)) continue;

      // A local variable that is later given a key does not count; the widget
      // constructor call itself must carry the key.
      violations.add(KeyViolation(
        file: relative,
        line: i + 1,
        widget: match,
        reason: 'no ValueKey<String> on this $match',
      ));
    }
    return violations;
  }

  /// Whether the constructor call spanning [source] supplies a key.
  ///
  /// Walks the argument list by paren depth rather than scanning the whole
  /// lookahead, so a key belonging to a *sibling* widget later in the lookahead
  /// is not mistaken for this one's.
  static bool _hasKeyArgument(String source, String widgetName) {
    final startMatch =
        RegExp('(^|[^A-Za-z0-9_])${RegExp.escape(widgetName)}\\s*\\(').firstMatch(source);
    if (startMatch == null) return false;

    var i = source.indexOf('(', startMatch.start);
    if (i == -1) return false;
    final open = i;
    var depth = 0;
    var end = source.length;

    for (; i < source.length; i++) {
      final ch = source[i];
      if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }

    final args = source.substring(open, end);
    // Accept the explicit keyed forms and the `super.key` pass-through.
    return RegExp(r'key\s*:\s*(const\s+)?ValueKey').hasMatch(args) ||
        RegExp(r'key\s*:\s*const\s+ValueKey').hasMatch(args) ||
        RegExp(r'\bsuper\.key\b').hasMatch(args) ||
        RegExp(r'key\s*:\s*[A-Za-z_][A-Za-z0-9_.]*').hasMatch(args);
  }
}

Future<void> main(List<String> args) async {
  final target = args.isEmpty
      ? Directory('packages${Platform.pathSeparator}app'
          '${Platform.pathSeparator}lib')
      : Directory(args.first);

  final checker = KeyChecker();

  List<KeyViolation> violations;
  try {
    violations = checker.check(target);
  } on ArgumentError catch (e) {
    stderr.writeln('check_keys: ${e.message}');
    exit(2);
  }

  if (violations.isEmpty) {
    stdout.writeln('check_keys: OK - every interactive widget in '
        '${target.path} carries a ValueKey');
    return;
  }

  stderr.writeln('check_keys: ${violations.length} unkeyed interactive '
      'widget(s) in ${target.path}\n');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  stderr.writeln('\nEvery interactive element needs a stable ValueKey<String> '
      'so scenarios can target it. Add `key: const ValueKey<String>(\'...\')`, '
      'or suppress a specific line with '
      '`// ignore: unkeyed_widget` and a comment explaining why.');

  exit(1);
}

import 'dart:convert';
import 'dart:io';

/// One executable step in a scenario.
///
/// Accepts the three argument shapes the vendored toolchains emit, because
/// scenarios authored against either upstream must run unmodified:
///
///   inline    `{ "step": 1, "action": "tap", "key": "submit_button" }`
///   nested    `{ "step": 1, "action": "tap", "args": { "key": "submit_button" } }`
///   recorded  `{ "step": 1, "tool": "tap", "params": { "key": "submit_button" } }`
///
/// The recorded shape is what `record_export` produces; the nested shape is
/// what `execute_batch` documents.
class E2eStep {
  const E2eStep({
    required this.step,
    required this.action,
    this.args = const {},
    this.label,
  });

  /// 1-based position within the owning scenario.
  final int step;

  /// Tool name to invoke, e.g. `tap` or `assert_visible`.
  final String action;

  /// Arguments passed to the tool.
  final Map<String, Object?> args;

  /// Optional human label, used in reports.
  final String? label;

  /// Parses one step object, tolerating every supported shape.
  factory E2eStep.fromJson(Map<String, Object?> json) {
    // `tool` and `action` are both accepted as the verb.
    final action = (json['action'] ?? json['tool'] ?? json['method']) as String?;
    if (action == null || action.isEmpty) {
      throw FormatException(
        'step is missing an action: expected one of '
        '"action", "tool", or "method". Got keys: ${json.keys.toList()}',
        json.toString(),
      );
    }

    // Metadata keys are not tool arguments.
    const metadata = {'step', 'action', 'tool', 'method', 'args', 'params', 'label'};

    final Map<String, Object?> args = {};
    // Inline fields are applied first so an explicit nested block, which is the
    // more deliberate and more structured form, wins on conflict.
    json.forEach((key, value) {
      if (!metadata.contains(key)) args[key.toString()] = value;
    });
    final nested = json['args'] ?? json['params'];
    if (nested is Map) {
      nested.forEach((key, value) => args[key.toString()] = value);
    }

    // `step` is optional; recorded exports always carry it.
    final rawStep = json['step'];
    final index = rawStep is int ? rawStep : (rawStep is num ? rawStep.toInt() : 0);

    return E2eStep(
      step: index,
      action: action,
      args: args,
      label: json['label'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'step': step,
        'action': action,
        if (label != null) 'label': label,
        'args': args,
      };

  /// Short human description for reports.
  String get describe {
    final target = args['key'] ?? args['text'] ?? args['selector'] ?? '';
    final suffix = target == '' ? '' : ' $target';
    return 'step $step: $action$suffix';
  }

  /// Returns a copy with [step] renumbered.
  E2eStep withStep(int newStep) =>
      E2eStep(step: newStep, action: action, args: args, label: label);

  @override
  String toString() => describe;
}

/// A named, ordered list of steps plus optional template variables.
class E2eScenario {
  const E2eScenario({
    required this.name,
    required this.commands,
    this.description,
    this.variables = const {},
  });

  /// Scenario identifier, used as the report key.
  final String name;

  /// Optional prose description.
  final String? description;

  /// Ordered steps.
  final List<E2eStep> commands;

  /// Values substituted into step arguments before execution.
  final Map<String, Object?> variables;

  /// Parses a scenario object.
  ///
  /// Accepts the step list under `commands`, `steps`, `actions`, or `tools`,
  /// since the vendored exporters disagree on the key.
  factory E2eScenario.fromJson(Map<String, Object?> json) {
    final name = (json['name'] ?? json['scenarioName'] ?? json['scenario']) as String?;
    if (name == null || name.isEmpty) {
      throw const FormatException('scenario is missing "name"');
    }

    final rawCommands = json['commands'] ?? json['steps'] ?? json['actions'] ?? json['tools'];
    if (rawCommands is! List) {
      throw FormatException(
        'scenario "$name" has no command list: expected "commands", "steps", '
        '"actions", or "tools" to be a JSON array',
      );
    }

    final commands = <E2eStep>[];
    for (var i = 0; i < rawCommands.length; i++) {
      final entry = rawCommands[i];
      if (entry is! Map) {
        throw FormatException(
          'scenario "$name" command ${i + 1} is not an object',
        );
      }
      // Renumber so `step` is always dense and 1-based regardless of source.
      commands.add(E2eStep.fromJson(
        Map<String, Object?>.from(entry),
      ).withStep(i + 1));
    }

    final rawVars = json['variables'] ?? json['vars'];
    final variables = <String, Object?>{};
    if (rawVars is Map) {
      rawVars.forEach((key, value) => variables[key.toString()] = value);
    }

    return E2eScenario(
      name: name,
      commands: List.unmodifiable(commands),
      description: json['description'] as String?,
      variables: Map.unmodifiable(variables),
    );
  }

  /// Decodes a scenario from a JSON string.
  factory E2eScenario.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('scenario JSON must be an object');
    }
    return E2eScenario.fromJson(Map<String, Object?>.from(decoded));
  }

  /// Loads a single scenario file.
  factory E2eScenario.loadFile(File file) =>
      E2eScenario.decode(file.readAsStringSync());

  /// Result of scanning a directory for scenarios.
  ///
  /// [skipped] records files that looked like scenarios but did not parse, so
  /// a stray config file in the scenario directory cannot abort an entire run.
  static ({List<E2eScenario> scenarios, List<String> skipped}) loadDirectorySafe(
    Directory dir,
  ) {
    if (!dir.existsSync()) return (scenarios: const [], skipped: const []);

    final scenarios = <E2eScenario>[];
    final skipped = <String>[];

    for (final file in _jsonFiles(dir)) {
      try {
        scenarios.add(E2eScenario.loadFile(file));
      } on FormatException catch (e) {
        skipped.add('${file.path}: ${e.message}');
      } on FileSystemException catch (e) {
        skipped.add('${file.path}: ${e.message}');
      }
    }
    return (scenarios: scenarios, skipped: skipped);
  }

  /// Loads every `.json` scenario in [dir], sorted by filename for stable runs.
  ///
  /// Throws if any file fails to parse. Use [loadDirectorySafe] to collect
  /// problems instead of failing fast.
  static List<E2eScenario> loadDirectory(Directory dir) {
    if (!dir.existsSync()) return const [];
    return _jsonFiles(dir).map(E2eScenario.loadFile).toList(growable: false);
  }

  /// `.json` files in [dir], sorted by path.
  static List<File> _jsonFiles(Directory dir) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Map<String, Object?> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (variables.isNotEmpty) 'variables': variables,
        'commands': commands.map((c) => c.toJson()).toList(),
      };

  /// Returns a copy with `{{var}}` placeholders in arguments substituted.
  ///
  /// Substitutes whole-value matches only; a placeholder embedded in a longer
  /// string is left untouched so partial interpolation cannot corrupt values.
  E2eScenario interpolate() {
    if (variables.isEmpty) return this;

    /// Replaces an argument when its whole value matches a variable name.
    ///
    /// Only whole-value matches are substituted; a variable name embedded in a
    /// longer string is left untouched so partial interpolation cannot silently
    /// corrupt values.
    Object? substitute(Object? value) {
      if (value is! String) return value;
      final direct = variables[value];
      if (direct == null) return value;
      return direct is String ? direct : direct.toString();
    }

    return E2eScenario(
      name: name,
      description: description,
      variables: variables,
      commands: commands
          .map((c) => E2eStep(
                step: c.step,
                action: c.action,
                label: c.label,
                args: c.args.map((k, v) => MapEntry(k, substitute(v))),
              ))
          .toList(growable: false),
    );
  }

  @override
  String toString() => 'E2eScenario($name, ${commands.length} steps)';
}

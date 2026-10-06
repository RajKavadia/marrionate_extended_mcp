import 'dart:convert';

import '../drivers/driver_factory.dart';

/// Ambient state a tool handler needs.
class ToolContext {
  const ToolContext({
    required this.recorder,
    this.stopOnFailure = false,
    this.stepDelayMs = 0,
    this.platform,
    this.session,
  });

  /// Records every executed step, including assertions.
  final Object? recorder;

  /// Abort the batch at the first failing step.
  final bool stopOnFailure;

  /// Pause between steps, in milliseconds.
  final int stepDelayMs;

  /// Platform reported by the app under test, when connected.
  final String? platform;

  /// The attached app, when one is connected.
  ///
  /// Live handlers read their driver from here rather than closing over a
  /// connection, so reconnecting swaps the driver without rebuilding handlers.
  final LiveSession? session;

  /// Returns a copy carrying [session], leaving everything else intact.
  ToolContext withSession(LiveSession? session) => ToolContext(
        recorder: recorder,
        stopOnFailure: stopOnFailure,
        stepDelayMs: stepDelayMs,
        platform: platform,
        session: session ?? this.session,
      );
}

/// Signature every tool implements.
typedef ToolHandler = Future<Map<String, Object?>> Function(
  Map<String, Object?> args,
  ToolContext context,
);

/// Which automation stack owns a tool.
enum ToolSource {
  /// Marionette: VM-service-based. Works on native and Flutter web in debug.
  marionette,

  /// Flutter-skill: VM service on native, CDP on web.
  flutterSkill,

  /// This package's own additions.
  e2e,
}

/// The namespace each source presents its tools under.
///
/// Both vendored stacks define a `tap` with different argument shapes and
/// different transports, so the prefix is what keeps them apart on the wire.
extension ToolSourcePrefix on ToolSource {
  String get prefix => switch (this) {
        ToolSource.marionette => 'mcp_',
        ToolSource.flutterSkill => 'skill_',
        ToolSource.e2e => '',
      };
}

/// Metadata plus implementation for one MCP tool.
class ToolDescriptor {
  ToolDescriptor({
    required this.name,
    required this.description,
    required this.source,
    required this.handler,
    this.inputSchema = const {},
    this.aliases = const {},
  });

  /// Canonical tool name presented to MCP clients.
  final String name;

  /// Human-readable summary shown in `tools/list`.
  final String description;

  /// Which stack provides this tool.
  final ToolSource source;

  /// Implementation.
  final ToolHandler handler;

  /// JSON Schema for the tool's arguments.
  final Map<String, Object?> inputSchema;

  /// Unprefixed names that also resolve here.
  ///
  /// Both vendored stacks define a `tap` with different argument shapes, so the
  /// canonical names are namespaced (`mcp_tap`, `skill_tap`) while the flat
  /// aliases keep existing agent configurations working.
  final Set<String> aliases;

  /// Whether this tool needs a live app connection.
  bool get requiresConnection => source != ToolSource.e2e;

  /// The name clients see, e.g. `mcp_tap`.
  ///
  /// Uniqueness is per source, so this is what the registry is keyed by: the two
  /// stacks both have a `tap`, and they are not interchangeable.
  String get wireName => '${source.prefix}$name';

  Map<String, Object?> toJson() => {
        'name': wireName,
        'description': description,
        'inputSchema': inputSchema,
      };

  @override
  String toString() => 'ToolDescriptor($wireName)';
}

/// Name lookup for tools, with alias resolution.
///
/// Keys are qualified by [ToolSource] because both stacks contribute tools with
/// identical bare names. Resolution order is deliberate: an explicit namespace
/// wins, then the first source that owns the bare name, then a flat alias.
class ToolRegistry {
  final Map<String, ToolDescriptor> _byKey = {};
  final Map<String, ToolDescriptor> _byAlias = {};

  static String _key(ToolSource source, String name) => '${source.name}::$name';

  /// The source a namespace prefix implies, or null when unprefixed.
  static ToolSource? sourceForPrefix(String name) {
    if (name.startsWith('mcp_')) return ToolSource.marionette;
    if (name.startsWith('skill_')) return ToolSource.flutterSkill;
    return null;
  }

  /// Strips a known namespace prefix, if present.
  static String stripPrefix(String name) {
    final source = sourceForPrefix(name);
    return source == null ? name : name.substring(source.prefix.length);
  }

  /// Registers [descriptor], rejecting duplicate names and aliases.
  void register(ToolDescriptor descriptor) {
    final key = _key(descriptor.source, descriptor.name);
    if (_byKey.containsKey(key)) {
      throw ArgumentError.value(
        descriptor.wireName,
        'name',
        'tool already registered',
      );
    }
    _byKey[key] = descriptor;
    for (final alias in descriptor.aliases) {
      final existing = _byAlias[alias];
      if (existing != null) {
        throw ArgumentError.value(
          alias,
          'aliases',
          'alias already claimed by ${existing.wireName}',
        );
      }
      _byAlias[alias] = descriptor;
    }
  }

  /// Registers many descriptors.
  void registerAll(Iterable<ToolDescriptor> descriptors) {
    for (final d in descriptors) {
      register(d);
    }
  }

  /// Resolves an exact wire name such as `mcp_tap`.
  ToolDescriptor? lookup(String wireName) {
    final source = sourceForPrefix(wireName);
    if (source == null) return null;
    return _byKey[_key(source, stripPrefix(wireName))];
  }

  /// Resolves a wire name, a bare name, or a flat alias.
  ///
  /// A namespaced name is authoritative: `skill_tap` never resolves to
  /// marionette's `tap`, which would silently run the wrong transport against
  /// incompatible selectors.
  ToolDescriptor? resolve(String nameOrAlias) {
    final prefixed = sourceForPrefix(nameOrAlias);
    if (prefixed != null) {
      final byPrefix =
          _byKey[_key(prefixed, stripPrefix(nameOrAlias))];
      if (byPrefix != null) return byPrefix;
    }
    for (final source in ToolSource.values) {
      final byName = _byKey[_key(source, nameOrAlias)];
      if (byName != null) return byName;
    }
    return _byAlias[nameOrAlias];
  }

  /// Every tool, optionally filtered to one [source].
  List<ToolDescriptor> list({ToolSource? source}) {
    final all = _byKey.values.toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    if (source == null) return all;
    return all.where((t) => t.source == source).toList();
  }

  /// Wire names, sorted.
  List<String> get names => _byKey.values.map((t) => t.wireName).toList()
    ..sort();

  /// Bare names owned by [source], sorted.
  List<String> namesFor(ToolSource source) =>
      list(source: source).map((t) => t.name).toList()..sort();

  /// Wire names plus aliases, for error messages and diagnostics.
  List<String> get allCallableNames => {
        for (final t in _byKey.values) ...[t.wireName, ...t.aliases],
      }.toList()
        ..sort();

  int get length => _byKey.length;

  bool get isEmpty => _byKey.isEmpty;

  /// `tools/list` payload.
  List<Map<String, Object?>> toJsonList({ToolSource? source}) =>
      list(source: source).map((t) => t.toJson()).toList();

  /// Encodes a single descriptor for diagnostics.
  String describe(String name) {
    final tool = resolve(name);
    if (tool == null) return 'no tool named "$name"';
    return const JsonEncoder.withIndent('  ').convert({
      'name': tool.wireName,
      'source': tool.source.name,
      'aliases': tool.aliases.toList()..sort(),
      'description': tool.description,
      'inputSchema': tool.inputSchema,
    });
  }

  void clear() {
    _byKey.clear();
    _byAlias.clear();
  }
}

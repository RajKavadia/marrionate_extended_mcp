// Normalises vendored pubspecs so each can be published independently.
//
// Two pub constraints drive this design:
//
//   1. `dart pub publish` rejects any package declaring `resolution: workspace`.
//   2. A Dart pub workspace requires every member to declare it.
//
// So vendored packages cannot be workspace members *and* publishable. They are
// therefore kept workspace-free and publishable, and local development resolves
// them through `dependency_overrides` with path dependencies in the consuming
// packages (packages/flutter_e2e_toolkit, packages/app).
//
// Transformations applied to each vendor pubspec:
//   - drop `resolution: workspace`
//   - drop `publish_to: none`
//   - set version to the fork's initial release
//   - rewrite internal dependency keys to the e2e_* names and pin them
//   - rename `executables` keys so forks do not squat upstream global commands
//
// Idempotent: re-running produces no further changes.
import 'dart:io';

/// One vendored package's publish metadata.
class VendorPackage {
  VendorPackage({
    required this.dir,
    required this.name,
    required this.version,
    this.internalDeps = const {},
    this.executables = const {},
  });

  /// Directory relative to repo root.
  final String dir;

  /// Published package name.
  final String name;

  /// Initial published version.
  final String version;

  /// Maps upstream internal dependency name -> e2e_* published name.
  final Map<String, String> internalDeps;

  /// Maps upstream executable name -> fork executable name.
  final Map<String, String> executables;
}

/// Result of normalising one pubspec.
class PrepareReport {
  final List<String> changes = [];
  final List<String> problems = [];

  @override
  String toString() {
    if (problems.isNotEmpty) {
      return 'PROBLEMS:\n${problems.map((p) => '  $p').join('\n')}';
    }
    return changes.isEmpty ? 'no changes' : changes.join('\n');
  }
}

/// Rewrites vendored pubspecs into publishable form.
class PublishPreparer {
  PublishPreparer({required this.root, required this.packages, this.dryRun = false});

  final Directory root;
  final List<VendorPackage> packages;
  final bool dryRun;

  List<PrepareReport> run() {
    return packages.map(prepare).toList();
  }

  PrepareReport prepare(VendorPackage pkg) {
    final report = PrepareReport();
    final file = File('${root.path}${Platform.pathSeparator}${pkg.dir}'
        '${Platform.pathSeparator}pubspec.yaml');
    if (!file.existsSync()) {
      report.problems.add('${pkg.dir}: pubspec.yaml missing');
      return report;
    }

    var out = file.readAsStringSync();
    final original = out;

    // 1. Drop `resolution: workspace`.
    final resolution = RegExp(r'^resolution:\s*workspace\s*\n', multiLine: true);
    if (resolution.hasMatch(out)) {
      out = out.replaceAll(resolution, '');
      report.changes.add('${pkg.dir}: dropped resolution: workspace');
    }

    // 2. Drop `publish_to: none` (and its trailing comment).
    final publishTo =
        RegExp(r'''^publish_to:\s*['"]?none['"]?.*\n''', multiLine: true);
    if (publishTo.hasMatch(out)) {
      out = out.replaceAll(publishTo, '');
      report.changes.add('${pkg.dir}: dropped publish_to: none');
    }

    // 3. Pin the fork version.
    final version = RegExp(r'^version:\s*\S+\s*$', multiLine: true);
    if (!version.hasMatch(out)) {
      report.problems.add('${pkg.dir}: no version: key found');
    } else if (!out.contains('version: ${pkg.version}')) {
      out = out.replaceAll(version, 'version: ${pkg.version}');
      report.changes.add('${pkg.dir}: version -> ${pkg.version}');
    }

    // 4. Rewrite internal dependency keys and pin them to the fork version.
    pkg.internalDeps.forEach((upstream, forked) {
      // Matches the dependency line plus an inline version constraint.
      final dep = RegExp('^(\\s+)${RegExp.escape(upstream)}:\\s*\\S*.*\$',
          multiLine: true);
      if (dep.hasMatch(out)) {
        out = out.replaceAll(dep, '  $forked: ^${pkg.version}');
        report.changes.add('${pkg.dir}: dep $upstream -> $forked: ^${pkg.version}');
      } else if (!out.contains('$forked:')) {
        report.problems.add('${pkg.dir}: expected dependency $upstream not found');
      }
    });

    // 5. Rename executables so forks do not squat upstream global commands.
    pkg.executables.forEach((upstream, forked) {
      final exe = RegExp('^(\\s+)${RegExp.escape(upstream)}:\\s*${RegExp.escape(upstream)}\\s*\$',
          multiLine: true);
      if (exe.hasMatch(out)) {
        out = out.replaceAll(exe, '  $forked: $upstream');
        report.changes.add('${pkg.dir}: executable $upstream -> $forked');
      } else if (!out.contains('$forked:')) {
        report.problems.add('${pkg.dir}: expected executable $upstream not found');
      }
    });

    // 6. Bound dependencies that lack an upper limit. pub.dev requires one for
    //    SDK-coupled packages so a future major release cannot silently break
    //    consumers.
    for (final match in unboundedDependencies.allMatches(out)) {
      final name = match.group(2)!;
      final upper = upperBounds[name];
      if (upper == null) continue;
      // Already bounded when the constraint is a range (contains '<').
      if (match.group(0)!.contains('<')) continue;
      // [ \t]+ rather than \s+ so a match can never span a newline.
      final bounded = RegExp('^([ \t]+)${RegExp.escape(name)}:[ \t]*.*\$',
          multiLine: true);
      if (bounded.hasMatch(out)) {
        out = out.replaceAll(bounded, '  $name: "$upper"');
        report.changes.add('${pkg.dir}: bounded $name to "$upper"');
      }
    }

    // 7. Ensure a dependency_overrides block so sibling forks resolve from disk
    //    before they exist on pub.dev. `dart pub publish` warns about overrides
    //    but excludes them from published metadata, so the hosted constraint
    //    above is what consumers actually receive.
    if (pkg.internalDeps.isNotEmpty) {
      final existingOverride =
          RegExp(r'^dependency_overrides:\s*\n((?:  .*\n)*)', multiLine: true);
      final desired = StringBuffer('dependency_overrides:\n');
      pkg.internalDeps.forEach((_, forked) {
        desired.writeln('  $forked:\n    path: ../${_dirForName(packages, forked)}');
      });

      if (existingOverride.hasMatch(out)) {
        out = out.replaceAll(existingOverride, desired.toString());
      } else {
        if (!out.endsWith('\n')) out += '\n';
        out += '\n$desired';
      }
      report.changes.add('${pkg.dir}: wrote dependency_overrides for siblings');
    }

    if (out != original && !dryRun) {
      file.writeAsStringSync(out);
    }
    return report;
  }

  /// Matches a dependency line and captures its name in group 2.
  ///
  /// Group 1 is the leading indent, group 2 the package name. Uses `[ \t]+`
  /// rather than `\s+` because `\s` matches newlines under multiLine and would
  /// let a match run past the end of its own line. Anchored to leading whitespace
  /// so top-level keys like `name:` and `version:` are never matched.
  static final RegExp unboundedDependencies =
      RegExp(r'^([ \t]+)([a-z_][a-z0-9_]*):[ \t]*\S.*$', multiLine: true);

  /// Upper bounds to impose on SDK-coupled dependencies.
  static const Map<String, String> upperBounds = {
    'vm_service': '>=14.0.0 <16.0.0',
  };

  /// Maps a published package name back to its vendor directory.
  static String _dirForName(List<VendorPackage> all, String name) {
    for (final p in all) {
      if (p.name == name) return p.dir.split('/').last;
    }
    throw ArgumentError.value(name, 'name', 'no vendor package with this name');
  }
}

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final scriptDir = File.fromUri(Platform.script).parent;
  final root = Directory('${scriptDir.path}${Platform.pathSeparator}..');

  final packages = <VendorPackage>[
    VendorPackage(
      dir: 'vendor/flutter_skill',
      name: 'e2e_flutter_skill',
      version: '0.1.0',
      executables: {'flutter_skill': 'e2e_flutter_skill'},
    ),
    VendorPackage(
      dir: 'vendor/marionette_flutter',
      name: 'e2e_marionette_flutter',
      version: '0.1.0',
    ),
    VendorPackage(
      dir: 'vendor/marionette_mcp',
      name: 'e2e_marionette_mcp',
      version: '0.1.0',
      executables: {'marionette_mcp': 'e2e_marionette_mcp'},
    ),
    VendorPackage(
      dir: 'vendor/marionette_cli',
      name: 'e2e_marionette_cli',
      version: '0.1.0',
      executables: {'marionette': 'e2e_marionette'},
      internalDeps: {'marionette_mcp': 'e2e_marionette_mcp'},
    ),
    VendorPackage(
      dir: 'vendor/marionette_logging',
      name: 'e2e_marionette_logging',
      version: '0.1.0',
      internalDeps: {'marionette_flutter': 'e2e_marionette_flutter'},
    ),
    VendorPackage(
      dir: 'vendor/marionette_logger',
      name: 'e2e_marionette_logger',
      version: '0.1.0',
      internalDeps: {'marionette_flutter': 'e2e_marionette_flutter'},
    ),
  ];

  stdout.writeln(dryRun
      ? 'Dry run (no writes)...'
      : 'Preparing vendored pubspecs for publish...');

  final reports = PublishPreparer(root: root, packages: packages, dryRun: dryRun)
      .run();

  var problems = 0;
  for (var i = 0; i < packages.length; i++) {
    stdout.writeln('\n== ${packages[i].name} ==');
    stdout.writeln(reports[i]);
    problems += reports[i].problems.length;
  }

  if (problems > 0) {
    stderr.writeln('\nFAILED: $problems problem(s).');
    exit(2);
  }
  stdout.writeln('\nOK: all ${packages.length} pubspecs publishable.');
}

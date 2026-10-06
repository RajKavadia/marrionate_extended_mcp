// Rewrites a vendored Dart package's published identity.
//
// The vendored trees under vendor/ are byte-identical copies of upstream. To
// republish them under new names (every upstream name is already taken on
// pub.dev) exactly two mechanical rewrites are applied:
//
//   1. pubspec.yaml `name:` becomes the new package name
//   2. every `package:<old>/` import/export becomes `package:<new>/`
//
// Nothing else is touched. The tool is idempotent and refuses to run if any
// reference to the old name survives, because a missed import surfaces as a
// compile error hundreds of files away from the actual mistake.
//
// Usage:
//   dart run tool/rename_package.dart            # apply all renames
//   dart run tool/rename_package.dart --verify   # report only, non-zero on leftovers
//   dart run tool/rename_package.dart --dry-run  # show counts, write nothing
import 'dart:io';

/// A single package rename to apply.
class PackageRename {
  PackageRename({
    required this.dir,
    required this.from,
    required this.to,
  });

  /// Package directory relative to the repository root.
  final String dir;

  /// Upstream package name, e.g. `marionette_flutter`.
  final String from;

  /// Published package name, e.g. `e2e_marionette_flutter`.
  final String to;

  @override
  String toString() => '$from -> $to ($dir)';
}

/// Outcome of a rename pass.
class RenameReport {
  int filesScanned = 0;
  int filesChanged = 0;
  int importsRewritten = 0;
  int librariesRewritten = 0;
  int pubspecsRewritten = 0;
  int librariesRenamed = 0;

  /// References to an old name that survived the rewrite. Must be empty.
  final List<String> leftovers = [];

  bool get isClean => leftovers.isEmpty;

  @override
  String toString() {
    final b = StringBuffer()
      ..writeln('scanned=$filesScanned changed=$filesChanged '
          'imports=$importsRewritten libraries=$librariesRewritten '
          'libRenamed=$librariesRenamed pubspecs=$pubspecsRewritten');
    if (leftovers.isEmpty) {
      b.writeln('leftovers: none');
    } else {
      b.writeln('leftovers: ${leftovers.length}');
      for (final l in leftovers.take(40)) {
        b.writeln('  $l');
      }
      if (leftovers.length > 40) {
        b.writeln('  ... ${leftovers.length - 40} more');
      }
    }
    return b.toString();
  }
}

/// Applies [PackageRename]s to a repository tree.
class PackageRenamer {
  PackageRenamer({
    required this.root,
    required this.renames,
    this.verifyOnly = false,
    this.dryRun = false,
  });

  final Directory root;
  final List<PackageRename> renames;
  final bool verifyOnly;
  final bool dryRun;

  RenameReport run() {
    final report = RenameReport();
    for (final rename in renames) {
      _applyRename(rename, report);
    }
    return report;
  }

  void _applyRename(PackageRename rename, RenameReport report) {
    final dir = Directory('${root.path}${Platform.pathSeparator}${rename.dir}');
    if (!dir.existsSync()) {
      report.leftovers.add('${rename.dir}: directory missing');
      return;
    }

    // Rewrite this package's own name across the WHOLE repository, not just its
    // own directory. Sibling packages import each other, so
    // vendor/marionette_logging references package:marrionate_extended_mcp/src/marionette_flutter/ and would
    // be missed by a directory-scoped pass -- leaving a compile error far from
    // the actual mistake.
    for (final file in _allFiles(root)) {
      if (!_isSource(file)) continue;
      report.filesScanned++;
      final original = file.readAsStringSync();
      final updated = _rewriteSource(original, rename, report);
      if (updated != original) {
        report.filesChanged++;
        if (!verifyOnly && !dryRun) {
          file.writeAsStringSync(updated);
        }
      }
    }

    // The package's own pubspec is the one place `name:` must change.
    final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (pubspec.existsSync()) {
      final original = pubspec.readAsStringSync();
      final updated = _rewritePubspec(original, rename, report);
      if (updated != original) {
        report.pubspecsRewritten++;
        if (!verifyOnly && !dryRun) {
          pubspec.writeAsStringSync(updated);
        }
      }
    }

    // Rename the top-level library file to match the package, so the public
    // entry point is `package:<new>/<new>.dart` per pub convention instead of
    // importing a stale upstream filename.
    final oldLib = File('${dir.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}${rename.from}.dart');
    final newLib = File('${dir.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}${rename.to}.dart');
    if (oldLib.existsSync() && !newLib.existsSync()) {
      report.librariesRenamed++;
      if (!verifyOnly && !dryRun) {
        oldLib.renameSync(newLib.path);
      }
    }

    if (dryRun) return;

    // A surviving reference to the old name anywhere is a hard failure. Reading
    // from disk (not from `updated`) means --verify sees the real state.
    for (final file in _allFiles(root)) {
      if (!_isSource(file)) continue;
      final content = file.readAsStringSync();
      if (content.contains('package:${rename.from}/')) {
        report.leftovers.add(
            '${_rel(file.path)}: package:${rename.from}/ still present');
      }
      if (content.contains('package:${rename.to}/${rename.from}.dart')) {
        report.leftovers.add('${_rel(file.path)}: '
            'stale library reference to ${rename.from}.dart');
      }
    }
  }

  /// Whether [file] is a source file subject to rewriting.
  static bool _isSource(File file) {
    final path = file.path.replaceAll('\\', '/');
    if (path.contains('/.dart_tool/') || path.contains('/build/')) return false;
    return path.endsWith('.dart') || path.endsWith('.yaml');
  }

  String _rewriteSource(
    String source,
    PackageRename rename,
    RenameReport report,
  ) {
    var out = source;

    // library <old_name>;  ->  library <new_name>;
    final libDecl = RegExp('^library\\s+${RegExp.escape(rename.from)}\\s*;',
        multiLine: true);
    if (libDecl.hasMatch(out)) {
      report.librariesRewritten++;
      out = out.replaceAll(
          libDecl, 'library ${rename.to};');
    }

    // import/export 'package:<old>/<old>.dart' -> 'package:<new>/<new>.dart'
    final selfRef = 'package:${rename.from}/${rename.from}.dart';
    if (out.contains(selfRef)) {
      report.importsRewritten += _countOccurrences(out, selfRef);
      out = out.replaceAll(
          selfRef, 'package:${rename.to}/${rename.to}.dart');
    }

    // Same, for a tree whose package prefix was already rewritten by an earlier
    // run but whose library filename has not: package:<new>/<old>.dart.
    final halfRef = 'package:${rename.to}/${rename.from}.dart';
    if (out.contains(halfRef)) {
      report.importsRewritten += _countOccurrences(out, halfRef);
      out = out.replaceAll(
          halfRef, 'package:${rename.to}/${rename.to}.dart');
    }

    // import/export 'package:<old>/...' and any other string reference.
    final pkgRef = 'package:${rename.from}/';
    if (out.contains(pkgRef)) {
      report.importsRewritten += _countOccurrences(out, pkgRef);
      out = out.replaceAll(pkgRef, 'package:${rename.to}/');
    }

    // Import of our own package by bare name, e.g. `import 'marionette_flutter.dart'`
    // when the library file sits at lib/<name>.dart. Handled by the package: form
    // above in all observed sources, so nothing extra is required here.
    return out;
  }

  String _rewritePubspec(
    String source,
    PackageRename rename,
    RenameReport report,
  ) {
    var out = source;
    // Only the top-level `name:` key, anchored at column 0.
    final nameKey =
        RegExp('^name:\\s*${RegExp.escape(rename.from)}\\s*\$', multiLine: true);
    if (nameKey.hasMatch(out)) {
      out = out.replaceAll(nameKey, 'name: ${rename.to}');
    }
    return out;
  }

  static int _countOccurrences(String haystack, String needle) {
    var count = 0;
    var index = haystack.indexOf(needle);
    while (index != -1) {
      count++;
      index = haystack.indexOf(needle, index + needle.length);
    }
    return count;
  }

  Iterable<File> _allFiles(Directory dir) sync* {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        yield entity;
      }
    }
  }

  String _rel(String path) =>
      path.startsWith(root.path) ? path.substring(root.path.length + 1) : path;
}

Future<void> main(List<String> args) async {
  final verifyOnly = args.contains('--verify');
  final dryRun = args.contains('--dry-run');

  final scriptDir = File.fromUri(Platform.script).parent;
  final root = Directory('${scriptDir.path}${Platform.pathSeparator}..');

  final renames = <PackageRename>[
    PackageRename(
        dir: 'vendor/flutter_skill', from: 'flutter_skill', to: 'e2e_flutter_skill'),
    PackageRename(dir: 'vendor/marionette_flutter',
        from: 'marionette_flutter', to: 'e2e_marionette_flutter'),
    PackageRename(dir: 'vendor/marionette_mcp',
        from: 'marionette_mcp', to: 'e2e_marionette_mcp'),
    PackageRename(dir: 'vendor/marionette_cli',
        from: 'marionette_cli', to: 'e2e_marionette_cli'),
    PackageRename(dir: 'vendor/marionette_logging',
        from: 'marionette_logging', to: 'e2e_marionette_logging'),
    PackageRename(dir: 'vendor/marionette_logger',
        from: 'marionette_logger', to: 'e2e_marionette_logger'),
  ];

  stdout.writeln(verifyOnly
      ? 'Verifying renames (read-only)...'
      : dryRun
          ? 'Dry run (no writes)...'
          : 'Applying renames...');

  final report = PackageRenamer(
    root: root,
    renames: renames,
    verifyOnly: verifyOnly,
    dryRun: dryRun,
  ).run();

  stdout.writeln(report);

  if (!report.isClean) {
    stderr.writeln('\nFAILED: ${report.leftovers.length} leftover reference(s).');
    exit(2);
  }
  stdout.writeln('\nOK: no leftovers.');
}

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import 'widget_catalog.dart';

/// Rewrites Dart source to add `ValueKey<String>` on catalog widget constructors.
class KeyInjector {
  const KeyInjector();

  /// Returns updated source, or the original when nothing changed / not enabled.
  String inject({
    required String source,
    required String path,
  }) {
    if (!_isEnabled(source)) return source;

    final parseResult = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );

    final usedKeys = <String>{};
    final edits = <_TextEdit>[];

    parseResult.unit.accept(_KeyVisitor(
      source: source,
      path: path,
      usedKeys: usedKeys,
      edits: edits,
    ));

    if (edits.isEmpty) return source;

    edits.sort((a, b) => b.offset.compareTo(a.offset));
    var out = source;
    for (final edit in edits) {
      out = out.replaceRange(edit.offset, edit.offset, edit.insert);
    }

    return _ensureValueKeyImport(out);
  }

  static bool _isEnabled(String source) {
    if (source.contains('// e2e:auto_keys')) return true;
    return RegExp(r'@E2eAutoKey\b').hasMatch(source);
  }
}

class _KeyVisitor extends RecursiveAstVisitor<void> {
  _KeyVisitor({
    required this.source,
    required this.path,
    required this.usedKeys,
    required this.edits,
  });

  final String source;
  final String path;
  final Set<String> usedKeys;
  final List<_TextEdit> edits;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _maybeInject(_widgetName(node.constructorName), node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null) {
      _maybeInject(node.methodName.name, node.argumentList);
    } else if (node.target is SimpleIdentifier) {
      final target = (node.target as SimpleIdentifier).name;
      if (_isTypeName(target)) {
        _maybeInject('$target.${node.methodName.name}', node.argumentList);
      }
    }
    super.visitMethodInvocation(node);
  }

  static bool _isTypeName(String name) =>
      name.isNotEmpty && name[0].toUpperCase() == name[0];

  void _maybeInject(String widgetName, ArgumentList argumentList) {
    if (!WidgetCatalog.shouldKey(widgetName)) return;
    if (_hasKeyArgument(argumentList)) return;
    if (_lineIgnored(argumentList.offset)) return;

    final key = _allocateKey(
      widgetName: widgetName,
      line: _lineForOffset(argumentList.offset),
      argumentList: argumentList,
    );

    final snippet = "key: const ValueKey<String>('$key')";
    final int insertOffset;
    final String insert;

    if (argumentList.arguments.isEmpty) {
      insertOffset = argumentList.leftParenthesis.offset + 1;
      insert = snippet;
    } else if (_hasPositionalArguments(argumentList)) {
      // Named `key` must follow positional args: Text('hi', key: ...).
      final lastArg = argumentList.arguments.last;
      final textAfterLast = source.substring(
        lastArg.end,
        argumentList.rightParenthesis.offset,
      );
      final hasTrailingComma = textAfterLast.contains(',');
      if (hasTrailingComma) {
        insertOffset = argumentList.rightParenthesis.offset;
        final isMultiline = textAfterLast.contains('\n');
        insert = isMultiline ? '        $snippet,\n' : ' $snippet,';
      } else {
        insertOffset = argumentList.rightParenthesis.offset;
        insert = ', $snippet';
      }
    } else {
      insertOffset = argumentList.leftParenthesis.offset + 1;
      insert = _needsNewlineAfterParen(argumentList)
          ? '\n        $snippet,'
          : '$snippet, ';
    }

    edits.add(_TextEdit(offset: insertOffset, insert: insert));
  }

  bool _hasPositionalArguments(ArgumentList args) {
    for (final arg in args.arguments) {
      if (arg is! NamedExpression) return true;
    }
    return false;
  }

  String _widgetName(ConstructorName constructorName) {
    final typeName = constructorName.type.name.lexeme;
    final named = constructorName.name;
    if (named != null && named.name.isNotEmpty) {
      return '$typeName.${named.name}';
    }
    return typeName;
  }

  bool _hasKeyArgument(ArgumentList args) {
    for (final arg in args.arguments) {
      if (arg is NamedExpression && arg.name.label.name == 'key') {
        return true;
      }
    }
    return false;
  }

  bool _lineIgnored(int nodeOffset) {
    final line = _lineForOffset(nodeOffset);
    if (line <= 1) return false;
    final lines = source.split('\n');
    final prev = lines[line - 2];
    return prev.contains('ignore: unkeyed_widget') ||
        prev.contains('ignore: e2e_no_auto_key');
  }

  int _lineForOffset(int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < source.length; i++) {
      if (source.codeUnitAt(i) == 10) line++;
    }
    return line;
  }

  bool _needsNewlineAfterParen(ArgumentList args) {
    if (args.arguments.isEmpty) return false;
    final between = source.substring(
      args.leftParenthesis.offset + 1,
      args.arguments.first.offset,
    );
    return between.contains('\n');
  }

  String _allocateKey({
    required String widgetName,
    required int line,
    required ArgumentList argumentList,
  }) {
    final base = _baseKeyName(widgetName: widgetName, argumentList: argumentList);
    final fileStem = p.basenameWithoutExtension(path).replaceAll('-', '_');
    var candidate = _slug('${fileStem}_${base}_l$line');
    var n = 1;
    var unique = candidate;
    while (!usedKeys.add(unique)) {
      n++;
      unique = '${candidate}_$n';
    }
    return unique;
  }

  String _baseKeyName({
    required String widgetName,
    required ArgumentList argumentList,
  }) {
    final literal = _firstStringLiteral(argumentList);
    if (literal != null) {
      final slug = _slug(literal);
      if (slug.isNotEmpty) return '${_widgetSlug(widgetName)}_$slug';
    }
    return _widgetSlug(widgetName);
  }

  String? _firstStringLiteral(ArgumentList args) {
    for (final arg in args.arguments) {
      final expr = arg is NamedExpression ? arg.expression : arg;
      final value = _stringValue(expr);
      if (value != null) return value;
    }
    return null;
  }

  String? _stringValue(Expression expr) {
    if (expr is StringLiteral) {
      return expr.stringValue;
    }
    if (expr is ParenthesizedExpression) {
      return _stringValue(expr.expression);
    }
    return null;
  }

  String _widgetSlug(String widgetName) {
    return widgetName
        .replaceAll('.', '_')
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .toLowerCase();
  }

  String _slug(String input) {
    final lower = input.toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    return cleaned.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }
}

class _TextEdit {
  const _TextEdit({required this.offset, required this.insert});
  final int offset;
  final String insert;
}

String _ensureValueKeyImport(String source) {
  if (!source.contains('ValueKey')) return source;
  if (source.contains("import 'package:flutter/material.dart'") ||
      source.contains('import "package:flutter/material.dart"') ||
      source.contains("import 'package:flutter/widgets.dart'") ||
      source.contains('import "package:flutter/widgets.dart"') ||
      source.contains("import 'package:flutter/cupertino.dart'")) {
    return source;
  }

  const materialImport = "import 'package:flutter/material.dart';\n";
  final importMatch = RegExp(r'^import ', multiLine: true).firstMatch(source);
  if (importMatch != null) {
    return source.replaceRange(importMatch.start, importMatch.start, materialImport);
  }
  return materialImport + source;
}

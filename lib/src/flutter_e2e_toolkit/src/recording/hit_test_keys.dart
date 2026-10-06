import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Finds the nearest [ValueKey<String>] containing [position].
String? valueKeyAtGlobalPosition(Offset position) {
  final targets = keyedGesturesAt(position);
  if (targets.isEmpty) return null;
  return targets.first.key;
}

/// Reads editable text from a focused [FocusNode], when available.
String? textFromFocus(FocusNode? focus) {
  if (focus == null) return null;
  final context = focus.context;
  if (context == null || !context.mounted) return null;

  try {
    final editable = context.findAncestorStateOfType<EditableTextState>();
    return editable?.textEditingValue.text;
  } catch (_) {
    return null;
  }
}

/// Nearest [ValueKey<String>] on the focus widget chain.
String? valueKeyFromFocus(FocusNode? focus) {
  if (focus == null) return null;
  final context = focus.context;
  if (context == null || !context.mounted) return null;

  try {
    final selfKey = context.widget.key;
    if (selfKey is ValueKey<String>) return selfKey.value;

    String? found;
    context.visitAncestorElements((ancestor) {
      if (!ancestor.mounted) return false;
      try {
        final key = ancestor.widget.key;
        if (key is ValueKey<String>) {
          found = key.value;
          return false;
        }
      } catch (_) {
        return false;
      }
      return true;
    });
    return found;
  } catch (_) {
    return null;
  }
}

/// Gestures a widget will actually handle. Used so the recorder emits
/// Marionette actions that change state, and skips keyed widgets that ignore
/// the pointer (static tiles, plain text, read-only fields).
class GestureAffordances {
  const GestureAffordances({
    this.tap = false,
    this.doubleTap = false,
    this.secondaryTap = false,
    this.longPress = false,
    this.horizontalDrag = false,
    this.verticalDrag = false,
    this.scale = false,
    this.readOnly = false,
  });

  final bool tap;
  final bool doubleTap;
  final bool secondaryTap;
  final bool longPress;
  final bool horizontalDrag;
  final bool verticalDrag;
  final bool scale;
  final bool readOnly;

  GestureAffordances merge(GestureAffordances other) {
    return GestureAffordances(
      tap: tap || other.tap,
      doubleTap: doubleTap || other.doubleTap,
      secondaryTap: secondaryTap || other.secondaryTap,
      longPress: longPress || other.longPress,
      horizontalDrag: horizontalDrag || other.horizontalDrag,
      verticalDrag: verticalDrag || other.verticalDrag,
      scale: scale || other.scale,
      readOnly: readOnly || other.readOnly,
    );
  }
}

/// A [ValueKey<String>] and the gestures available from the hit leaf up through
/// that key.
class KeyedGestureTarget {
  const KeyedGestureTarget(this.key, this.affordances);

  final String key;
  final GestureAffordances affordances;
}

/// Keyed ancestors under [position], deepest first.
///
/// Affordances accumulate from the leaf, so a keyed [PageView] still reports
/// a horizontal drag when the hit landed on an inner keyed [Text].
List<KeyedGestureTarget> keyedGesturesAt(Offset position) {
  final root = WidgetsBinding.instance.rootElement;
  if (root != null) {
    final leaf = _deepestElementAt(root, position);
    if (leaf != null) {
      final targets = _targetsFrom(leaf);
      if (targets.isNotEmpty) return targets;
    }
  }
  return _targetsFromHitTest(position);
}

List<KeyedGestureTarget> _targetsFrom(Element leaf) {
  final chain = <Element>[leaf];
  leaf.visitAncestorElements((ancestor) {
    chain.add(ancestor);
    return true;
  });

  var acc = const GestureAffordances();
  final targets = <KeyedGestureTarget>[];
  for (final element in chain) {
    if (!element.mounted) break;
    acc = acc.merge(_affordanceOf(element.widget));
    final key = element.widget.key;
    if (key is ValueKey<String>) {
      targets.add(KeyedGestureTarget(key.value, acc));
    }
  }
  return targets;
}

List<KeyedGestureTarget> _targetsFromHitTest(Offset position) {
  try {
    final binding = WidgetsBinding.instance;
    final views = binding.platformDispatcher.views;
    final view = views.isNotEmpty
        ? views.first
        : binding.platformDispatcher.implicitView;
    if (view == null) return const [];

    final result = HitTestResult();
    binding.hitTestInView(result, position, view.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderObject) continue;
      Element? element;
      try {
        final dynamic creator = target.debugCreator;
        if (creator != null) {
          element = creator.element as Element?;
        }
      } catch (_) {}
      if (element == null || !element.mounted) continue;
      final targets = _targetsFrom(element);
      if (targets.isNotEmpty) return targets;
    }
  } catch (_) {}
  return const [];
}

/// First key in [targets] whose affordance matches [test].
String? firstKeyWhere(
  List<KeyedGestureTarget> targets,
  bool Function(GestureAffordances affordances) test,
) {
  for (final target in targets) {
    if (test(target.affordances)) return target.key;
  }
  return null;
}

Element? _deepestElementAt(Element element, Offset globalPos) {
  final ro = element.renderObject;
  // RenderView is not a RenderBox. Keep walking so the app content is reached.
  if (ro is RenderBox) {
    if (!ro.hasSize || !ro.attached) return null;
    try {
      final local = ro.globalToLocal(globalPos);
      if (!ro.paintBounds.contains(local)) return null;
    } catch (_) {
      return null;
    }
  }

  Element? childHit;
  element.visitChildren((child) {
    final hit = _deepestElementAt(child, globalPos);
    if (hit != null) childHit = hit;
  });
  if (childHit != null) return childHit;
  return ro is RenderBox ? element : null;
}

GestureAffordances _affordanceOf(Widget widget) {
  if (widget is GestureDetector) {
    return GestureAffordances(
      tap: widget.onTap != null || widget.onTapUp != null,
      doubleTap: widget.onDoubleTap != null,
      secondaryTap: widget.onSecondaryTap != null ||
          widget.onSecondaryTapUp != null,
      longPress: widget.onLongPress != null,
      horizontalDrag: widget.onHorizontalDragUpdate != null ||
          widget.onPanUpdate != null,
      verticalDrag: widget.onVerticalDragUpdate != null ||
          widget.onPanUpdate != null,
      scale: widget.onScaleUpdate != null || widget.onScaleEnd != null,
    );
  }
  if (widget is InkWell) {
    return GestureAffordances(
      tap: widget.onTap != null,
      doubleTap: widget.onDoubleTap != null,
      secondaryTap: widget.onSecondaryTap != null,
      longPress: widget.onLongPress != null,
    );
  }
  if (widget is ButtonStyleButton) {
    return GestureAffordances(
      tap: widget.onPressed != null,
      longPress: widget.onLongPress != null,
    );
  }
  if (widget is IconButton) {
    return GestureAffordances(
      tap: widget.onPressed != null,
      longPress: widget.onLongPress != null,
    );
  }
  if (widget is ListTile) {
    return GestureAffordances(
      tap: widget.onTap != null,
      longPress: widget.onLongPress != null,
    );
  }
  if (widget is EditableText) {
    return GestureAffordances(
      tap: !widget.readOnly,
      readOnly: widget.readOnly,
    );
  }
  if (widget is TextField) {
    return GestureAffordances(tap: !widget.readOnly, readOnly: widget.readOnly);
  }
  if (widget is Switch ||
      widget is Checkbox ||
      widget is Radio<dynamic> ||
      widget is Slider ||
      widget is DropdownButton<dynamic>) {
    return const GestureAffordances(tap: true);
  }
  if (widget is Dismissible) {
    return const GestureAffordances(horizontalDrag: true);
  }
  if (widget is PageView) {
    return const GestureAffordances(horizontalDrag: true);
  }
  if (widget is ScrollView) {
    final horizontal = widget.scrollDirection == Axis.horizontal;
    return GestureAffordances(
      horizontalDrag: horizontal,
      verticalDrag: !horizontal,
    );
  }
  return const GestureAffordances();
}

/// True when the focused field cannot accept typing.
bool focusIsReadOnly(FocusNode? focus) {
  if (focus == null) return false;
  final context = focus.context;
  if (context == null || !context.mounted) return false;
  try {
    final editable = context.findAncestorStateOfType<EditableTextState>();
    return editable?.widget.readOnly ?? false;
  } catch (_) {
    return false;
  }
}

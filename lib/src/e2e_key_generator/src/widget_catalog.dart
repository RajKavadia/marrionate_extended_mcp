/// Widget constructors that should carry a [ValueKey<String>] for e2e tooling.
class WidgetCatalog {
  const WidgetCatalog._();

  /// Interactive widgets (buttons, fields, touch targets, gestures, pickers).
  static const Set<String> interactive = {
    // Buttons
    'ElevatedButton',
    'FilledButton',
    'OutlinedButton',
    'TextButton',
    'IconButton',
    'FloatingActionButton',
    'SegmentedButton',
    'RawMaterialButton',
    'CupertinoButton',
    'PopupMenuButton',
    'MenuAnchor',
    'BackButton',
    'CloseButton',

    // Form fields and pickers
    'TextField',
    'TextFormField',
    'CupertinoTextField',
    'SearchBar',
    'SearchAnchor',
    'DropdownButton',
    'DropdownButtonFormField',
    'DropdownMenu',
    'Slider',
    'RangeSlider',
    'Switch',
    'SwitchListTile',
    'Checkbox',
    'CheckboxListTile',
    'Radio',
    'RadioListTile',
    'RadioGroup',

    // Touch targets and gestures
    'GestureDetector',
    'InkWell',
    'InkResponse',
    'ListTile',
    'Card',
    'Dismissible',
    'Draggable',
    'LongPressDraggable',
    'DragTarget',
    'InteractiveViewer',

    // Chips
    'Chip',
    'ActionChip',
    'FilterChip',
    'ChoiceChip',
    'InputChip',
  };

  /// Observable and structural widgets (assertions, scroll, lists, containers).
  static const Set<String> observable = {
    // Text and content
    'Text',
    'RichText',
    'SelectableText',
    'Image',
    'Icon',

    // Scrolling and views
    'ListView',
    'GridView',
    'PageView',
    'Scrollbar',
    'RawScrollbar',
    'CupertinoScrollbar',
    'SingleChildScrollView',
    'CustomScrollView',
    'ReorderableListView',
    'RefreshIndicator',

    // Layout and structure
    'Scaffold',
    'AppBar',
    'SliverAppBar',
    'Drawer',
    'BottomNavigationBar',
    'NavigationBar',
    'TabBar',
    'Tab',
    'Column',
    'Row',
    'Wrap',
    'Stack',
    'Expanded',
    'Flexible',
    'SizedBox',
    'Container',
    'Padding',
    'Center',
    'Align',
    'FractionallySizedBox',
    'AspectRatio',

    // Complex / data
    'Table',
    'DataTable',
    'Form',
    'Stepper',
    'ExpansionTile',
  };

  static final Set<String> all = {...interactive, ...observable};

  /// Returns true if [widgetName] or its base class is in the catalog.
  ///
  /// Supports bare constructors ('ListView') and named ones ('ListView.builder',
  /// 'FilledButton.tonal', 'Radio.adaptive').
  static bool shouldKey(String widgetName) {
    if (all.contains(widgetName)) return true;
    final dot = widgetName.indexOf('.');
    if (dot > 0) {
      final base = widgetName.substring(0, dot);
      return all.contains(base);
    }
    return false;
  }
}

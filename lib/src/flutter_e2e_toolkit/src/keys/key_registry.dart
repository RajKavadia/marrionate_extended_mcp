/// The set of [ValueKey]s every e2e scenario is allowed to target.
///
/// The governing rule for this project: anything a tool can interact with, or
/// that an assertion can observe, carries a stable `ValueKey<String>`. Keys are
/// the only selector the scenarios use — never text or coordinates — so a copy
/// change cannot silently break a test.
///
/// This registry is the machine-readable form of that rule. [requiredKeys] is
/// the inventory, [ScenarioValidator] checks scenarios against it, and
/// `tool/check_keys.dart` checks the app's widgets against it.
class KeyRegistry {
  const KeyRegistry._();

  /// Every key the demo app guarantees, grouped by owning screen.
  ///
  /// Keyed entries are `screen -> key`. Screen names match the route names in
  /// the app so a failure points at an unambiguous location.
  static const Map<String, List<String>> requiredKeys = {
    'home': [
      'home_screen',
      'home_profile',
      'home_settings',
      'home_notifications',
    ],
    'profile': [
      'profile_screen',
      'name_field',
      'email_field',
      'bio_field',
      'readonly_field',
      'submit_button',
      'profile_result',
    ],
    'settings': [
      'settings_screen',
      'settings_items',
      'settings_notifications',
      'settings_page_view',
      'settings_dismissible',
      'settings_pinch_zoom',
      'settings_mouse_tap',
      'settings_scoped_matching',
      'settings_custom_widgets',
      'settings_appearance',
      'settings_about',
    ],
    'notifications': [
      'notifications_screen',
      'push_notifications_switch',
      'email_notifications_switch',
      'inapp_notifications_switch',
      'notifications_state',
    ],
    'items': [
      'items_screen',
      'items_counter',
      'items_increment',
      'items_list',
      'item_0',
      'item_1',
      'item_2',
      'item_row_0',
      'item_row_1',
      'item_row_2',
    ],
    'page_view': [
      'page_view_screen',
      'page_view',
      'page_view_next',
      'page_0',
      'page_1',
      'page_2',
    ],
    'pinch_zoom': [
      'pinch_zoom_screen',
      'zoomable',
      'scale_text',
      'reset_zoom_button',
    ],
    'mouse_tap': [
      'mouse_tap_screen',
      'mouse_tap_target',
      'secondary_tap_count',
      'reset_secondary_button',
    ],
    'scoped_matching': [
      'scoped_matching_screen',
      'scoped_card_a',
      'scoped_card_b',
      'scoped_card_c',
      'scoped_child',
      'scoped_switch',
    ],
    'custom_widgets': [
      'custom_widgets_screen',
      'ds_tile_tappable',
      'ds_tile_static',
      'ds_tile_tap_count',
    ],
    'about': [
      'about_screen',
      'about_version',
      'about_settings_button',
    ],
  };

  /// Keys that appear more than once in the widget tree.
  ///
  /// These are only addressable when the lookup is scoped to an ancestor key,
  /// so the validator does not reject them and scenarios must pair them with an
  /// ancestor. Recorded here so tooling can surface the requirement.
  static const Set<String> ambiguousKeys = {
    'scoped_child',
    'scoped_switch',
  };

  /// Flat view of every required key.
  static final Set<String> allKeys = {
    for (final keys in requiredKeys.values) ...keys,
  };

  /// Screens that contribute at least one key.
  static List<String> get screens => requiredKeys.keys.toList()..sort();

  /// Keys belonging to [screen], or an empty list when unknown.
  static List<String> keysForScreen(String screen) =>
      requiredKeys[screen] ?? const [];

  /// Whether [key] appears in the inventory.
  static bool isKnown(String key) => allKeys.contains(key);

  /// Which screen owns [key], or null when unknown.
  static String? screenForKey(String key) {
    for (final entry in requiredKeys.entries) {
      if (entry.value.contains(key)) return entry.key;
    }
    return null;
  }

  /// Given keys referenced by scenarios, returns those absent from the
  /// inventory.
  static Set<String> unknownKeysIn(Iterable<String> keys) =>
      keys.where((k) => !isKnown(k)).toSet();

  /// Throws [StateError] listing any gap, for use in tests.
  static void assertComplete() {
    final duplicates = <String>[];
    final seen = <String>{};
    for (final keys in requiredKeys.values) {
      for (final key in keys) {
        if (!seen.add(key)) duplicates.add(key);
      }
    }
    if (duplicates.isNotEmpty) {
      throw StateError(
        'KeyRegistry contains duplicate keys: ${duplicates.join(", ")}. '
        'Duplicate keys make scenario targeting ambiguous.',
      );
    }
  }
}

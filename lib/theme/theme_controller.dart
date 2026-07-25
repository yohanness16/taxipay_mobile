import 'package:flutter/material.dart';

import '../db/database_helper.dart';

/// Owns the app's current [ThemeMode] (light / dark / follow system) and
/// persists the choice through the same lightweight key-value settings
/// store already used for other app preferences -- no extra dependency
/// needed just for "remember one enum value".
///
/// Defaults to dark: the black-and-green look is the app's primary,
/// intended aesthetic; light is offered as an alternative for drivers who
/// prefer it, not the other way around.
class ThemeController extends ChangeNotifier {
  static const String _settingKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final raw = await DatabaseHelper.instance.getSetting(_settingKey);
    _mode = switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await DatabaseHelper.instance.setSetting(_settingKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}

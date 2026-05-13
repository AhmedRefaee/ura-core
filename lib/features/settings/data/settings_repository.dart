import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const String _darkModeKey = 'isDarkMode';

  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  bool isDarkMode() {
    return _prefs.getBool(_darkModeKey) ?? false;
  }

  Future<bool> setDarkMode(bool value) {
    return _prefs.setBool(_darkModeKey, value);
  }
}

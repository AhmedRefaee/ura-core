import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/profile.dart';

class LocalProfileSource {
  static const _key = 'cached_profile';

  final SharedPreferences _prefs;
  const LocalProfileSource(this._prefs);

  Profile? get() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return Profile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Profile profile) async {
    await _prefs.setString(_key, jsonEncode(profile.toMap()));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}

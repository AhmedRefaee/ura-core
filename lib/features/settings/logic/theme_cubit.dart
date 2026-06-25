import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../data/settings_repository.dart';

import '../../../core/logic/safe_emit.dart';
part 'theme_state.dart';

class ThemeCubit extends Cubit<ThemeState> with SafeEmit<ThemeState> {
  final SettingsRepository _repository;

  ThemeCubit(this._repository)
    : super(ThemeState(isDarkMode: _repository.isDarkMode()));

  Future<void> toggleDarkMode() async {
    final newValue = !state.isDarkMode;
    await _repository.setDarkMode(newValue);
    if (!isClosed) {
      safeEmit(ThemeState(isDarkMode: newValue));
    }
  }

  void initializeTheme() {
    final isDark = _repository.isDarkMode();
    if (!isClosed) {
      safeEmit(ThemeState(isDarkMode: isDark));
    }
  }
}

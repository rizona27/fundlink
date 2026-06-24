import 'package:flutter/foundation.dart';
import '../services/database_repository.dart';
import '../widgets/theme_switch.dart' show ThemeMode;

/// Manages user settings (privacy, theme, display preferences) with ChangeNotifier.
class SettingsNotifier extends ChangeNotifier {
  final DatabaseRepository? _repository;
  bool _isPrivacyMode = true;
  ThemeMode _themeMode = ThemeMode.system;
  bool _showHoldersOnSummaryCard = true;
  bool _disposed = false;

  SettingsNotifier(this._repository);

  bool get isPrivacyMode => _isPrivacyMode;
  ThemeMode get themeMode => _themeMode;
  bool get showHoldersOnSummaryCard => _showHoldersOnSummaryCard;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _initFields({
    required bool isPrivacyMode,
    required ThemeMode themeMode,
    required bool showHoldersOnSummaryCard,
  }) {
    _isPrivacyMode = isPrivacyMode;
    _themeMode = themeMode;
    _showHoldersOnSummaryCard = showHoldersOnSummaryCard;
  }

  // Called by DataManager after loading from DB/Prefs
  void loadFromValues({
    required bool isPrivacyMode,
    required ThemeMode themeMode,
    required bool showHoldersOnSummaryCard,
  }) {
    _initFields(
      isPrivacyMode: isPrivacyMode,
      themeMode: themeMode,
      showHoldersOnSummaryCard: showHoldersOnSummaryCard,
    );
  }

  Future<void> togglePrivacyMode() async {
    if (_disposed) return;
    _isPrivacyMode = !_isPrivacyMode;

    if (!kIsWeb) {
      await _repository!.saveSetting('privacy_mode', _isPrivacyMode.toString());
    }

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_disposed) return;
    if (_themeMode == mode) return;
    _themeMode = mode;

    if (!kIsWeb) {
      await _repository!.saveSetting('theme_mode', _themeModeToString(mode));
    }

    notifyListeners();
  }

  Future<void> setShowHoldersOnSummaryCard(bool value) async {
    if (_disposed) return;
    if (_showHoldersOnSummaryCard == value) return;
    _showHoldersOnSummaryCard = value;

    if (!kIsWeb) {
      await _repository!.saveSetting(
          'show_holders_on_summary', value.toString());
    }

    notifyListeners();
  }

  String obscuredName(String name) {
    if (!_isPrivacyMode || name.isEmpty) return name;

    final firstChar = name[0];
    if (name.length == 1) return name;

    return '$firstChar${'*' * (name.length - 1)}';
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

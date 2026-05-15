import '../services/database_repository.dart';

class UIStateService {
  static final UIStateService _instance = UIStateService._internal();
  factory UIStateService() => _instance;
  UIStateService._internal();
  
  final DatabaseRepository _repository = DatabaseRepository();
  
  Future<void> saveBool(String key, bool value) async {
    try {
      await _repository.saveSetting('ui_$key', value.toString());
    } catch (e) {
    }
  }
  
  Future<bool?> getBool(String key) async {
    try {
      final value = await _repository.getSetting('ui_$key');
      if (value == null) return null;
      return value == 'true';
    } catch (e) {
      return null;
    }
  }
  
  Future<void> saveString(String key, String value) async {
    try {
      await _repository.saveSetting('ui_$key', value);
    } catch (e) {
    }
  }
  
  Future<String?> getString(String key) async {
    try {
      return await _repository.getSetting('ui_$key');
    } catch (e) {
      return null;
    }
  }
  
  Future<void> saveInt(String key, int value) async {
    try {
      await _repository.saveSetting('ui_$key', value.toString());
    } catch (e) {
    }
  }
  
  Future<int?> getInt(String key) async {
    try {
      final value = await _repository.getSetting('ui_$key');
      if (value == null) return null;
      return int.tryParse(value);
    } catch (e) {
      return null;
    }
  }
  
  Future<void> remove(String key) async {
    try {
      await _repository.saveSetting('ui_$key', '');
    } catch (e) {
    }
  }
}

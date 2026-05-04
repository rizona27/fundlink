import 'package:flutter/foundation.dart';
import '../services/database_repository.dart';

/// UI 状态管理服务 - 使用 SQLite 存储 UI 状态
class UIStateService {
  static final UIStateService _instance = UIStateService._internal();
  factory UIStateService() => _instance;
  UIStateService._internal();
  
  final DatabaseRepository _repository = DatabaseRepository();
  
  /// 保存布尔状态
  Future<void> saveBool(String key, bool value) async {
    try {
      await _repository.saveSetting('ui_$key', value.toString());
    } catch (e) {
      debugPrint('保存UI状态失败: $key = $value, 错误: $e');
    }
  }
  
  /// 获取布尔状态
  Future<bool?> getBool(String key) async {
    try {
      final value = await _repository.getSetting('ui_$key');
      if (value == null) return null;
      return value == 'true';
    } catch (e) {
      debugPrint('获取UI状态失败: $key, 错误: $e');
      return null;
    }
  }
  
  /// 保存字符串状态
  Future<void> saveString(String key, String value) async {
    try {
      await _repository.saveSetting('ui_$key', value);
    } catch (e) {
      debugPrint('保存UI状态失败: $key, 错误: $e');
    }
  }
  
  /// 获取字符串状态
  Future<String?> getString(String key) async {
    try {
      return await _repository.getSetting('ui_$key');
    } catch (e) {
      debugPrint('获取UI状态失败: $key, 错误: $e');
      return null;
    }
  }
  
  /// 保存整数状态
  Future<void> saveInt(String key, int value) async {
    try {
      await _repository.saveSetting('ui_$key', value.toString());
    } catch (e) {
      debugPrint('保存UI状态失败: $key, 错误: $e');
    }
  }
  
  /// 获取整数状态
  Future<int?> getInt(String key) async {
    try {
      final value = await _repository.getSetting('ui_$key');
      if (value == null) return null;
      return int.tryParse(value);
    } catch (e) {
      debugPrint('获取UI状态失败: $key, 错误: $e');
      return null;
    }
  }
  
  /// 删除状态
  Future<void> remove(String key) async {
    try {
      // 注意：DatabaseRepository 需要添加 deleteSetting 方法
      // 暂时通过保存空值实现
      await _repository.saveSetting('ui_$key', '');
    } catch (e) {
      debugPrint('删除UI状态失败: $key, 错误: $e');
    }
  }
}

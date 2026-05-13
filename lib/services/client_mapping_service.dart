import 'dart:convert';
import '../models/client_mapping.dart';
import '../constants/app_constants.dart';
import '../services/database_repository.dart';
import 'package:uuid/uuid.dart';

/// 客户映射词典服务 - 使用 SQLite 数据库存储
/// 
/// 数据存储位置：database settings 表
/// Key: client_mappings
/// Value: JSON 数组字符串
class ClientMappingService {
  static final Uuid _uuid = const Uuid();
  final DatabaseRepository _repository = DatabaseRepository();

  /// 获取所有映射关系
  Future<List<ClientMapping>> getAllMappings() async {
    try {
      final jsonString = await _repository.getSetting(AppConstants.keyClientMappings);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => ClientMapping.fromJson(json)).toList();
    } catch (e) {
      print('获取映射词典失败: $e');
      return [];
    }
  }

  /// 保存所有映射关系
  Future<void> saveAllMappings(List<ClientMapping> mappings) async {
    try {
      final jsonList = mappings.map((m) => m.toJson()).toList();
      await _repository.saveSetting(
        AppConstants.keyClientMappings,
        jsonEncode(jsonList),
      );
    } catch (e) {
      print('保存映射词典失败: $e');
      rethrow;
    }
  }

  /// 添加映射关系
  Future<ClientMapping> addMapping(String clientId, String clientName) async {
    final mappings = await getAllMappings();
    
    // 检查是否已存在相同的客户号
    final existingIndex = mappings.indexWhere((m) => m.clientId == clientId);
    
    final newMapping = ClientMapping(
      id: _uuid.v4(),
      clientId: clientId,
      clientName: clientName,
    );

    if (existingIndex != -1) {
      // 更新现有映射
      mappings[existingIndex] = newMapping.copyWith(
        createdAt: mappings[existingIndex].createdAt,
      );
    } else {
      // 添加新映射
      mappings.add(newMapping);
    }

    await saveAllMappings(mappings);
    return newMapping;
  }

  /// 更新映射关系
  Future<void> updateMapping(String id, String clientId, String clientName) async {
    final mappings = await getAllMappings();
    final index = mappings.indexWhere((m) => m.id == id);
    
    if (index == -1) {
      throw Exception('映射关系不存在');
    }

    mappings[index] = mappings[index].copyWith(
      clientId: clientId,
      clientName: clientName,
      updatedAt: DateTime.now(),
    );

    await saveAllMappings(mappings);
  }

  /// 删除映射关系
  Future<void> deleteMapping(String id) async {
    final mappings = await getAllMappings();
    mappings.removeWhere((m) => m.id == id);
    await saveAllMappings(mappings);
  }

  /// 根据客户号查找客户名
  Future<String?> getClientNameByClientId(String clientId) async {
    final mappings = await getAllMappings();
    final mapping = mappings.firstWhere(
      (m) => m.clientId == clientId,
      orElse: () => throw Exception('未找到映射'),
    );
    return mapping.clientName;
  }

  /// 根据客户名查找所有匹配的映射关系（支持同名不同客户号）
  Future<List<ClientMapping>> getMappingsByClientName(String clientName) async {
    final mappings = await getAllMappings();
    return mappings.where((m) => m.clientName == clientName).toList();
  }

  /// 检查客户号是否存在
  Future<bool> existsByClientId(String clientId) async {
    try {
      await getClientNameByClientId(clientId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 清除所有映射
  Future<void> clearAll() async {
    await _repository.saveSetting(AppConstants.keyClientMappings, '');
  }
}

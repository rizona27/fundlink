import 'dart:convert';
import '../models/client_mapping.dart';
import '../constants/app_constants.dart';
import '../services/database_repository.dart';
import 'package:uuid/uuid.dart';

class ClientMappingService {
  static final Uuid _uuid = const Uuid();
  final DatabaseRepository _repository = DatabaseRepository();

  Future<List<ClientMapping>> getAllMappings() async {
    try {
      final jsonString = await _repository.getSetting(AppConstants.keyClientMappings);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => ClientMapping.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAllMappings(List<ClientMapping> mappings) async {
    try {
      final jsonList = mappings.map((m) => m.toJson()).toList();
      await _repository.saveSetting(
        AppConstants.keyClientMappings,
        jsonEncode(jsonList),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<ClientMapping> addMapping(String clientId, String clientName) async {
    final mappings = await getAllMappings();
    
    final existingIndex = mappings.indexWhere((m) => m.clientId == clientId);
    
    final newMapping = ClientMapping(
      id: _uuid.v4(),
      clientId: clientId,
      clientName: clientName,
    );

    if (existingIndex != -1) {
      mappings[existingIndex] = newMapping.copyWith(
        createdAt: mappings[existingIndex].createdAt,
      );
    } else {
      mappings.add(newMapping);
    }

    await saveAllMappings(mappings);
    return newMapping;
  }

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

  Future<void> deleteMapping(String id) async {
    final mappings = await getAllMappings();
    mappings.removeWhere((m) => m.id == id);
    await saveAllMappings(mappings);
  }

  Future<String?> getClientNameByClientId(String clientId) async {
    final mappings = await getAllMappings();
    final mapping = mappings.firstWhere(
      (m) => m.clientId == clientId,
      orElse: () => throw Exception('未找到映射'),
    );
    return mapping.clientName;
  }

  Future<List<ClientMapping>> getMappingsByClientName(String clientName) async {
    final mappings = await getAllMappings();
    return mappings.where((m) => m.clientName == clientName).toList();
  }

  Future<bool> existsByClientId(String clientId) async {
    try {
      await getClientNameByClientId(clientId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> clearAll() async {
    await _repository.saveSetting(AppConstants.keyClientMappings, '');
  }
}

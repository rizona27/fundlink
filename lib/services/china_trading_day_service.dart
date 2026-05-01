import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:world_holidays/world_holidays.dart';

/// 中国交易日判断服务
/// 采用三层降级策略：
/// 1. 专业节假日 API（包含调休补班信息）
/// 2. world_holidays 包（法定节假日）
/// 3. 本地周一到周五判断（兜底方案）
class ChinaTradingDayService {
  static final ChinaTradingDayService _instance = ChinaTradingDayService._internal();
  
  factory ChinaTradingDayService() {
    return _instance;
  }
  
  ChinaTradingDayService._internal();
  
  final WorldHolidays _worldHolidays = WorldHolidays();
  
  // 缓存：日期字符串 -> 是否交易日
  final Map<String, bool> _cache = {};
  
  /// 判断指定日期是否为中国 A 股交易日
  /// 
  /// 返回 true 表示是交易日，false 表示非交易日
  /// 
  /// 判断逻辑（按优先级）：
  /// 1. 尝试使用 timor.tech API 获取准确的交易日信息（包含调休补班）
  /// 2. 如果 API 失败，使用 world_holidays 判断法定节假日
  /// 3. 如果都失败，使用基础的周一到周五判断
  Future<bool> isTradingDay(DateTime date) async {
    // 先检查缓存
    final dateKey = _formatDate(date);
    if (_cache.containsKey(dateKey)) {
      // 缓存命中，不打印日志
      return _cache[dateKey]!;
    }
    
    bool result;
    try {
      // 第一层：尝试使用专业 API
      final apiResult = await _checkByApi(date);
      if (apiResult != null) {
        result = apiResult;
      } else {
        // API 返回 null，继续下一层
        throw Exception('API 返回 null');
      }
    } catch (e) {
      try {
        // 第二层：使用 world_holidays 包
        final holidayResult = _checkByWorldHolidays(date);
        if (holidayResult != null) {
          result = holidayResult;
        } else {
          // world_holidays 返回 null，使用兜底方案
          result = _checkByWeekday(date);
        }
      } catch (e) {
        // 第三层：使用基础判断（兜底方案）
        result = _checkByWeekday(date);
      }
    }
    
    // 存入缓存
    _cache[dateKey] = result;
    return result;
  }
  
  /// 批量判断多个日期是否为交易日
  Future<List<bool>> isTradingDays(List<DateTime> dates) async {
    final results = <bool>[];
    for (final date in dates) {
      results.add(await isTradingDay(date));
    }
    return results;
  }
  
  /// 获取下一个交易日
  Future<DateTime> getNextTradingDay({DateTime? from}) async {
    DateTime next = from ?? DateTime.now();
    // 从明天开始查找
    next = DateTime(next.year, next.month, next.day).add(const Duration(days: 1));
    
    // 最多查找 30 天
    for (int i = 0; i < 30; i++) {
      if (await isTradingDay(next)) {
        return next;
      }
      next = next.add(const Duration(days: 1));
    }
    
    // 如果找不到，返回 30 天后的日期
    return next;
  }
  
  /// 获取上一个交易日
  Future<DateTime> getPreviousTradingDay({DateTime? from}) async {
    DateTime previous = from ?? DateTime.now();
    // 从昨天开始查找
    previous = DateTime(previous.year, previous.month, previous.day).subtract(const Duration(days: 1));
    
    // 最多查找 30 天
    for (int i = 0; i < 30; i++) {
      if (await isTradingDay(previous)) {
        return previous;
      }
      previous = previous.subtract(const Duration(days: 1));
    }
    
    // 如果找不到，返回 30 天前的日期
    return previous;
  }
  
  // ==================== 私有方法 ====================
  
  /// 第一层：使用 timor.tech API 判断
  /// API 文档: https://timor.tech/api/holiday
  /// 
  /// 返回：
  /// - true: 是工作日/交易日
  /// - false: 是休息日/节假日
  /// - null: API 请求失败或数据不可用
  Future<bool?> _checkByApi(DateTime date) async {
    try {
      final dateString = _formatDate(date);
      final url = 'https://timor.tech/api/holiday/info/$dateString';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // API 返回格式：
        // {
        //   "code": 0,
        //   "type": {
        //     "type": 0,  // 0: 工作日, 1: 周末, 2: 节假日, 3: 调休工作日
        //     "name": "workday"
        //   }
        // }
        
        if (data['code'] == 0 && data['type'] != null) {
          final type = data['type']['type'];
          
          // type 说明：
          // 0: 工作日（包括正常工作日和调休补班）
          // 1: 周末
          // 2: 法定节假日
          // 3: 调休工作日（周末需要上班）
          
          // 对于基金交易来说，type 为 0 或 3 都是交易日
          final isWorkday = (type == 0 || type == 3);
          return isWorkday;
        }
      }
    } catch (e) {
      // API 异常，返回 null 让上层处理
    }
    
    return null;
  }
  
  /// 第二层：使用 world_holidays 包判断
  /// 
  /// 返回：
  /// - true: 可能是交易日（周一到周五且非法定节假日）
  /// - false: 确定不是交易日（周末或法定节假日）
  /// - null: 无法判断
  bool? _checkByWorldHolidays(DateTime date) {
    try {
      // 首先排除周末
      if (date.weekday == DateTime.saturday || 
          date.weekday == DateTime.sunday) {
        return false;
      }
      
      // 然后检查是否是法定节假日
      // 注意：world_holidays 不包含调休补班信息
      final isHoliday = _worldHolidays.isHoliday('CN', date);
      
      if (isHoliday) {
        return false; // 法定节假日，不是交易日
      }
      
      // 周一到周五且非法定节假日
      // 但无法确定是否有调休补班，所以返回 null 让下一层处理
      // 这里我们保守地认为是交易日
      return true;
    } catch (e) {
      return null;
    }
  }
  
  /// 第三层：基础判断（兜底方案）
  /// 只判断周一到周五
  bool _checkByWeekday(DateTime date) {
    return date.weekday >= DateTime.monday && 
           date.weekday <= DateTime.friday;
  }
  
  /// 格式化日期为 yyyy-MM-dd
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

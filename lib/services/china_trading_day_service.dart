import 'dart:convert';
import 'package:world_holidays/world_holidays.dart';
import 'http_client_provider.dart';

class ChinaTradingDayService {
  static final ChinaTradingDayService _instance = ChinaTradingDayService._internal();
  
  factory ChinaTradingDayService() {
    return _instance;
  }
  
  ChinaTradingDayService._internal();
  
  final WorldHolidays _worldHolidays = WorldHolidays();
  
  final Map<String, bool> _cache = {};
  
  Future<bool> isTradingDay(DateTime date) async {
    final dateKey = _formatDate(date);
    if (_cache.containsKey(dateKey)) {
      return _cache[dateKey]!;
    }
    
    bool result;
    try {
      final apiResult = await _checkByApi(date);
      if (apiResult != null) {
        result = apiResult;
      } else {
        throw Exception('API 返回 null');
      }
    } catch (e) {
      try {
        final holidayResult = _checkByWorldHolidays(date);
        if (holidayResult != null) {
          result = holidayResult;
        } else {
          result = _checkByWeekday(date);
        }
      } catch (e) {
        result = _checkByWeekday(date);
      }
    }
    
    _cache[dateKey] = result;
    return result;
  }
  
  Future<List<bool>> isTradingDays(List<DateTime> dates) async {
    final results = <bool>[];
    for (final date in dates) {
      results.add(await isTradingDay(date));
    }
    return results;
  }
  
  Future<DateTime> getNextTradingDay({DateTime? from}) async {
    DateTime next = from ?? DateTime.now();
    next = DateTime(next.year, next.month, next.day).add(const Duration(days: 1));
    
    for (int i = 0; i < 30; i++) {
      if (await isTradingDay(next)) {
        return next;
      }
      next = next.add(const Duration(days: 1));
    }
    
    return next;
  }
  
  Future<DateTime> getPreviousTradingDay({DateTime? from}) async {
    DateTime previous = from ?? DateTime.now();
    previous = DateTime(previous.year, previous.month, previous.day).subtract(const Duration(days: 1));
    
    for (int i = 0; i < 30; i++) {
      if (await isTradingDay(previous)) {
        return previous;
      }
      previous = previous.subtract(const Duration(days: 1));
    }
    
    return previous;
  }
  
  DateTime getNextTradingDaySync({DateTime? from}) {
    DateTime next = from ?? DateTime.now();
    next = DateTime(next.year, next.month, next.day).add(const Duration(days: 1));
    
    for (int i = 0; i < 30; i++) {
      final dateKey = _formatDate(next);
      bool isTrading;
      
      if (_cache.containsKey(dateKey)) {
        isTrading = _cache[dateKey]!;
      } else {
        if (next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
          isTrading = false;
        } else {
          final isHoliday = _worldHolidays.isHoliday('CN', next);
          isTrading = !isHoliday;
        }
        _cache[dateKey] = isTrading;
      }
      
      if (isTrading) {
        return next;
      }
      next = next.add(const Duration(days: 1));
    }
    
    return next;
  }
  
  
  Future<bool?> _checkByApi(DateTime date) async {
    try {
      final dateString = _formatDate(date);
      final url = 'https://timor.tech/api/holiday/info/$dateString';
      
      final response = await HttpClientProvider.client.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        
        if (data['code'] == 0 && data['type'] != null) {
          final type = data['type']['type'];
          
          
          final isWorkday = (type == 0 || type == 3);
          return isWorkday;
        }
      }
    } catch (e) {
    }
    
    return null;
  }
  
  bool? _checkByWorldHolidays(DateTime date) {
    try {
      if (date.weekday == DateTime.saturday || 
          date.weekday == DateTime.sunday) {
        return false;
      }
      
      final isHoliday = _worldHolidays.isHoliday('CN', date);
      
      if (isHoliday) {
        return false; 
      }
      
      return true;
    } catch (e) {
      return null;
    }
  }
  
  bool _checkByWeekday(DateTime date) {
    return date.weekday >= DateTime.monday && 
           date.weekday <= DateTime.friday;
  }
  
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

import 'package:flutter/material.dart';
import 'services/database_helper.dart';

/// 数据库初始化测试脚本
/// 运行方式: dart test_database_init.dart
void main() async {
  print('=== FundLink 数据库初始化测试 ===\n');
  
  try {
    // 注意：这个脚本需要在 Flutter 环境中运行
    // 如果使用纯 Dart，需要使用 sqflite_common_ffi
    
    print('1. 正在初始化数据库...');
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;
    print('✅ 数据库初始化成功\n');
    
    print('2. 检查表结构...');
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    print('找到的表:');
    for (final table in tables) {
      print('  - ${table['name']}');
    }
    print('');
    
    print('3. 测试插入数据...');
    final testId = DateTime.now().millisecondsSinceEpoch.toString();
    await dbHelper.insertHolding({
      'id': testId,
      'client_name': '测试客户',
      'client_id': 'test_001',
      'fund_code': '000001',
      'fund_name': '华夏成长混合',
      'total_shares': 1000.0,
      'total_cost': 10000.0,
      'avg_cost': 10.0,
      'nav_date': DateTime.now().toIso8601String(),
      'current_nav': 11.5,
      'remarks': '测试数据',
      'is_pinned': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('✅ 插入测试持仓成功\n');
    
    print('4. 测试查询数据...');
    final holdings = await dbHelper.queryAllHoldings();
    print('查询到 ${holdings.length} 条持仓记录');
    if (holdings.isNotEmpty) {
      final first = holdings.first;
      print('  基金代码: ${first['fund_code']}');
      print('  基金名称: ${first['fund_name']}');
      print('  持有份额: ${first['total_shares']}');
      print('  当前净值: ${first['current_nav']}');
    }
    print('');
    
    print('5. 测试更新数据...');
    await dbHelper.updateHolding(testId, {'is_pinned': 1});
    final updated = await dbHelper.queryPinnedHoldings();
    print('✅ 置顶持仓数量: ${updated.length}\n');
    
    print('6. 测试删除数据...');
    await dbHelper.deleteHolding(testId);
    final afterDelete = await dbHelper.queryAllHoldings();
    print('✅ 删除后持仓数量: ${afterDelete.length}\n');
    
    print('7. 测试日志功能...');
    await dbHelper.insertLog({
      'message': '测试日志消息',
      'type': 'info',
      'timestamp': DateTime.now().toIso8601String(),
    });
    final logs = await dbHelper.queryLogs(limit: 10);
    print('✅ 日志数量: ${logs.length}\n');
    
    print('8. 测试预警规则...');
    final alertId = DateTime.now().millisecondsSinceEpoch.toString();
    await dbHelper.insertAlert({
      'id': alertId,
      'fund_code': '000001',
      'fund_name': '华夏成长混合',
      'threshold_up': 3.0,
      'threshold_down': -2.0,
      'is_enabled': 1,
      'active_hours_start': '09:30',
      'active_hours_end': '15:30',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    final alerts = await dbHelper.queryEnabledAlerts();
    print('✅ 启用的预警规则: ${alerts.length}');
    
    // 清理测试数据
    await dbHelper.deleteAlert(alertId);
    print('');
    
    print('=== 所有测试通过！===');
    print('\n数据库文件位置:');
    print('  - Android/iOS: 应用数据目录');
    print('  - Windows: %APPDATA%/fundlink/fundlink.db');
    print('  - macOS: ~/Library/Application Support/fundlink/fundlink.db');
    print('  - Linux: ~/.local/share/fundlink/fundlink.db');
    
    await dbHelper.close();
  } catch (e, stackTrace) {
    print('❌ 测试失败!');
    print('错误: $e');
    print('堆栈: $stackTrace');
  }
}

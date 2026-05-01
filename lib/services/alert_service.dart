import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/valuation_alert.dart';
import '../services/database_helper.dart';
import '../services/fund_service.dart';
import '../services/china_trading_day_service.dart';

/// 估值预警服务 - 智能时间段控制
class AlertService {
  final FundService _fundService;
  final FlutterLocalNotificationsPlugin _notifications;
  
  Timer? _checkTimer;
  bool _isMonitoring = false;
  
  AlertService(this._fundService) : _notifications = FlutterLocalNotificationsPlugin();

  /// 初始化通知服务
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOSSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
    );
    
    await _notifications.initialize(settings);
    
    // 创建通知渠道
    await _createNotificationChannels();
    
    debugPrint('AlertService 初始化完成');
  }

  Future<void> _createNotificationChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    
    const channel = AndroidNotificationChannel(
      'valuation_alerts',
      '估值预警',
      description: '基金净值变动提醒',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    await _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    
    // 紧急预警渠道
    const urgentChannel = AndroidNotificationChannel(
      'urgent_alerts',
      '紧急预警',
      description: '闭市前重要提醒',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    
    await _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(urgentChannel);
  }

  /// 启动监控（智能时间段）
  void startMonitoring() {
    if (_isMonitoring) {
      debugPrint('预警监控已在运行');
      return;
    }
    
    _isMonitoring = true;
    debugPrint('启动估值预警监控');
    
    // 每分钟检查一次
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _smartCheck();
    });
    
    // 立即检查一次
    _smartCheck();
  }

  /// 停止监控
  void stopMonitoring() {
    _checkTimer?.cancel();
    _isMonitoring = false;
    debugPrint('停止估值预警监控');
  }

  /// 智能检查（仅在设定时间段内执行）
  Future<void> _smartCheck() async {
    try {
      final now = DateTime.now();
      
      // 1. 检查是否是交易日
      final isTradingDay = await ChinaTradingDayService().isTradingDay(now);
      if (!isTradingDay) {
        return;
      }
      
      // 2. 检查是否在活跃时间段
      if (!_isInActiveHours(now)) {
        return;
      }
      
      // 3. 检查是否接近闭市（最后1小时）
      final isNearClose = _isNearMarketClose(now);
      
      // 4. 获取启用的预警规则
      final alerts = await _getEnabledAlerts();
      if (alerts.isEmpty) {
        return;
      }
      
      debugPrint('开始检查 ${alerts.length} 个预警规则');
      
      // 5. 批量检查估值
      await _checkValuationAlerts(alerts, isNearClose);
      
    } catch (e) {
      debugPrint('预警检查失败: $e');
    }
  }

  /// 判断是否在活跃时间段
  bool _isInActiveHours(DateTime now) {
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    
    // 默认活跃时间：9:30 - 15:30
    const marketStart = 9 * 60 + 30;  // 9:30
    const marketEnd = 15 * 60 + 30;   // 15:30
    
    // TODO: 从数据库读取用户自定义设置
    // final userStart = await _getUserSetting('alert_start_time');
    // final userEnd = await _getUserSetting('alert_end_time');
    
    return currentTime >= marketStart && currentTime <= marketEnd;
  }

  /// 判断是否接近闭市（最后1小时）
  bool _isNearMarketClose(DateTime now) {
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    
    const marketClose = 15 * 60;  // 15:00
    const oneHourBefore = 14 * 60; // 14:00
    
    return currentTime >= oneHourBefore && currentTime < marketClose;
  }

  /// 获取启用的预警规则
  Future<List<ValuationAlert>> _getEnabledAlerts() async {
    final dbHelper = DatabaseHelper.instance;
    final alertsData = await dbHelper.queryEnabledAlerts();
    return alertsData.map((map) => ValuationAlert.fromMap(map)).toList();
  }

  /// 检查估值预警
  Future<void> _checkValuationAlerts(
    List<ValuationAlert> alerts,
    bool isNearClose,
  ) async {
    for (final alert in alerts) {
      try {
        // 获取实时估值
        final valuation = await _fundService.fetchRealtimeValuation(alert.fundCode);
        
        if (valuation == null || valuation.isEmpty) {
          continue;
        }
        
        final changePercent = (valuation['gszzl'] as num?)?.toDouble() ?? 0.0;
        final currentNav = (valuation['gsz'] as num?)?.toDouble() ?? 0.0;
        
        // 检查是否触发预警
        bool triggered = false;
        String message = '';
        
        if (alert.thresholdUp != null && changePercent >= alert.thresholdUp!) {
          triggered = true;
          message = '📈 ${alert.fundName.isNotEmpty ? alert.fundName : alert.fundCode} 涨幅达到 ${changePercent.toStringAsFixed(2)}%';
        } else if (alert.thresholdDown != null && changePercent <= alert.thresholdDown!) {
          triggered = true;
          message = '📉 ${alert.fundName.isNotEmpty ? alert.fundName : alert.fundCode} 跌幅达到 ${changePercent.toStringAsFixed(2)}%';
        }
        
        // 触发预警
        if (triggered) {
          await _sendNotification(
            title: '估值预警',
            body: message,
            fundCode: alert.fundCode,
            changePercent: changePercent,
          );
          
          debugPrint('预警触发: ${alert.fundCode} 涨跌幅 $changePercent%');
          
          // 如果是闭市前，发送更紧急的通知
          if (isNearClose) {
            await _sendUrgentNotification(
              title: '⚠️ 闭市前预警',
              body: '$message\n建议关注今日收盘情况',
            );
          }
        }
        
      } catch (e) {
        debugPrint('检查 ${alert.fundCode} 预警失败: $e');
      }
      
      // 避免请求过快，间隔 500ms
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// 发送普通通知
  Future<void> _sendNotification({
    required String title,
    required String body,
    required String fundCode,
    required double changePercent,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'valuation_alerts',
      '估值预警',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body),
    );
    
    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );
    
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: fundCode,
    );
  }

  /// 发送紧急通知（闭市前）
  Future<void> _sendUrgentNotification({
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'urgent_alerts',
      '紧急预警',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    );
    
    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );
    
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1,
      title,
      body,
      details,
    );
  }

  /// 添加预警规则
  Future<void> addAlert(ValuationAlert alert) async {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.insertAlert(alert.toMap());
    debugPrint('添加预警规则: ${alert.fundCode}');
  }

  /// 更新预警规则
  Future<void> updateAlert(ValuationAlert alert) async {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.updateAlert(alert.id, alert.toMap());
    debugPrint('更新预警规则: ${alert.fundCode}');
  }

  /// 删除预警规则
  Future<void> deleteAlert(String id) async {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.deleteAlert(id);
    debugPrint('删除预警规则: $id');
  }

  /// 切换预警开关
  Future<void> toggleAlert(String id, bool enabled) async {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.toggleAlert(id, enabled);
    debugPrint('切换预警规则: $id -> $enabled');
  }

  /// 获取所有预警规则
  Future<List<ValuationAlert>> getAllAlerts() async {
    final dbHelper = DatabaseHelper.instance;
    final alertsData = await dbHelper.queryAllAlerts();
    return alertsData.map((map) => ValuationAlert.fromMap(map)).toList();
  }

  /// 检查是否正在监控
  bool get isMonitoring => _isMonitoring;
}

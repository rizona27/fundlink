import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用生命周期监听回调类型
typedef LockRequiredCallback = void Function();

/// 生物识别保护服务
class BiometricGuard {
  static final LocalAuthentication _auth = LocalAuthentication();
  static DateTime? _lastActiveTime;
  static Timer? _lockCheckTimer;
  
  static LockRequiredCallback? _onLockRequired;

  /// 检查设备是否支持生物识别
  static Future<bool> canCheckBiometrics() async {
    try {
      final result = await _auth.canCheckBiometrics;
      debugPrint('canCheckBiometrics 结果: $result');
      return result;
    } catch (e) {
      debugPrint('检查生物识别支持失败: $e');
      return false;
    }
  }

  /// 初始化并设置生命周期监听
  static void initialize(LockRequiredCallback onLockRequired) {
    _onLockRequired = onLockRequired;
    
    // 添加生命周期观察者
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
    
    debugPrint('BiometricGuard 初始化完成');
  }

  /// 检查是否需要锁定
  static Future<bool> shouldLock() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('biometric_enabled') ?? false;
    
    if (!enabled) return false;
    
    // 检查后台停留时间
    if (_lastActiveTime == null) return false;
    
    final elapsed = DateTime.now().difference(_lastActiveTime!);
    final lockDelay = prefs.getInt('biometric_lock_delay') ?? 0; // 秒，0表示立即锁定
    
    // 如果设置为0，任何后台切换都锁定
    if (lockDelay == 0) {
      return elapsed.inSeconds > 0;
    }
    
    return elapsed.inSeconds > lockDelay;
  }

  /// 执行生物识别认证
  static Future<bool> authenticate({
    String reason = '请验证身份以继续',
  }) async {
    try {
      debugPrint('开始生物识别认证...');
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) {
        debugPrint('设备不支持生物识别');
        return false;
      }
      
      final available = await _auth.getAvailableBiometrics();
      debugPrint('可用的生物识别方式: $available');
      if (available.isEmpty) {
        debugPrint('未设置生物识别方式');
        return false;
      }
      
      debugPrint('使用原因: $reason');
      
      final result = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      
      debugPrint('生物识别认证结果: $result');
      return result;
    } catch (e) {
      debugPrint('生物识别认证失败: $e');
      return false;
    }
  }

  /// 记录活跃时间
  static void markActive() {
    _lastActiveTime = DateTime.now();
  }

  /// 获取主要生物识别类型名称
  static Future<String> getPrimaryBiometricType() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      
      if (available.isEmpty) {
        return '未设置';
      }
      
      // 优先级：面部 > 指纹 > 其他
      if (available.contains(BiometricType.face)) {
        return '面部识别';
      }
      if (available.contains(BiometricType.fingerprint)) {
        return '指纹识别';
      }
      
      return '生物识别';
    } catch (e) {
      return '生物识别';
    }
  }

  /// 启用/禁用生物识别
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (enabled) {
      // 在启用时，先检查是否支持并请求权限
      final canCheck = await canCheckBiometrics();
      if (!canCheck) {
        debugPrint('设备不支持生物识别');
        return;
      }
      
      // 尝试进行一次认证以获取权限
      final available = await _auth.getAvailableBiometrics();
      if (available.isEmpty) {
        debugPrint('未设置生物识别方式');
        return;
      }
      
      debugPrint('可用的生物识别方式: $available');
      
      // 在 iOS 上，首次调用 authenticate 会触发权限请求
      try {
        await _auth.authenticate(
          localizedReason: '验证身份以启用生物识别保护',
          options: const AuthenticationOptions(
            useErrorDialogs: true,
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        debugPrint('生物识别权限已授予');
      } catch (e) {
        debugPrint('生物识别认证失败: $e');
        // 即使认证失败，也要保存设置，让用户可以稍后重试
      }
    }
    
    await prefs.setBool('biometric_enabled', enabled);
    debugPrint('生物识别已${enabled ? "启用" : "禁用"}');
  }

  /// 获取是否启用
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometric_enabled') ?? false;
  }

  /// 设置锁定延迟（秒）
  static Future<void> setLockDelay(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('biometric_lock_delay', seconds);
    debugPrint('锁定延迟设置为: ${seconds}秒');
  }

  /// 获取锁定延迟
  static Future<int> getLockDelay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('biometric_lock_delay') ?? 0;
  }
}

/// 应用生命周期观察者
class _LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // 进入后台，记录时间
        BiometricGuard._lastActiveTime = DateTime.now();
        debugPrint('应用进入后台，记录时间: ${BiometricGuard._lastActiveTime}');
        break;
        
      case AppLifecycleState.resumed:
        // 回到前台，检查是否需要锁定
        _checkLockOnResume();
        break;
        
      default:
        break;
    }
  }

  Future<void> _checkLockOnResume() async {
    final shouldLock = await BiometricGuard.shouldLock();
    if (shouldLock) {
      debugPrint('需要锁定，触发回调');
      BiometricGuard._onLockRequired?.call();
    } else {
      BiometricGuard.markActive();
      debugPrint('无需锁定，标记活跃');
    }
  }
}

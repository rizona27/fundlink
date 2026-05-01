import 'package:flutter/cupertino.dart';
import '../services/biometric_guard.dart';

/// 生物识别锁定覆盖层
class BiometricLockOverlay extends StatefulWidget {
  final Widget child;
  
  const BiometricLockOverlay({
    super.key,
    required this.child,
  });

  @override
  State<BiometricLockOverlay> createState() => _BiometricLockOverlayState();
}

class _BiometricLockOverlayState extends State<BiometricLockOverlay> {
  bool _isLocked = false;
  bool _isAuthenticating = false;
  String _biometricType = '生物识别';
  
  @override
  void initState() {
    super.initState();
    _loadBiometricType();
    
    // 设置生命周期监听
    BiometricGuard.initialize(() {
      if (mounted) {
        setState(() {
          _isLocked = true;
        });
        _attemptUnlock();
      }
    });
  }

  Future<void> _loadBiometricType() async {
    final type = await BiometricGuard.getPrimaryBiometricType();
    if (mounted) {
      setState(() {
        _biometricType = type;
      });
    }
  }

  Future<void> _attemptUnlock() async {
    setState(() {
      _isAuthenticating = true;
    });
    
    final success = await BiometricGuard.authenticate(
      reason: '使用 $_biometricType 验证身份',
    );
    
    if (mounted) {
      setState(() {
        _isLocked = !success;
        _isAuthenticating = false;
      });
      
      if (success) {
        BiometricGuard.markActive();
      } else {
        // 认证失败，显示密码选项
        _showPasswordFallback();
      }
    }
  }

  void _showPasswordFallback() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('验证失败'),
        content: const Text('是否使用密码解锁？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('重试'),
            onPressed: () {
              Navigator.pop(context);
              _attemptUnlock();
            },
          ),
          CupertinoDialogAction(
            child: const Text('使用密码'),
            onPressed: () {
              Navigator.pop(context);
              // TODO: 实现密码输入逻辑
              _showNotImplementedToast();
            },
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('取消'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showNotImplementedToast() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: const Text('密码功能暂未实现'),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocked) {
      return widget.child;
    }
    
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Container(
            color: CupertinoColors.black.withOpacity(0.95),
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.lock_shield_fill,
                      size: 80,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '应用已锁定',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请使用 $_biometricType 验证身份',
                      style: TextStyle(
                        color: CupertinoColors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isAuthenticating)
                      const CupertinoActivityIndicator(
                        radius: 16,
                        color: CupertinoColors.white,
                      )
                    else
                      CupertinoButton.filled(
                        onPressed: _attemptUnlock,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        child: const Text(
                          '点击验证',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    const SizedBox(height: 16),
                    CupertinoButton(
                      onPressed: _showPasswordFallback,
                      child: Text(
                        '使用密码',
                        style: TextStyle(
                          color: CupertinoColors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../services/data_manager.dart';
import '../models/log_entry.dart';

/// 错误边界组件 - 捕获子树中的错误并显示友好提示
/// 
/// 使用场景：
/// - 包裹可能抛出异常的 Widget
/// - 防止单个组件崩溃导致整个页面白屏
/// - 提供重试机制和错误日志记录
/// 
/// 示例：
/// ```dart
/// ErrorBoundary(
///   child: FundPerformanceChart(...),
///   errorWidget: CustomErrorWidget(message: '图表加载失败'),
///   onError: (error, stackTrace) {
///     // 自定义错误处理逻辑
///   },
/// )
/// ```
class ErrorBoundary extends StatefulWidget {
  /// 子组件
  final Widget child;
  
  /// 自定义错误显示组件（可选）
  final Widget Function(Object error, StackTrace stackTrace)? errorBuilder;
  
  /// 默认错误提示文本
  final String? errorMessage;
  
  /// 错误发生时的回调
  final void Function(Object error, StackTrace stackTrace)? onError;
  
  /// 是否自动记录错误到日志系统
  final bool autoLogError;
  
  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.errorMessage,
    this.onError,
    this.autoLogError = true,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当依赖变化时重置错误状态
    if (_hasError && mounted) {  // ✅ 添加 mounted 检查
      setState(() {
        _hasError = false;
        _error = null;
        _stackTrace = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorWidget();
    }
    
    return _SafeWrapper(
      onError: _handleError,
      child: widget.child,
    );
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (mounted) {  // ✅ 添加 mounted 检查
      setState(() {
        _hasError = true;
        _error = error;
        _stackTrace = stackTrace;
      });
    }

    // 调用外部回调
    widget.onError?.call(error, stackTrace);

    // 自动记录错误
    if (widget.autoLogError) {
      _logError(error, stackTrace);
    }

    // Debug 模式下打印详细错误
    if (kDebugMode) {
      debugPrint('❌ ErrorBoundary 捕获错误:');
      debugPrint('错误类型: ${error.runtimeType}');
      debugPrint('错误信息: $error');
      debugPrint('堆栈跟踪:\n$stackTrace');
    }
  }

  Widget _buildErrorWidget() {
    // 使用自定义错误构建器
    if (widget.errorBuilder != null && _error != null && _stackTrace != null) {
      return widget.errorBuilder!(_error!, _stackTrace!);
    }

    // 使用默认错误界面
    return _DefaultErrorWidget(
      message: widget.errorMessage ?? '加载失败',
      error: _error,
      onRetry: _handleRetry,
    );
  }

  void _handleRetry() {
    if (mounted) {  // ✅ 添加 mounted 检查
      setState(() {
        _hasError = false;
        _error = null;
        _stackTrace = null;
      });
    }
  }

  Future<void> _logError(Object error, StackTrace stackTrace) async {
    try {
      final dataManager = DataManagerProvider.maybeOf(context);
      if (dataManager != null) {
        await dataManager.addLog(
          '组件错误: ${error.toString()}',
          type: LogType.error,
        );
      }
    } catch (e) {
      // 日志记录失败不应影响主流程
      debugPrint('记录错误日志失败: $e');
    }
  }
}

/// 安全包装器 - 在构建过程中捕获异常
class _SafeWrapper extends StatelessWidget {
  final Widget child;
  final void Function(Object error, StackTrace stackTrace) onError;

  const _SafeWrapper({
    required this.child,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return _ErrorCatcher(
      onError: onError,
      child: child,
    );
  }
}

/// 错误捕获器 - 使用 Zone 捕获异步错误
class _ErrorCatcher extends StatefulWidget {
  final Widget child;
  final void Function(Object error, StackTrace stackTrace) onError;

  const _ErrorCatcher({
    required this.child,
    required this.onError,
  });

  @override
  State<_ErrorCatcher> createState() => _ErrorCatcherState();
}

class _ErrorCatcherState extends State<_ErrorCatcher> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    // 注册 Flutter 错误处理器
    FlutterError.onError = (FlutterErrorDetails details) {
      widget.onError(details.exception, details.stack ?? StackTrace.empty);
    };
  }
}

/// 默认错误显示组件
class _DefaultErrorWidget extends StatelessWidget {
  final String message;
  final Object? error;
  final VoidCallback onRetry;

  const _DefaultErrorWidget({
    required this.message,
    this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 错误图标
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: CupertinoColors.systemOrange,
            ),
            
            const SizedBox(height: 16),
            
            // 错误标题
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
              ),
              textAlign: TextAlign.center,
            ),
            
            // 错误详情（仅 Debug 模式）
            if (kDebugMode && error != null) ...[
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            
            const SizedBox(height: 24),
            
            // 重试按钮
            CupertinoButton.filled(
              onPressed: onRetry,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.refresh, size: 18),
                  SizedBox(width: 8),
                  Text('重试'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误边界工具类 - 提供静态方法
class ErrorBoundaryUtils {
  /// 安全执行异步操作，捕获错误
  static Future<T?> safeExecute<T>(
    Future<T> Function() operation, {
    void Function(Object error)? onError,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      onError?.call(error);
      
      if (kDebugMode) {
        debugPrint('safeExecute 捕获错误: $error');
        debugPrint('堆栈: $stackTrace');
      }
      
      return null;
    }
  }

  /// 安全执行同步操作
  static T? safeExecuteSync<T>(
    T Function() operation, {
    void Function(Object error)? onError,
  }) {
    try {
      return operation();
    } catch (error, stackTrace) {
      onError?.call(error);
      
      if (kDebugMode) {
        debugPrint('safeExecuteSync 捕获错误: $error');
        debugPrint('堆栈: $stackTrace');
      }
      
      return null;
    }
  }
}

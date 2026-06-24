import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../services/data_manager.dart';
import '../models/log_entry.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  
  final Widget Function(Object error, StackTrace stackTrace)? errorBuilder;
  
  final String? errorMessage;
  
  final void Function(Object error, StackTrace stackTrace)? onError;
  
  final bool autoLogError;
  
  final bool autoRetry;
  
  final Duration retryDelay;
  
  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.errorMessage,
    this.onError,
    this.autoLogError = true,
    this.autoRetry = false,
    this.retryDelay = const Duration(seconds: 2),
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
    if (_hasError && mounted) {
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
    if (mounted) {
      setState(() {
        _hasError = true;
        _error = error;
        _stackTrace = stackTrace;
      });
    }

    widget.onError?.call(error, stackTrace);

    if (widget.autoLogError) {
      _logError(error, stackTrace);
    }

    if (widget.autoRetry) {
      Future.delayed(widget.retryDelay, () {
        if (mounted) {
          _handleRetry();
        }
      });
    }

    if (kDebugMode) {
    }
  }

  Widget _buildErrorWidget() {
    if (widget.autoRetry) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(height: 16),
            Text(
              widget.errorMessage ?? '加载中...',
              style: TextStyle(
                fontSize: 14,
                color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                    ? CupertinoColors.white.withOpacity(0.6)
                    : CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      );
    }
    
    if (widget.errorBuilder != null && _error != null && _stackTrace != null) {
      return widget.errorBuilder!(_error!, _stackTrace!);
    }

    return _DefaultErrorWidget(
      message: widget.errorMessage ?? '加载失败',
      error: _error,
      onRetry: _handleRetry,
    );
  }

  void _handleRetry() {
    if (mounted) {
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
    }
  }
}

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
    FlutterError.onError = (FlutterErrorDetails details) {
      widget.onError(details.exception, details.stack ?? StackTrace.empty);
    };
  }
}

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
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: CupertinoColors.systemOrange,
            ),
            
            const SizedBox(height: 16),
            
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
              ),
              textAlign: TextAlign.center,
            ),
            
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

class ErrorBoundaryUtils {
  static Future<T?> safeExecute<T>(
    Future<T> Function() operation, {
    void Function(Object error)? onError,
  }) async {
    try {
      return await operation();
    } catch (error) {
      onError?.call(error);
      
      if (kDebugMode) {
      }
      
      return null;
    }
  }

  static T? safeExecuteSync<T>(
    T Function() operation, {
    void Function(Object error)? onError,
  }) {
    try {
      return operation();
    } catch (error) {
      onError?.call(error);
      
      if (kDebugMode) {
      }
      
      return null;
    }
  }
}

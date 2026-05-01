import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CountdownRefreshButton extends StatefulWidget {
  final VoidCallback onRefresh;
  final int refreshIntervalSeconds;
  final bool isRefreshing;
  final double refreshProgress;
  final double size;
  final VoidCallback? onIntervalChanged;

  const CountdownRefreshButton({
    super.key,
    required this.onRefresh,
    required this.refreshIntervalSeconds,
    this.isRefreshing = false,
    this.refreshProgress = 0.0,
    this.size = 32,
    this.onIntervalChanged,
  });

  @override
  State<CountdownRefreshButton> createState() => _CountdownRefreshButtonState();
}

class _CountdownRefreshButtonState extends State<CountdownRefreshButton>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int _remainingSeconds = 0;
  late DateTime _lastRefreshTime;
  bool _isDisposed = false;

  static const List<int> intervalOptions = [60, 180, 300];

  @override
  void initState() {
    super.initState();
    _lastRefreshTime = DateTime.now();
    _remainingSeconds = widget.refreshIntervalSeconds;
    _startTimer();
  }

  void _startTimer() {
    if (_isDisposed) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (widget.isRefreshing) return;

      final elapsed = DateTime.now().difference(_lastRefreshTime).inSeconds;
      final remaining = widget.refreshIntervalSeconds - elapsed;

      if (remaining <= 0) {
        _lastRefreshTime = DateTime.now();
        widget.onRefresh();
        if (mounted && !_isDisposed) {
          setState(() {
            _remainingSeconds = widget.refreshIntervalSeconds;
          });
        }
      } else {
        if (mounted && !_isDisposed) {
          setState(() {
            _remainingSeconds = remaining;
          });
        }
      }
    });
  }

  void _restartTimer() {
    if (_isDisposed) return;
    _timer.cancel();
    _lastRefreshTime = DateTime.now();
    _remainingSeconds = widget.refreshIntervalSeconds;
    _startTimer();
  }

  void _manualRefresh() {
    if (widget.isRefreshing || _isDisposed) return;
    if (!mounted) return;
    _lastRefreshTime = DateTime.now();
    setState(() {
      _remainingSeconds = widget.refreshIntervalSeconds;
    });
    widget.onRefresh();
  }

  void _showIntervalPickerDialog() {
    if (_isDisposed) return;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(
          '估值刷新间隔',
          style: TextStyle(
            color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
          ),
        ),
        message: Text(
          '选择自动刷新估值的间隔时间',
          style: TextStyle(
            color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
          ),
        ),
        actions: intervalOptions.map((seconds) {
          final label = seconds == 60 ? '1分钟' : (seconds == 180 ? '3分钟' : '5分钟');
          final isSelected = seconds == widget.refreshIntervalSeconds;
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              widget.onIntervalChanged?.call();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? CupertinoColors.activeBlue
                        : (isDarkMode ? CupertinoColors.white : CupertinoColors.black),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 16,
                    color: CupertinoColors.activeBlue,
                  ),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              color: CupertinoColors.systemRed,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(CountdownRefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRefreshing != widget.isRefreshing && !widget.isRefreshing) {
      _lastRefreshTime = DateTime.now();
      setState(() {
        _remainingSeconds = widget.refreshIntervalSeconds;
      });
    }
    if (oldWidget.refreshIntervalSeconds != widget.refreshIntervalSeconds) {
      _remainingSeconds = widget.refreshIntervalSeconds;
      _lastRefreshTime = DateTime.now();
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final interval = widget.refreshIntervalSeconds > 0 ? widget.refreshIntervalSeconds : 60;

    double displayProgress;
    if (widget.isRefreshing) {
      displayProgress = widget.refreshProgress.clamp(0.0, 1.0);
    } else {
      final progress = 1 - (_remainingSeconds / interval);
      displayProgress = progress.clamp(0.0, 1.0);
    }

    return GestureDetector(
      onTap: _manualRefresh,
      onLongPress: _showIntervalPickerDialog,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: widget.size - 6,
              height: widget.size - 6,
              child: CustomPaint(
                painter: _CircularProgressPainter(
                  progress: displayProgress,
                  backgroundColor: isDarkMode
                      ? CupertinoColors.white.withOpacity(0.2)
                      : CupertinoColors.systemGrey.withOpacity(0.2),
                  progressColor: CupertinoColors.activeBlue,
                ),
              ),
            ),
            if (widget.isRefreshing)
              SizedBox(
                width: widget.size - 8,
                height: widget.size - 8,
                child: const CupertinoActivityIndicator(),
              )
            else if (_remainingSeconds > 0 && _remainingSeconds <= interval)
              Text(
                '$_remainingSeconds',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? CupertinoColors.white
                      : CupertinoColors.label,
                ),
              )
            else
              Icon(
                CupertinoIcons.arrow_clockwise,
                size: 16,
                color: isDarkMode
                    ? CupertinoColors.white
                    : CupertinoColors.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;

  _CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, paint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * 3.14159 * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159 / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor;
  }
}
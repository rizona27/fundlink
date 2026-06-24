import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class Toast {
  static OverlayEntry? _currentOverlayEntry;

  static void show(
      BuildContext context,
      String message, {
        Duration duration = AppConstants.toastDuration,
        Brightness? brightness,
      }) {
    _removeCurrentOverlay();

    final overlayState = Overlay.of(context);

    final isDark = brightness != null
        ? brightness == Brightness.dark
        : CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.black;

    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        duration: duration,
        backgroundColor: backgroundColor,
        textColor: textColor,
        onDismiss: () {
          if (overlayEntry != null && overlayEntry.mounted) {
            overlayEntry.remove();
          }
          if (_currentOverlayEntry == overlayEntry) {
            _currentOverlayEntry = null;
          }
        },
      ),
    );

    _currentOverlayEntry = overlayEntry;
    overlayState.insert(overlayEntry);
  }

  static void _removeCurrentOverlay() {
    if (_currentOverlayEntry != null && _currentOverlayEntry!.mounted) {
      _currentOverlayEntry!.remove();
    }
    _currentOverlayEntry = null;
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final Duration duration;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.duration,
    required this.backgroundColor,
    required this.textColor,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) {
            widget.onDismiss();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shadowColor = CupertinoColors.black.withOpacity(0.15);

    return Positioned(
      bottom: AppConstants.toastBottomOffset,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(maxWidth: AppConstants.toastMaxWidth),
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(AppConstants.toastBorderRadius),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.textColor,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension ToastExtension on BuildContext {
  void showToast(
      String message, {
        Duration duration = AppConstants.toastDuration,
        Brightness? brightness,
      }) {
    Toast.show(this, message, duration: duration, brightness: brightness);
  }
}
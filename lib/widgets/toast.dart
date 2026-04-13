import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class Toast {
  static OverlayEntry? _currentOverlayEntry;

  static void show(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    _removeCurrentOverlay();

    final overlayState = Overlay.of(context);

    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        duration: duration,
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
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.duration,
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
    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 320),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.label,
                ),
                textAlign: TextAlign.left, // 文本左对齐
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension ToastExtension on BuildContext {
  void showToast(String message, {Duration duration = const Duration(seconds: 2)}) {
    Toast.show(this, message, duration: duration);
  }
}
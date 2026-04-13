import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

/// 磨砂玻璃质感按钮（支持深色模式、主要/次要样式、自定义尺寸）
class GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;        // true = 蓝色主题（主要操作），false = 灰色/透明（次要操作）
  final double? width;         // 可选宽度
  final double height;         // 高度
  final double borderRadius;   // 圆角
  final EdgeInsetsGeometry padding;

  const GlassButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isPrimary = true,
    this.width,
    this.height = 44,
    this.borderRadius = 30,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
        : CupertinoColors.white.withValues(alpha: 0.85);

    Color? effectiveBgColor;
    if (onPressed == null) {
      effectiveBgColor = isDarkMode ? CupertinoColors.systemGrey : CupertinoColors.systemGrey5;
    } else if (isPrimary) {
      effectiveBgColor = CupertinoColors.activeBlue.withValues(alpha: 0.15);
    } else {
      effectiveBgColor = bgColor;
    }

    final textColor = (onPressed == null)
        ? (isDarkMode ? CupertinoColors.white : CupertinoColors.label).withValues(alpha: 0.5)
        : (isPrimary ? CupertinoColors.activeBlue : (isDarkMode ? CupertinoColors.white : CupertinoColors.label));

    Widget button = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: effectiveBgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CupertinoButton(
        onPressed: onPressed,
        padding: padding,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
    if (onPressed == null) button = Opacity(opacity: 0.6, child: button);
    return button;
  }
}
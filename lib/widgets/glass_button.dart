import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool expand;
  final double minWidth;
  final Color? backgroundColorOverride; // 自定义背景色
  final Color? textColorOverride; // 自定义文字颜色

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isPrimary = true,
    this.width,
    this.height = 44,
    this.borderRadius = 30,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.expand = false,
    this.minWidth = 120.0,
    this.backgroundColorOverride,
    this.textColorOverride,
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
    } else if (backgroundColorOverride != null) {
      // 使用自定义背景色
      effectiveBgColor = backgroundColorOverride;
    } else if (isPrimary) {
      effectiveBgColor = CupertinoColors.activeBlue.withValues(alpha: 0.15);
    } else {
      effectiveBgColor = bgColor;
    }

    final textColor = (onPressed == null)
        ? (isDarkMode ? CupertinoColors.white : CupertinoColors.label).withValues(alpha: 0.5)
        : (textColorOverride ?? (isPrimary ? CupertinoColors.activeBlue : (isDarkMode ? CupertinoColors.white : CupertinoColors.label)));

    Widget buttonContent;
    if (icon != null && label.isEmpty) {
      // 只有图标
      buttonContent = Icon(
        icon,
        size: 18,
        color: textColor,
      );
    } else if (icon != null) {
      // 图标 + 文字
      buttonContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: textColor,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      );
    } else {
      // 只有文字
      buttonContent = Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      );
    }

    Widget button = Container(
      width: width ?? (expand ? null : null),
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
        child: buttonContent,
      ),
    );

    if (!expand && width == null) {
      button = ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: IntrinsicWidth(child: button),
      );
    }

    if (expand && width == null) {
      button = SizedBox(width: double.infinity, child: button);
    }

    if (onPressed == null) button = Opacity(opacity: 0.6, child: button);
    return button;
  }
}
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;           // 新增：图标参数
  final VoidCallback? onPressed;
  final bool isPrimary;
  final double? width;           // 固定宽度，优先级最高
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool expand;             // 是否撑满父容器（全宽）
  final double minWidth;         // 非展开模式下的最小宽度

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
    this.expand = false,         // 默认不撑满，避免子菜单中过长
    this.minWidth = 120.0,       // 默认最小宽度
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

    // 构建按钮内容
    Widget buttonContent;
    if (icon != null && label.isEmpty) {
      // 只有图标，没有文字
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
      // 宽度优先级：width > expand（全宽） > 约束最小宽度（minWidth + 内容自适应）
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

    // 非展开模式且未指定固定宽度时，用 ConstrainedBox 设置最小宽度，并让宽度由内容决定
    if (!expand && width == null) {
      button = ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: IntrinsicWidth(child: button),
      );
    }

    // 展开模式且未指定宽度时，让按钮撑满父容器
    if (expand && width == null) {
      button = SizedBox(width: double.infinity, child: button);
    }

    if (onPressed == null) button = Opacity(opacity: 0.6, child: button);
    return button;
  }
}
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

/// 通用渐变卡片组件
class GradientCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int? countValue;
  final List<Color> gradient;
  final bool isExpanded;
  final VoidCallback onTap;
  final bool isDarkMode;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const GradientCard({
    super.key,
    required this.title,
    this.subtitle,
    this.countValue,
    required this.gradient,
    required this.isExpanded,
    required this.onTap,
    required this.isDarkMode,
    this.trailing,
    this.padding,
    this.borderRadius = 10,
  });

  Color _getCountColor(int? count) {
    if (count == null) return CupertinoColors.label.withOpacity(0.5);
    if (count == 1) return const Color(0xFFD4A84B);
    if (count <= 3) return const Color(0xFFD4844B);
    return const Color(0xFFD46B6B);
  }

  @override
  Widget build(BuildContext context) {
    final endColor = isDarkMode
        ? CupertinoColors.systemBackground
        : CupertinoColors.white;
    final adjustedGradient = [gradient[0], endColor];
    final countColor = _getCountColor(countValue);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(
        left: 0,
        right: isExpanded ? 16 : 0,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding ?? const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: adjustedGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: gradient[0].withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(3, 3),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // 标题
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.label,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 右侧内容
              if (trailing != null)
                trailing!
              else if (subtitle != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: CupertinoColors.label.withOpacity(0.5),
                      ),
                    ),
                    if (countValue != null) ...[
                      const SizedBox(width: 2),
                      Text(
                        '$countValue',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                          color: countColor,
                        ),
                      ),
                      Text(
                        '支',
                        style: TextStyle(
                          fontSize: 11,
                          color: CupertinoColors.label.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
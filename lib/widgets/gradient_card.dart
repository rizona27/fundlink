import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class GradientCard extends StatelessWidget {
  final String title;
  final String? clientId;
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
    this.clientId,
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

  Color _getEndColor() {
    if (isDarkMode) {
      return const Color(0xFF1C1C1E);
    }
    return CupertinoColors.white;
  }

  Color _getTextColor() {
    if (isDarkMode) {
      return CupertinoColors.white;
    }
    return CupertinoColors.label;
  }

  Color _getSubTextColor() {
    if (isDarkMode) {
      return CupertinoColors.white.withOpacity(0.5);
    }
    return CupertinoColors.label.withOpacity(0.5);
  }

  Color _getShadowColor() {
    if (gradient.isEmpty) {
      return isDarkMode ? CupertinoColors.black.withOpacity(0.3) : Colors.black.withOpacity(0.15);
    }
    if (isDarkMode) {
      return CupertinoColors.black.withOpacity(0.3);
    }
    return gradient[0].withOpacity(0.25);
  }

  Color _getBoxShadowColor() {
    if (isDarkMode) {
      return CupertinoColors.black.withOpacity(0.15);
    }
    return Colors.black.withOpacity(0.05);
  }

  @override
  Widget build(BuildContext context) {
    final endColor = _getEndColor();
    final gradientColors = gradient.isNotEmpty ? [gradient[0], endColor] : [endColor, endColor];
    final countColor = _getCountColor(countValue);
    final textColor = _getTextColor();
    final subTextColor = _getSubTextColor();
    final shadowColor = _getShadowColor();
    final boxShadowColor = _getBoxShadowColor();

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
              colors: gradientColors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 6,
                offset: const Offset(3, 3),
              ),
              BoxShadow(
                color: boxShadowColor,
                blurRadius: 4,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                    children: [
                      TextSpan(text: title),
                      if (clientId != null && clientId!.isNotEmpty)
                        TextSpan(
                          text: ' ($clientId)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                        color: subTextColor,
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
                          color: subTextColor,
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
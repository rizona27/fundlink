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
  final String? debugSource;
  final int? maxTitleLength;

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
    this.debugSource,
    this.maxTitleLength,
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
    return isDarkMode ? CupertinoColors.white : CupertinoColors.black;
  }

  Color _getSubTextColor() {
    if (isDarkMode) {
      return CupertinoColors.white.withOpacity(0.5);
    }
    return CupertinoColors.black.withOpacity(0.5);
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
    String displayTitle = title;
    if (maxTitleLength != null && title.length > maxTitleLength!) {
      displayTitle = title.substring(0, maxTitleLength!) + '…';
    }

    final endColor = _getEndColor();
    final gradientColors = gradient.isNotEmpty ? [gradient[0], endColor] : [endColor, endColor];
    final countColor = _getCountColor(countValue);
    final textColor = _getTextColor();
    final subTextColor = _getSubTextColor();
    final shadowColor = _getShadowColor();
    final boxShadowColor = _getBoxShadowColor();

    return Container(
      margin: EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding ?? const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: textColor,
                    ),
                    children: [
                      TextSpan(text: displayTitle),
                      if (clientId != null && clientId!.isNotEmpty)
                        TextSpan(
                          text: ' ($clientId)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                            color: subTextColor,
                            height: 1.2,
                          ),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                  strutStyle: const StrutStyle(height: 1.2, fontSize: 15, forceStrutHeight: true),
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
                        height: 1.2,
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
                          height: 1.2,
                        ),
                      ),
                      Text(
                        '支',
                        style: TextStyle(
                          fontSize: 11,
                          color: subTextColor,
                          height: 1.2,
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
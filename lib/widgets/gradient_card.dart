import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class GradientCard extends StatefulWidget {
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

  @override
  State<GradientCard> createState() => _GradientCardState();
}

class _GradientCardState extends State<GradientCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    
    // 根据初始状态设置控制器
    if (widget.isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(GradientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isExpanded != widget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getCountColor(int? count) {
    if (count == null) return CupertinoColors.label.withOpacity(0.5);
    if (count == 1) return const Color(0xFFD4A84B);
    if (count <= 3) return const Color(0xFFD4844B);
    return const Color(0xFFD46B6B);
  }

  Color _getEndColor() {
    if (widget.isDarkMode) {
      return const Color(0xFF1C1C1E);
    }
    return CupertinoColors.white;
  }

  Color _getTextColor() {
    return widget.isDarkMode ? CupertinoColors.white : CupertinoColors.black;
  }

  Color _getSubTextColor() {
    if (widget.isDarkMode) {
      return CupertinoColors.white.withOpacity(0.5);
    }
    return CupertinoColors.black.withOpacity(0.5);
  }

  Color _getShadowColor() {
    if (widget.gradient.isEmpty) {
      return widget.isDarkMode ? CupertinoColors.black.withOpacity(0.3) : Colors.black.withOpacity(0.15);
    }
    if (widget.isDarkMode) {
      return CupertinoColors.black.withOpacity(0.3);
    }
    return widget.gradient[0].withOpacity(0.25);
  }

  Color _getBoxShadowColor() {
    if (widget.isDarkMode) {
      return CupertinoColors.black.withOpacity(0.15);
    }
    return Colors.black.withOpacity(0.05);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return _buildCard(_animation.value);
      },
    );
  }

  Widget _buildCard(double animationValue) {
    String displayTitle = widget.title;
    if (widget.maxTitleLength != null && widget.title.length > widget.maxTitleLength!) {
      displayTitle = widget.title.substring(0, widget.maxTitleLength!) + '…';
    }

    final endColor = _getEndColor();
    final List<Color> gradientColors = widget.gradient.isNotEmpty ? [widget.gradient[0], endColor] : [endColor, endColor];
    final countColor = _getCountColor(widget.countValue);
    final textColor = _getTextColor();
    final subTextColor = _getSubTextColor();
    final shadowColor = _getShadowColor();
    final boxShadowColor = _getBoxShadowColor();

    // 计算不对称收缩的边距
    // 展开时：左端缩进约30px，右端通过渐变终点移动来缩短
    final leftPadding = 16.0 + (animationValue * 30.0); // 从16增加到46
    
    return Container(
      margin: EdgeInsets.zero,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: widget.padding ?? EdgeInsets.symmetric(
            vertical: 10,
            horizontal: animationValue > 0 ? leftPadding : 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.centerLeft,
              end: animationValue > 0 ? Alignment(0.7, 0) : Alignment.centerRight, // 渐变终点向左移动
            ),
            borderRadius: BorderRadius.circular(widget.borderRadius),
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
                      if (widget.clientId != null && widget.clientId!.isNotEmpty)
                        TextSpan(
                          text: ' (${widget.clientId})',
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
              if (widget.trailing != null)
                widget.trailing!
              else if (widget.subtitle != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: subTextColor,
                        height: 1.2,
                      ),
                    ),
                    if (widget.countValue != null) ...[
                      const SizedBox(width: 2),
                      Text(
                        '${widget.countValue}',
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
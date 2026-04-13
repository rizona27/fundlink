import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionText;
  final VoidCallback? onAction;
  final FontWeight titleFontWeight;
  final double? titleFontSize;
  final Widget? customButton;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionText,
    this.onAction,
    this.titleFontWeight = FontWeight.normal,
    this.titleFontSize = 18,
    this.customButton,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final topPadding = MediaQuery.of(context).padding.top;

    // 获取页面背景色（与 CupertinoPageScaffold 默认背景匹配）
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return Container(
      color: backgroundColor,
      child: Stack(
        children: [
          // 装饰层：扩展到全屏（包括导航栏区域）
          Positioned(
            top: -topPadding, // 向上扩展，覆盖状态栏区域
            left: 0,
            right: 0,
            bottom: 0,
            child: Stack(
              children: [
                // 模糊色块
                Positioned(
                  top: -50,
                  right: -50,
                  child: _BlurredBlob(
                    size: 200,
                    color: CupertinoColors.activeBlue.withOpacity(isDarkMode ? 0.12 : 0.08),
                  ),
                ),
                Positioned(
                  bottom: 100,
                  left: -30,
                  child: _BlurredBlob(
                    size: 150,
                    color: CupertinoColors.systemPurple.withOpacity(isDarkMode ? 0.1 : 0.05),
                  ),
                ),
                Positioned(
                  top: 200,
                  left: 100,
                  child: _BlurredBlob(
                    size: 120,
                    color: CupertinoColors.systemOrange.withOpacity(isDarkMode ? 0.08 : 0.04),
                  ),
                ),
                // 极淡网格纹理
                Opacity(
                  opacity: isDarkMode ? 0.03 : 0.01,
                  child: const _GridBackground(),
                ),
              ],
            ),
          ),
          // 内容区域：保留安全区，避免被状态栏遮挡
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _AnimatedIconContainer(icon: icon, isDarkMode: isDarkMode),
                    const SizedBox(height: 40),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: titleFontSize ?? (screenWidth > 600 ? 24 : 22),
                        fontWeight: titleFontWeight,
                        letterSpacing: -0.5,
                        color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: screenWidth > 600 ? 16 : 15,
                        height: 1.5,
                        color: isDarkMode
                            ? CupertinoColors.secondaryLabel
                            : CupertinoColors.systemGrey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (customButton != null) ...[
                      const SizedBox(height: 48),
                      customButton!,
                    ] else if (actionText != null && onAction != null) ...[
                      const SizedBox(height: 48),
                      _GlassButton(text: actionText!, onTap: onAction!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 以下为辅助组件（保持不变）
class _BlurredBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _BlurredBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

class _AnimatedIconContainer extends StatelessWidget {
  final IconData icon;
  final bool isDarkMode;
  const _AnimatedIconContainer({required this.icon, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Icon(
          icon,
          size: 56,
          color: isDarkMode
              ? CupertinoColors.systemGrey2
              : CupertinoColors.systemGrey3,
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _GlassButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue.withOpacity(isDarkMode ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CupertinoColors.activeBlue.withOpacity(isDarkMode ? 0.3 : 0.2),
                width: 0.5,
              ),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.activeBlue,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(),
      size: Size.infinite,
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CupertinoColors.label
      ..strokeWidth = 0.8;
    for (double x = 0; x < size.width; x += 30) {
      for (double y = 0; y < size.height; y += 30) {
        canvas.drawCircle(Offset(x, y), 0.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
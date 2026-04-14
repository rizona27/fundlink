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
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      child: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              children: [
                Positioned(
                  top: -topPadding - 50,
                  right: -50,
                  child: _BlurredBlob(
                    size: 250,
                    color: CupertinoColors.activeBlue.withOpacity(isDarkMode ? 0.12 : 0.08),
                  ),
                ),
                Positioned(
                  bottom: 100,
                  left: -50,
                  child: _BlurredBlob(
                    size: 200,
                    color: CupertinoColors.systemPurple.withOpacity(isDarkMode ? 0.1 : 0.05),
                  ),
                ),
                Positioned(
                  top: screenHeight * 0.3,
                  left: screenWidth * 0.7,
                  child: _BlurredBlob(
                    size: 180,
                    color: CupertinoColors.systemOrange.withOpacity(isDarkMode ? 0.08 : 0.04),
                  ),
                ),
                Opacity(
                  opacity: isDarkMode ? 0.03 : 0.01,
                  child: const _GridBackground(),
                ),
              ],
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 40,
                right: 40,
                top: topPadding + 20,
                bottom: bottomPadding + 20,
              ),
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
        ],
      ),
    );
  }
}

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
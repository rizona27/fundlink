import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../main.dart'; // ✅ 正确引用主界面的 MainTabView

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _contentController;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textOffset;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.2, 0.8, curve: Curves.easeOut)),
    );

    _textOffset = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.2, 0.8, curve: Curves.easeOut)),
    );

    _contentController.forward();

    // 5秒后淡入淡出跳转到主界面
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainTabView(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // 背景渐变（深色/浅色适配）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode
                    ? [const Color(0xFF1A1A2E), const Color(0xFF16213E), const Color(0xFF0F3460)]
                    : [const Color(0xFFF8F5F0), const Color(0xFFF0ECE5), const Color(0xFFF8F5F0)],
              ),
            ),
          ),
          // 动态光圈（深色模式颜色调整）
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildGlowCircle(index: 0, rotation: _glowController.value * 2 * math.pi),
                  _buildGlowCircle(index: 1, rotation: _glowController.value * 2 * math.pi * 0.3),
                ],
              );
            },
          ),
          // 文字内容
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _textOpacity,
                child: SlideTransition(
                  position: _textOffset,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      const Text(
                        "Less is",
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w200, fontFamily: 'Serif'),
                      ),
                      const Text(
                        "More.",
                        style: TextStyle(fontSize: 60, fontWeight: FontWeight.w600, fontFamily: 'Serif'),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Text(
                          "Finding Abundance Through Subtraction",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w300),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "专业 · 专注 · 价值",
                        style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Copyright © 2026 Rizona.",
                        style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.grey[500] : Colors.grey[700]),
                      ),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowCircle({required int index, required double rotation}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final glowColor = isDarkMode
        ? const Color(0xFF6C63FF).withOpacity(0.2)  // 深色模式用紫色光晕
        : const Color(0xFFE8D5C4).withOpacity(0.3); // 浅色模式用暖色光晕

    return Positioned(
      top: 100,
      left: 50,
      child: Transform.rotate(
        angle: rotation,
        child: Container(
          width: 250.0 + (index * 100),
          height: 250.0 + (index * 100),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [glowColor, Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}
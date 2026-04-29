import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../main.dart';

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

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainTabView(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 1200),
          ),
        );
      }
    });
  }

  Route? get _currentRoute {
    return ModalRoute.of(context);
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
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode
                    // 深色模式：深蓝紫色渐变，神秘优雅
                    ? [const Color(0xFF1a1b3a), const Color(0xFF2d1b4e), const Color(0xFF1f2937)]
                    // 浅色模式：温暖的金粉色渐变，柔和舒适
                    : [const Color(0xFFFFF5E6), const Color(0xFFFFE8D6), const Color(0xFFFFF0F0)],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              return Stack(
                children: [
                  // 主光晕 - 更大更柔和的扩散效果
                  _buildSoftGlow(index: 0, opacity: 0.08),
                  // 次要光晕 - 偏移位置，增加层次感
                  _buildSoftGlow(index: 1, opacity: 0.06, offsetX: 100, offsetY: 50),
                  // 第三个光晕 - 另一个方向
                  _buildSoftGlow(index: 2, opacity: 0.05, offsetX: -50, offsetY: 100),
                ],
              );
            },
          ),
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
                      Text(
                        "Less is",
                        style: TextStyle(
                          fontSize: 32, 
                          fontWeight: FontWeight.w200, 
                          fontFamily: 'Serif',
                          // 深色模式：淡紫白色；浅色模式：深紫褐色
                          color: isDarkMode ? const Color(0xFFE8E6F0) : const Color(0xFF5A4A42),
                        ),
                      ),
                      Text(
                        "More.",
                        style: TextStyle(
                          fontSize: 60, 
                          fontWeight: FontWeight.w600, 
                          fontFamily: 'Serif',
                          // 深色模式：纯白略带紫调；浅色模式：深棕色
                          color: isDarkMode ? const Color(0xFFF5F3FF) : const Color(0xFF3D2E28),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          "Finding Abundance Through Subtraction",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.w300,
                            // 深色模式：淡紫色；浅色模式：暖灰色
                            color: isDarkMode ? const Color(0xFFC8C4D9).withOpacity(0.7) : const Color(0xFF8B7D72),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "专业 · 专注 · 价值",
                        style: TextStyle(
                          fontSize: 13, 
                          // 深色模式：淡紫灰；浅色模式：暖灰褐
                          color: isDarkMode ? const Color(0xFFA8A4B8).withOpacity(0.6) : const Color(0xFF9E8E82),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Copyright © 2026 Rizona.",
                        style: TextStyle(
                          fontSize: 11, 
                          // 深色模式：更淡的紫灰；浅色模式：浅暖灰
                          color: isDarkMode ? const Color(0xFF8884A0).withOpacity(0.5) : const Color(0xFFB8A89A),
                        ),
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

  Widget _buildSoftGlow({required int index, required double opacity, double offsetX = 0, double offsetY = 0}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // 使用更柔和的渐变色彩
    final glowColor = isDarkMode
        ? const Color(0xFF9B8AFF)  // 淡紫色
        : const Color(0xFFFFB347); // 金橙色

    // 根据索引设置不同的大小和位置
    final sizes = [400.0, 300.0, 250.0];
    final size = sizes[index] ?? 300.0;
    
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.3 + offsetY,
      left: MediaQuery.of(context).size.width * 0.5 - size / 2 + offsetX,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            // 更平滑的多层渐变，从中心到边缘逐渐消失
            colors: [
              glowColor.withOpacity(opacity),
              glowColor.withOpacity(opacity * 0.6),
              glowColor.withOpacity(opacity * 0.3),
              glowColor.withOpacity(opacity * 0.1),
              Colors.transparent,
            ],
            stops: const [0.0, 0.2, 0.4, 0.7, 1.0],
          ),
        ),
      ),
    );
  }
}
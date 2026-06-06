import 'package:flutter/material.dart';
import '../main.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _line1, _line2, _line3, _line4, _footer;

  static const _enFont = 'FundLinkEN';
  static const _zhFont = 'FundLinkZH';

  // Golden-ratio vertical placement: visual centre at ~38.2% from top.
  static double _goldenTop(double height) => height * 0.30;
  // Horizontal breathing room proportional to screen width.
  static double _sideMargin(double width) => width * 0.12;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));

    _line1 = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.00, 0.18, curve: Curves.easeOut)));
    _line2 = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.10, 0.30, curve: Curves.easeOut)));
    _line3 = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.30, 0.50, curve: Curves.easeOut)));
    _line4 = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.40, 0.60, curve: Curves.easeOut)));
    _footer = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.55, 0.75, curve: Curves.easeOut)));

    _ctrl.forward();

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, a, __) => const MainTabView(),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
          transitionDuration: const Duration(milliseconds: 1000),
        ));
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _fadeUp(Animation<double> a, Widget child) {
    return AnimatedBuilder(
      animation: a,
      builder: (_, c) {
        final t = a.value;
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: c));
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    final textColor = isDark ? const Color(0xFFE8E2D8) : const Color(0xFF2C2416);
    final muted = isDark ? const Color(0xFF8A8074) : const Color(0xFF908578);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF11111C), Color(0xFF191928), Color(0xFF151522)]
                : const [Color(0xFFFBF9F6), Color(0xFFF4EFE9), Color(0xFFEFE8E0)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Main content — placed at golden-ratio vertical position ──
              Positioned(
                top: _goldenTop(screen.height),
                left: _sideMargin(screen.width),
                right: _sideMargin(screen.width),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fadeUp(_line1, Text('FundLink',
                        style: TextStyle(fontSize: 44, fontWeight: FontWeight.w400,
                            fontFamily: _enFont, fontFamilyFallback: const ['Serif'],
                            letterSpacing: 8.0, color: textColor))),
                    const SizedBox(height: 6),
                    _fadeUp(_line2, Text('一基暴富',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w400,
                            fontFamily: _zhFont, fontFamilyFallback: const ['Serif'],
                            letterSpacing: 10.0, color: textColor.withOpacity(0.85)))),
                    const SizedBox(height: 52),
                    _fadeUp(_line3, Text('less is more',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300,
                            letterSpacing: 5.0, color: muted))),
                    const SizedBox(height: 6),
                    _fadeUp(_line4, Text('Finding Abundance Through Subtraction',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w300,
                            color: muted.withOpacity(0.7)))),
                  ],
                ),
              ),
              // ── Footer ──
              Positioned(
                bottom: 48,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _footer,
                  builder: (_, __) => Opacity(
                    opacity: _footer.value,
                    child: Column(children: [
                      Text('专业 · 专注 · 价值',
                          style: TextStyle(fontSize: 12, color: muted.withOpacity(0.45))),
                      const SizedBox(height: 4),
                      Text('Copyright © 2026 Rizona.',
                          style: TextStyle(fontSize: 10, color: muted.withOpacity(0.3))),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

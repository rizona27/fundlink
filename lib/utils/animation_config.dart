import 'package:flutter/cupertino.dart';

class AnimationConfig {
  
  static const Duration durationFast = Duration(milliseconds: 150);
  
  static const Duration durationStandard = Duration(milliseconds: 200);
  
  static const Duration durationMedium = Duration(milliseconds: 300);
  
  static const Duration durationSlow = Duration(milliseconds: 400);
  
  static const Duration durationVerySlow = Duration(milliseconds: 500);
  
  static const Curve curveEaseOutCubic = Curves.easeOutCubic;
  
  static const Curve curveEaseInOutCubic = Curves.easeInOutCubic;
  
  static const Curve curveEaseOutQuart = Curves.easeOutQuart;
  
  static const Curve curveElasticOut = Curves.elasticOut;
  
  static const Duration durationExpand = durationSlow;
  static const Curve curveExpand = curveEaseOutCubic;
  
  static const Duration durationFade = durationStandard;
  static const Curve curveFade = curveEaseOutCubic;
  
  static const Duration durationPageTransition = durationMedium;
  static const Curve curvePageTransition = curveEaseOutCubic;
  
  static const Duration durationButtonFeedback = durationFast;
  static const Curve curveButtonFeedback = curveEaseOutQuart;
  
  static const Duration durationToast = durationStandard;
  static const Curve curveToast = curveEaseOutCubic;
  
  static const Duration durationSearchBar = durationMedium;
  static const Curve curveSearchBar = curveEaseOutCubic;
  
  static Widget fadeTransition({
    required Widget child,
    required double opacity,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedOpacity(
      opacity: opacity,
      duration: duration ?? durationFade,
      curve: curve ?? curveFade,
      child: child,
    );
  }
  
  static Widget sizeTransition({
    required Widget child,
    required bool isVisible,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedSize(
      duration: duration ?? durationExpand,
      curve: curve ?? curveExpand,
      child: isVisible ? child : const SizedBox.shrink(),
    );
  }
  
  static Widget containerTransition({
    required Widget child,
    Color? color,
    EdgeInsetsGeometry? padding,
    BorderRadiusGeometry? borderRadius,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedContainer(
      duration: duration ?? durationMedium,
      curve: curve ?? curveEaseInOutCubic,
      color: color,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
  
  static Widget fadeInWithSize({
    required Widget child,
    required bool isVisible,
    Duration? duration,
    Curve? curve,
  }) {
    final dur = duration ?? durationExpand;
    final crv = curve ?? curveExpand;
    
    return AnimatedSize(
      duration: dur,
      curve: crv,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: dur,
        curve: crv,
        child: isVisible ? child : const SizedBox.shrink(),
      ),
    );
  }
  
  static PageRouteBuilder<T> createPageRoute<T>({
    required Widget page,
    Duration? duration,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 0.05);
        const end = Offset.zero;
        
        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curvePageTransition),
        );
        var offsetAnimation = animation.drive(tween);
        
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
      transitionDuration: duration ?? durationPageTransition,
    );
  }
  
  static Widget dialogTransition({
    required Widget child,
    required Animation<double> animation,
  }) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: curveEaseOutCubic,
          ),
        ),
        child: child,
      ),
    );
  }
  
  static Widget buttonFeedback({
    required Widget child,
    required bool isPressed,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedScale(
      scale: isPressed ? 0.95 : 1.0,
      duration: duration ?? durationButtonFeedback,
      curve: curve ?? curveButtonFeedback,
      child: child,
    );
  }
  
  
  static Widget cardTapFeedback({
    required Widget child,
    required bool isPressed,
    Duration? duration,
    Curve? curve,
  }) {
    final dur = duration ?? durationButtonFeedback;
    final crv = curve ?? curveButtonFeedback;
    
    return AnimatedOpacity(
      opacity: isPressed ? 0.7 : 1.0,
      duration: dur,
      curve: crv,
      child: AnimatedScale(
        scale: isPressed ? 0.98 : 1.0,
        duration: dur,
        curve: crv,
        child: child,
      ),
    );
  }
  
  static Widget listExpandTransition({
    required Widget child,
    required bool isExpanded,
    Duration? duration,
    Curve? curve,
  }) {
    final dur = duration ?? durationExpand;
    final crv = curve ?? curveExpand;
    
    return AnimatedSize(
      duration: dur,
      curve: crv,
      child: AnimatedOpacity(
        opacity: isExpanded ? 1.0 : 0.0,
        duration: dur,
        curve: crv,
        child: isExpanded ? child : const SizedBox.shrink(),
      ),
    );
  }
  
  static Widget contentSwitchTransition({
    required Widget child,
    Key? key,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedSwitcher(
      duration: duration ?? durationMedium,
      switchInCurve: curve ?? curveEaseOutCubic,
      switchOutCurve: curve ?? curveEaseOutCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
  
  static Widget visibilityTransition({
    required Widget child,
    required bool isVisible,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: duration ?? durationFade,
      curve: curve ?? curveFade,
      child: child,
    );
  }
  
  static Widget loadingTransition({
    required Widget child,
    required bool isLoading,
    Widget? loadingWidget,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedSwitcher(
      duration: duration ?? durationMedium,
      switchInCurve: curve ?? curveEaseOutCubic,
      switchOutCurve: curve ?? curveEaseOutCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: isLoading 
          ? (loadingWidget ?? const Center(child: CupertinoActivityIndicator()))
          : child,
    );
  }
  
  static Widget numberTransition({
    required String text,
    TextStyle? style,
    Duration? duration,
    Curve? curve,
  }) {
    return AnimatedSwitcher(
      duration: duration ?? durationFast,
      switchInCurve: curve ?? curveEaseOutQuart,
      switchOutCurve: curve ?? curveEaseOutQuart,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: Text(
        text,
        key: ValueKey(text),
        style: style,
      ),
    );
  }
}

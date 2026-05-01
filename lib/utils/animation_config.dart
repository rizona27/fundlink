import 'package:flutter/cupertino.dart';

/// 统一动画配置 - 为整个项目提供一致的过渡效果
/// 
/// 使用示例:
/// ```dart
/// // 卡片展开/折叠
/// AnimatedSize(
///   duration: AnimationConfig.durationExpand,
///   curve: AnimationConfig.curveExpand,
///   child: ...
/// )
/// 
/// // 淡入淡出
/// AnimatedOpacity(
///   opacity: isVisible ? 1.0 : 0.0,
///   duration: AnimationConfig.durationFade,
///   curve: AnimationConfig.curveFade,
///   child: ...
/// )
/// ```
class AnimationConfig {
  // ==================== 动画时长配置 ====================
  
  /// 快速动画 (150ms) - 用于按钮反馈、小图标变化
  static const Duration durationFast = Duration(milliseconds: 150);
  
  /// 标准动画 (200ms) - 用于Toast提示、简单状态切换
  static const Duration durationStandard = Duration(milliseconds: 200);
  
  /// 中等动画 (300ms) - 用于页面导航、对话框显示
  static const Duration durationMedium = Duration(milliseconds: 300);
  
  /// 慢速动画 (400ms) - 用于卡片展开/折叠、内容区域显示
  static const Duration durationSlow = Duration(milliseconds: 400);
  
  /// 超慢动画 (500ms) - 用于特殊强调的过渡效果
  static const Duration durationVerySlow = Duration(milliseconds: 500);
  
  // ==================== 缓动曲线配置 ====================
  
  /// 标准缓出曲线 - 用于大多数展开/折叠动画
  static const Curve curveEaseOutCubic = Curves.easeOutCubic;
  
  /// 标准缓入缓出曲线 - 用于双向对称动画
  static const Curve curveEaseInOutCubic = Curves.easeInOutCubic;
  
  /// 快速缓出曲线 - 用于轻量级反馈
  static const Curve curveEaseOutQuart = Curves.easeOutQuart;
  
  /// 弹性缓出曲线 - 用于需要弹性的场景（暂未使用）
  static const Curve curveElasticOut = Curves.elasticOut;
  
  // ==================== 预定义动画类型 ====================
  
  /// 卡片展开/折叠动画配置
  static const Duration durationExpand = durationSlow; // 400ms
  static const Curve curveExpand = curveEaseOutCubic;
  
  /// 淡入淡出动画配置
  static const Duration durationFade = durationStandard; // 200ms
  static const Curve curveFade = curveEaseOutCubic;
  
  /// 页面导航动画配置
  static const Duration durationPageTransition = durationMedium; // 300ms
  static const Curve curvePageTransition = curveEaseOutCubic;
  
  /// 按钮反馈动画配置
  static const Duration durationButtonFeedback = durationFast; // 150ms
  static const Curve curveButtonFeedback = curveEaseOutQuart;
  
  /// Toast提示动画配置
  static const Duration durationToast = durationStandard; // 200ms
  static const Curve curveToast = curveEaseOutCubic;
  
  /// 搜索栏显示/隐藏动画配置
  static const Duration durationSearchBar = durationMedium; // 300ms
  static const Curve curveSearchBar = curveEaseOutCubic;
  
  // ==================== 辅助方法 ====================
  
  /// 创建淡入淡出过渡组件
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
  
  /// 创建尺寸变化过渡组件（用于展开/折叠）
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
  
  /// 创建容器属性动画（颜色、大小、圆角等）
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
  
  /// 创建组合动画：淡入 + 尺寸变化
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
  
  /// 创建页面路由过渡动画
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
  
  /// 创建对话框显示动画
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
  
  /// 创建按钮点击反馈动画
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
  
  // ==================== 新增动画辅助方法 ====================
  
  /// 创建卡片点击反馈动画（缩放 + 透明度）
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
  
  /// 创建列表项展开/收起动画（带淡入淡出）
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
  
  /// 创建内容切换动画（使用AnimatedSwitcher）
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
  
  /// 创建平滑的显示/隐藏过渡（保持布局空间）
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
  
  /// 创建加载状态切换动画
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
  
  /// 创建数字变化动画（用于金额、百分比等）
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

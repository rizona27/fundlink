import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

/// 桌面端Tab键焦点管理工具类
class DesktopFocusManager {
  /// 检查是否为桌面平台
  static bool get isDesktopPlatform {
    return kIsWeb || 
           defaultTargetPlatform == TargetPlatform.windows ||
           defaultTargetPlatform == TargetPlatform.macOS ||
           defaultTargetPlatform == TargetPlatform.linux;
  }
  
  /// 处理Tab键事件，实现输入框之间的焦点切换
  static KeyEventResult handleTabKey(FocusNode currentNode, FocusScopeNode scope, {bool shiftPressed = false}) {
    if (!isDesktopPlatform) {
      return KeyEventResult.ignored;
    }
    
    // Tab键按下时切换到下一个焦点
    if (shiftPressed) {
      // Shift+Tab 切换到上一个焦点
      scope.previousFocus();
    } else {
      // Tab 切换到下一个焦点
      scope.nextFocus();
    }
    
    return KeyEventResult.handled;
  }
  
  /// 为输入框添加Tab键监听器
  static void attachTabListener(FocusNode focusNode, FocusScopeNode scope) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        // 可以在这里添加自定义的Tab键处理逻辑
      }
    });
  }
}

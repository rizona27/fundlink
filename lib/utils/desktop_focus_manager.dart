import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'view_utils.dart';

class DesktopFocusManager {
  static KeyEventResult handleTabKey(FocusNode currentNode, FocusScopeNode scope, {bool shiftPressed = false}) {
    if (!ViewUtils.isDesktopPlatform()) {
      return KeyEventResult.ignored;
    }
    
    if (shiftPressed) {
      scope.previousFocus();
    } else {
      scope.nextFocus();
    }
    
    return KeyEventResult.handled;
  }
  
  static void attachTabListener(FocusNode focusNode, FocusScopeNode scope) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
      }
    });
  }
}

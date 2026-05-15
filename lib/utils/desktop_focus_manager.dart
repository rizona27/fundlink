import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

class DesktopFocusManager {
  static bool get isDesktopPlatform {
    return kIsWeb || 
           defaultTargetPlatform == TargetPlatform.windows ||
           defaultTargetPlatform == TargetPlatform.macOS ||
           defaultTargetPlatform == TargetPlatform.linux;
  }
  
  static KeyEventResult handleTabKey(FocusNode currentNode, FocusScopeNode scope, {bool shiftPressed = false}) {
    if (!isDesktopPlatform) {
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

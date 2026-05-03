import 'package:flutter/services.dart';
import '../constants/app_constants.dart';

/// 金额/份额/净值输入格式化器
/// - 只允许输入数字和小数点
/// - 小数点后最多 [AppConstants.maxDecimalPlaces] 位（默认4位）
/// - 整数部分最多 [AppConstants.maxIntegerDigits] 位（默认10位）
class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    // 只保留数字和小数点
    String filtered = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    
    // 确保只有一个小数点
    final parts = filtered.split('.');
    if (parts.length > 2) {
      filtered = parts[0] + '.' + parts[1];
    }
    
    // 如果以小数点开头，自动添加前导0
    if (filtered.startsWith('.')) {
      filtered = '0$filtered';
    }
    
    final newParts = filtered.split('.');
    String integerPart = newParts[0];
    String decimalPart = newParts.length > 1 ? newParts[1] : '';
    
    // 限制整数部分长度
    if (integerPart.length > AppConstants.maxIntegerDigits) {
      integerPart = integerPart.substring(0, AppConstants.maxIntegerDigits);
    }
    
    // 限制小数部分长度
    if (decimalPart.length > AppConstants.maxDecimalPlaces) {
      decimalPart = decimalPart.substring(0, AppConstants.maxDecimalPlaces);
    }
    
    // 组装最终结果
    String formatted;
    if (decimalPart.isEmpty) {
      formatted = integerPart;
    } else {
      formatted = '$integerPart.$decimalPart';
    }
    
    // 处理末尾是小数点的情况
    if (filtered.endsWith('.') && decimalPart.isEmpty && integerPart.isNotEmpty) {
      formatted = '$integerPart.';
    }
    
    // 如果格式化后的文本与原文本不同，更新光标位置
    if (formatted != newValue.text) {
      final cursorPos = formatted.length;
      return newValue.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: cursorPos),
      );
    }
    
    return newValue;
  }
}

/// 纯数字输入格式化器（不允许小数点）
/// - 只允许输入数字
/// - 最多 [AppConstants.maxIntegerDigits] 位（默认10位）
class IntegerInputFormatter extends TextInputFormatter {
  final int maxLength;
  
  IntegerInputFormatter({this.maxLength = AppConstants.maxIntegerDigits});
  
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    // 只保留数字
    final filtered = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    
    // 限制长度
    final limited = filtered.length > maxLength 
        ? filtered.substring(0, maxLength) 
        : filtered;
    
    // 如果过滤后的文本与原文本不同，更新光标位置
    if (limited != newValue.text) {
      return newValue.copyWith(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
    }
    
    return newValue;
  }
}

/// 客户号输入格式化器
/// - 只允许输入数字
/// - 最多12位
class ClientIdInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final filtered = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = filtered.length > 12 ? filtered.substring(0, 12) : filtered;
    
    if (limited != newValue.text) {
      return newValue.copyWith(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
    }
    return newValue;
  }
}

/// 客户姓名输入格式化器
/// - 允许中文、英文、数字和空格
/// - 最多一个空格
/// - 最大长度: 5个中文字符 或 10个英文字符
class ClientNameInputFormatter extends TextInputFormatter {
  static const int maxChineseChars = 5;  // 最多5个中文字符
  static const int maxEnglishChars = 10; // 最多10个英文字符
  
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final allowedPattern = RegExp(r'[a-zA-Z0-9\u4e00-\u9fa5 ]');
    String filtered = newValue.text
        .split('')
        .where((c) => allowedPattern.hasMatch(c))
        .join('');
    
    // 将多个连续空格替换为单个空格
    filtered = filtered.replaceAll(RegExp(r' +'), ' ');
    
    // 最多只允许一个空格
    final spaceCount = filtered.split('').where((c) => c == ' ').length;
    if (spaceCount > 1) {
      final firstSpaceIndex = filtered.indexOf(' ');
      if (firstSpaceIndex != -1) {
        filtered = filtered.substring(0, firstSpaceIndex + 1) +
            filtered.substring(firstSpaceIndex + 1).replaceAll(' ', '');
      }
    }
    
    // 检查长度限制: 5个中文或10个英文
    final chineseCount = filtered.runes.where((r) => r >= 0x4e00 && r <= 0x9fff).length;
    final englishCount = filtered.runes.where((r) => (r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a)).length;
    final digitCount = filtered.runes.where((r) => r >= 0x30 && r <= 0x39).length;
    
    // 如果包含中文，按中文字符数限制；否则按英文字符数限制
    bool exceedsLimit = false;
    if (chineseCount > 0) {
      // 有中文：总字符数不能超过5（包括空格和数字）
      if (filtered.length > maxChineseChars) {
        exceedsLimit = true;
      }
    } else {
      // 纯英文/数字：总字符数不能超过10
      if (filtered.length > maxEnglishChars) {
        exceedsLimit = true;
      }
    }
    
    if (exceedsLimit) {
      // 截断到最大长度
      if (chineseCount > 0) {
        filtered = filtered.substring(0, maxChineseChars);
      } else {
        filtered = filtered.substring(0, maxEnglishChars);
      }
    }
    
    if (filtered != newValue.text) {
      final cursorPos = filtered.length;
      return newValue.copyWith(
        text: filtered,
        selection: TextSelection.collapsed(offset: cursorPos),
      );
    }
    return newValue;
  }
}

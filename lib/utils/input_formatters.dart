import 'package:flutter/services.dart';
import '../constants/app_constants.dart';

class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    String filtered = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    
    final parts = filtered.split('.');
    if (parts.length > 2) {
      filtered = parts[0] + '.' + parts[1];
    }
    
    if (filtered.startsWith('.')) {
      filtered = '0$filtered';
    }
    
    final newParts = filtered.split('.');
    String integerPart = newParts[0];
    String decimalPart = newParts.length > 1 ? newParts[1] : '';
    
    if (integerPart.length > AppConstants.maxIntegerDigits) {
      integerPart = integerPart.substring(0, AppConstants.maxIntegerDigits);
    }
    
    if (decimalPart.length > AppConstants.maxDecimalPlaces) {
      decimalPart = decimalPart.substring(0, AppConstants.maxDecimalPlaces);
    }
    
    String formatted;
    if (decimalPart.isEmpty) {
      formatted = integerPart;
    } else {
      formatted = '$integerPart.$decimalPart';
    }
    
    if (filtered.endsWith('.') && decimalPart.isEmpty && integerPart.isNotEmpty) {
      formatted = '$integerPart.';
    }
    
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

class IntegerInputFormatter extends TextInputFormatter {
  final int maxLength;
  
  IntegerInputFormatter({this.maxLength = AppConstants.maxIntegerDigits});
  
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final filtered = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    
    final limited = filtered.length > maxLength 
        ? filtered.substring(0, maxLength) 
        : filtered;
    
    if (limited != newValue.text) {
      return newValue.copyWith(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
    }
    
    return newValue;
  }
}

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

class ClientNameInputFormatter extends TextInputFormatter {
  static const int maxChineseChars = 5;
  static const int maxEnglishChars = 10;
  
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final allowedPattern = RegExp(r'[a-zA-Z0-9\u4e00-\u9fa5 ]');
    String filtered = newValue.text
        .split('')
        .where((c) => allowedPattern.hasMatch(c))
        .join('');
    
    filtered = filtered.replaceAll(RegExp(r' +'), ' ');
    
    final spaceCount = filtered.split('').where((c) => c == ' ').length;
    if (spaceCount > 1) {
      final firstSpaceIndex = filtered.indexOf(' ');
      if (firstSpaceIndex != -1) {
        filtered = filtered.substring(0, firstSpaceIndex + 1) +
            filtered.substring(firstSpaceIndex + 1).replaceAll(' ', '');
      }
    }
    
    final chineseCount = filtered.runes.where((r) => r >= 0x4e00 && r <= 0x9fff).length;
    final englishCount = filtered.runes.where((r) => (r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a)).length;
    final digitCount = filtered.runes.where((r) => r >= 0x30 && r <= 0x39).length;
    
    bool exceedsLimit = false;
    if (chineseCount > 0) {
      if (filtered.length > maxChineseChars) {
        exceedsLimit = true;
      }
    } else {
      if (filtered.length > maxEnglishChars) {
        exceedsLimit = true;
      }
    }
    
    if (exceedsLimit) {
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

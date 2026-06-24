import 'package:flutter/services.dart';
import '../constants/app_constants.dart';

class InputUtils {
  static String extractDigits(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }
  
  static String extractNumbersAndDots(String input) {
    return input.replaceAll(RegExp(r'[^0-9.]'), '');
  }
}

class AmountInputFormatter extends TextInputFormatter {
  final int maxIntDigits;
  final int maxDecDigits;

  AmountInputFormatter({
    int? maxIntDigits,
    int? maxDecDigits,
  })  : maxIntDigits = maxIntDigits ?? AppConstants.amountMaxIntegerDigits,
      maxDecDigits = maxDecDigits ?? AppConstants.amountMaxDecimalPlaces;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    String filtered = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');

    final parts = filtered.split('.');
    if (parts.length > 2) {
      filtered = '${parts[0]}.${parts[1]}';
    }

    if (filtered.startsWith('.')) {
      filtered = '0$filtered';
    }

    final newParts = filtered.split('.');
    String integerPart = newParts[0];
    String decimalPart = newParts.length > 1 ? newParts[1] : '';

    if (integerPart.length > maxIntDigits) {
      integerPart = integerPart.substring(0, maxIntDigits);
    }

    if (decimalPart.length > maxDecDigits) {
      decimalPart = decimalPart.substring(0, maxDecDigits);
    }

    String formatted;
    if (decimalPart.isEmpty && !filtered.endsWith('.')) {
      formatted = integerPart;
    } else if (decimalPart.isEmpty && filtered.endsWith('.')) {
      formatted = '$integerPart.';
    } else {
      formatted = '$integerPart.$decimalPart';
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

/// Input formatter for NAV fields — integer 5 digits, decimal 4 digits.
class NavInputFormatter extends AmountInputFormatter {
  NavInputFormatter()
      : super(
            maxIntDigits: AppConstants.navMaxIntegerDigits,
            maxDecDigits: AppConstants.navMaxDecimalPlaces);
}

/// Input formatter for amount/shares fields — integer 10 digits, decimal 2 digits.
/// (Default AmountInputFormatter already uses these limits from AppConstants,
/// so this is an alias for clarity.)
class StandardAmountInputFormatter extends AmountInputFormatter {
  StandardAmountInputFormatter()
      : super(
            maxIntDigits: AppConstants.amountMaxIntegerDigits,
            maxDecDigits: AppConstants.amountMaxDecimalPlaces);
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

/// Input formatter for fee rate (percentage) fields.
/// Allows up to [AppConstants.feeRateMaxIntegerDigits] integer digits and
/// [AppConstants.feeRateMaxDecimalPlaces] decimal places.
class FeeRateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    String filtered = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');

    final parts = filtered.split('.');
    if (parts.length > 2) {
      filtered = '${parts[0]}.${parts[1]}';
    }

    if (filtered.startsWith('.')) {
      filtered = '0$filtered';
    }

    final newParts = filtered.split('.');
    String integerPart = newParts[0];
    String decimalPart = newParts.length > 1 ? newParts[1] : '';

    if (integerPart.length > AppConstants.feeRateMaxIntegerDigits) {
      integerPart =
          integerPart.substring(0, AppConstants.feeRateMaxIntegerDigits);
    }

    if (decimalPart.length > AppConstants.feeRateMaxDecimalPlaces) {
      decimalPart =
          decimalPart.substring(0, AppConstants.feeRateMaxDecimalPlaces);
    }

    String formatted;
    if (decimalPart.isEmpty && !filtered.endsWith('.')) {
      formatted = integerPart;
    } else if (decimalPart.isEmpty && filtered.endsWith('.')) {
      formatted = '$integerPart.';
    } else {
      formatted = '$integerPart.$decimalPart';
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

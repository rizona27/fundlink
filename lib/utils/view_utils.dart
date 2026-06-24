import 'package:flutter/foundation.dart';

class ViewUtils {
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String formatDateTime(DateTime dateTime) {
    return '${formatDate(dateTime)} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  static String maskClientName(String name) {
    if (name.isEmpty) return '';
    if (name.length == 1) return '*';
    if (name.length == 2) return '${name[0]}*';
    return '${name[0]}${'*' * (name.length - 2)}${name[name.length - 1]}';
  }

  static String maskString(String data, {int visibleChars = 2}) {
    if (data.length <= visibleChars) {
      return '*' * data.length;
    }
    return data.substring(0, visibleChars) + '*' * (data.length - visibleChars);
  }

  static bool isDesktopPlatform() {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static String truncateString(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  static double parseDouble(String value, {double defaultValue = 0.0}) {
    return double.tryParse(value) ?? defaultValue;
  }

  static int parseInt(String value, {int defaultValue = 0}) {
    return int.tryParse(value) ?? defaultValue;
  }
}

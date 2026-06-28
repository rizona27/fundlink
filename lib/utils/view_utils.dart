import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

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

  /// Masks all characters after the first one, keeping only the first char visible.
  /// Example: '张三' → '张*', '李四五' → '李**'
  static String obscuredName(String name) {
    if (name.isEmpty) return name;
    if (name.length == 1) return name;
    return '${name[0]}${'*' * (name.length - 1)}';
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

  // ── Model deserialization helpers ──────────────────────────

  /// Safe cast from a dynamic map value to double.
  static double toDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return fallback;
  }

  /// Safe cast from a dynamic map value to int.
  static int toInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  /// Safe cast from a 0/1 int or bool to bool.
  static bool toBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is int) return v == 1;
    return fallback;
  }

  /// Safe DateTime parse from an ISO-8601 string or DateTime value.
  static DateTime toDateTime(dynamic v, {DateTime? fallback}) {
    if (v == null) return fallback ?? DateTime.now();
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
    }
    return fallback ?? DateTime.now();
  }

  /// Executes an HTTP request with automatic retry on failure.
  ///
  /// Retries up to [AppConstants.maxNetworkRetries] times with exponential
  /// backoff based on [AppConstants.networkRetryDelayBase].
  /// Returns the response on success (status 200), or null if all retries fail.
  static Future<http.Response?> retryFetch(
    Future<http.Response> Function() request,
  ) async {
    http.Response? response;
    var retryCount = 0;
    Exception? lastException;

    while (retryCount <= AppConstants.maxNetworkRetries) {
      try {
        response = await request();
        if (response.statusCode == 200) {
          break;
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        retryCount++;
        if (retryCount <= AppConstants.maxNetworkRetries) {
          await Future.delayed(Duration(
            milliseconds:
                AppConstants.networkRetryDelayBase.inMilliseconds * retryCount,
          ));
        }
      }
    }

    return response;
  }
}

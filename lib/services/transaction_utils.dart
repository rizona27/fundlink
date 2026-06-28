import '../services/china_trading_day_service.dart';

/// Static utility methods for trading day calculations and transaction date logic.
/// Extracted from DataManager to reduce its scope and enable independent testing.
class TransactionUtils {
  TransactionUtils._(); // prevent instantiation

  static final ChinaTradingDayService _tds = ChinaTradingDayService();

  static bool isWeekday(DateTime date) {
    final weekday = date.weekday;
    return weekday >= DateTime.monday && weekday <= DateTime.friday;
  }

  static Future<bool> isTradingDay(DateTime date) async {
    return await _tds.isTradingDay(date);
  }

  static Future<DateTime> getNextTradingDay({DateTime? from}) async {
    return await _tds.getNextTradingDay(from: from);
  }

  static Future<DateTime> getPreviousTradingDay({DateTime? from}) async {
    return await _tds.getPreviousTradingDay(from: from);
  }

  static DateTime getNextWeekday(DateTime from) {
    DateTime next = from.add(const Duration(days: 1));
    while (!isWeekday(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  static DateTime calculateNavDateForTrade(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);

    final isTradeDay = _tds.isTradingDaySync(tradeDay);

    if (tradeDay.isBefore(today)) {
      if (!isTradeDay) {
        return _tds.getNextTradingDaySync(from: tradeDay);
      } else {
        if (isAfter1500) {
          return _tds.getNextTradingDaySync(from: tradeDay);
        } else {
          return tradeDay;
        }
      }
    }

    final effectiveIsAfter1500 = isTradeDay ? isAfter1500 : false;

    if (effectiveIsAfter1500) {
      return _tds.getNextTradingDaySync(from: tradeDay);
    } else {
      return isTradeDay ? tradeDay : _tds.getNextTradingDaySync(from: tradeDay);
    }
  }

  static Future<DateTime> calculateNavDateForTradeAsync(
      DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);

    final isTradeTradingDay = await isTradingDay(tradeDay);

    if (tradeDay.isBefore(today)) {
      if (!isTradeTradingDay) {
        return await getNextTradingDay(from: tradeDay);
      } else {
        if (isAfter1500) {
          return await getNextTradingDay(from: tradeDay);
        } else {
          return tradeDay;
        }
      }
    }

    final effectiveIsAfter1500 = isTradeTradingDay ? isAfter1500 : false;

    if (effectiveIsAfter1500) {
      return await getNextTradingDay(from: tradeDay);
    } else {
      return isTradeTradingDay ? tradeDay : await getNextTradingDay(from: tradeDay);
    }
  }

  static DateTime calculateConfirmDate(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final navDate = calculateNavDateForTrade(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);

    if (navDay.isBefore(today)) {
      return today;
    }

    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    final isTradeDay = _tds.isTradingDaySync(tradeDay);
    final effectiveIsAfter1500 = isTradeDay ? isAfter1500 : false;

    DateTime actualNavDate;
    if (effectiveIsAfter1500) {
      actualNavDate = _tds.getNextTradingDaySync(from: tradeDay);
    } else {
      actualNavDate =
          isTradeDay ? tradeDay : _tds.getNextTradingDaySync(from: tradeDay);
    }

    return _tds.getNextTradingDaySync(from: actualNavDate);
  }

  static Future<DateTime> calculateConfirmDateAsync(
      DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final navDate = await calculateNavDateForTradeAsync(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);

    if (navDay.isBefore(today)) {
      return today;
    }

    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    final isTradeTradingDay = await isTradingDay(tradeDay);
    final effectiveIsAfter1500 = isTradeTradingDay ? isAfter1500 : false;

    if (effectiveIsAfter1500) {
      final actualNavDate = await getNextTradingDay(from: tradeDay);
      return await getNextTradingDay(from: actualNavDate);
    } else {
      final actualNavDate = isTradeTradingDay
          ? tradeDay
          : await getNextTradingDay(from: tradeDay);
      return await getNextTradingDay(from: actualNavDate);
    }
  }

  static bool isTransactionPending(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final navDate = calculateNavDateForTrade(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);

    return !navDay.isBefore(today);
  }

  static Future<bool> isTransactionPendingAsync(
      DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final navDate = await calculateNavDateForTradeAsync(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);

    return !navDay.isBefore(today);
  }

  static Future<DateTime> getTradeApplicationDate(DateTime submitTime) async {
    final submitDay =
        DateTime(submitTime.year, submitTime.month, submitTime.day);
    final hour = submitTime.hour;

    final tradingDay = await isTradingDay(submitDay);

    if (tradingDay) {
      if (hour < 15) {
        return submitDay;
      } else {
        return await getNextTradingDay(from: submitDay);
      }
    } else {
      return await getNextTradingDay(from: submitDay);
    }
  }
}

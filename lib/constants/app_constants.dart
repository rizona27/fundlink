import 'package:package_info_plus/package_info_plus.dart';

class AppConstants {
  AppConstants._();

  static const String keyHoldings = 'fund_holdings';
  static const String keyTransactions = 'fund_transactions';
  static const String keyLogs = 'logs';
  static const String keyPrivacyMode = 'privacy_mode';
  static const String keyThemeMode = 'theme_mode';
  static const String keyValuationCache = 'valuation_cache';
  static const String keyShowHoldersOnSummaryCard = 'show_holders_on_summary_card';
  static const String keyFundInfoCache = 'fund_info_cache';
  static const String keyExpandedClients = 'clientview_expanded_clients';
  static const String keyPinnedSectionExpanded = 'clientview_pinned_section_expanded';
  static const String keySortKey = 'summary_sort_key';
  static const String keySortOrder = 'summary_sort_order';
  static const String keyExpandedFunds = 'summary_expanded_funds';
  static const String keyValuationRefreshInterval = 'valuationRefreshInterval';
  
  static const String keyClientMappings = 'client_mappings';

  static const String nasBackendUrl = 'https://fundlink.cr315.com';

  static String appVersion = '1.0.0';
  static String appVersionWithPrefix = 'v1.0.0';
  static String userAgentApp = 'FundLink-App/1.0.0';

  static Future<void> init() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
      appVersionWithPrefix = 'v${packageInfo.version}';
      userAgentApp = 'FundLink-App/${packageInfo.version}';
    } catch (e) {
      // 使用默认版本号
    }
  }
  static const String userAgentVersionChecker = 'FundLink-Version-Checker';
  
  static const String githubRepoOwner = 'rizona27';
  static const String githubRepoName = 'fundlink';
  static const String githubReleaseApiUrl = 'https://api.github.com/repos/$githubRepoOwner/$githubRepoName/releases/latest';
  static const String githubReleasePageUrl = 'https://github.com/$githubRepoOwner/$githubRepoName/releases';
  static const String githubProjectUrl = 'https://github.com/$githubRepoOwner/$githubRepoName';
  
  static const String apiEastmoneyPingzhongdata = 'https://fund.eastmoney.com/pingzhongdata/{code}.js';
  static const String apiEastmoneyFundArchives = 'https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code={code}&topline=10';
  static const String apiGtimgStockQuote = 'https://qt.gtimg.cn/q={codes}';

  // Backend fund analysis API (akshare-powered)
  static String get apiFundHoldings => '$nasBackendUrl/api/fund/holdings';
  static String get apiStockAnalysis => '$nasBackendUrl/api/stock/analysis';
  static String get apiPortfolioAnalysis => '$nasBackendUrl/api/portfolio/analysis';
  
  static const List<String> apiValuationSources = [
    'https://fundgz.1234567.com.cn/js/{code}.js?rt={timestamp}',
  ];

  static const int valuationCacheValidSeconds = 3600;
  static const int fundInfoCacheValidDays = 36500;
  static const int fundInfoCacheValidHours = 4;
  static const int fundReturnCacheValidDays = 1;
  static const int versionInfoCacheValidHours = 24;
  static const int maxCacheSize = 500;
  static const int maxLogEntries = 200;


  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);
  static const Duration fastAnimationDuration = Duration(milliseconds: 200);
  static const Duration slowAnimationDuration = Duration(milliseconds: 400);
  static const Duration searchDebounceDuration = Duration(milliseconds: 400);
  
  static const double scrollThrottleMs = 16.0;
  static const double maxSwipeOffset = 70.0;

  static const int tradingDayCheckBatchSize = 5;
  static const int refreshBatchSize = 5;
  static const double tradeTimeThreshold = 15.0;

  // ─── Decimal precision: input & display ───
  //
  // 金额（amount/totalCost/totalValue/profit）：整数 10 位，小数 2 位
  // 净值（nav/currentNav/averageCost）：整数 5 位，小数 4 位
  // 份额（shares）：整数 10 位，小数 2 位
  // 费率（fee rate）：整数 2 位，小数 2 位
  // 收益率（return/percentage）：显示用 2 位

  // Input: amount / shares fields (integer 10, decimal 2)
  static const int amountMaxIntegerDigits = 10;
  static const int amountMaxDecimalPlaces = 2;

  // Input: NAV / average cost fields (integer 5, decimal 4)
  static const int navMaxIntegerDigits = 5;
  static const int navMaxDecimalPlaces = 4;

  // Input: fee rate (integer 2, decimal 2, range -99.99 ~ 100.00)
  static const int feeRateMaxIntegerDigits = 2;
  static const int feeRateMaxDecimalPlaces = 2;
  static const double feeRateMinValue = -99.99;
  static const double feeRateMaxValue = 100.0;

  // Display precision (toStringAsFixed argument)
  static const int amountDecimalPlaces = 2; // 金额
  static const int navDecimalPlaces = 4; // 净值
  static const int sharesDecimalPlaces = 2; // 份额
  static const int rateDecimalPlaces = 2; // 收益率/百分比
  static const int stockPriceDecimalPlaces = 2; // 股价

  // Legacy aliases (kept for backward compat with existing code)
  static const int maxDecimalPlaces = 4;
  static const int maxIntegerDigits = 10;
  static const String numberPattern = r'^[0-9]*\.?[0-9]*$';

  static const Duration networkRequestTimeout = Duration(seconds: 20);
  static const int maxNetworkRetries = 2;
  static const Duration networkRetryDelayBase = Duration(milliseconds: 500);
  
  static const Duration cacheCleanupInterval = Duration(minutes: 5);
  static const int profitCacheMaxSize = 50;
  static const Duration profitCacheTtl = Duration(minutes: 30);
  static const int portfolioAnalysisCacheMaxSize = 10;
  static const Duration portfolioAnalysisCacheTtl = Duration(minutes: 30);
  static const Duration stockQuoteCacheTtl = Duration(minutes: 10);
  static const int transactionHistoryCacheMaxSize = 30;
  static const Duration transactionHistoryCacheTtl = Duration(hours: 1);
  
  static const Duration memoryMonitorInterval = Duration(seconds: 10);
  static const int memoryWarningThresholdMB = 200;
  static const int memoryCriticalThresholdMB = 400;
  
  static const Duration toastDuration = Duration(seconds: 2);
  static const Duration toastAnimationDuration = Duration(milliseconds: 300);
  
  static const Duration scrollThrottleDuration = Duration(milliseconds: 16);
  
  static const int maxClientNameLength = 20;
  static const int maxRemarksLength = 30;
  static const String fundCodePattern = r'^\d{6}$';
  
  static const double cardTapOpacity = 0.7;
  static const double cardTapScale = 0.98;
  static const double buttonPressedScale = 0.95;
  
  static const double toastMaxWidth = 320.0;
  static const double toastBottomOffset = 100.0;
  static const double toastBorderRadius = 12.0;
  
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  static const Duration dialogTransitionDuration = Duration(milliseconds: 300);
  static const Duration expandAnimationDuration = Duration(milliseconds: 400);
  
  static const int searchDebounceMs = 400;
  static const int versionCheckInitialDelaySeconds = 1;
  static const int versionCheckRetryDelaySeconds = 3;
  static const int versionCheckMaxRetries = 3;
  static const Duration versionCheckLongRetryDelay = Duration(minutes: 5);
  static const Duration versionCheckFinalRetryDelay = Duration(minutes: 10);
}

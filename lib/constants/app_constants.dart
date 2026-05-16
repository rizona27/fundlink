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
  
  static const String userAgentApp = 'FundLink-App/1.2.0';
  static const String userAgentVersionChecker = 'FundLink-Version-Checker';
  
  static const String githubRepoOwner = 'rizona27';
  static const String githubRepoName = 'fundlink';
  static const String githubReleaseApiUrl = 'https://api.github.com/repos/$githubRepoOwner/$githubRepoName/releases/latest';
  static const String githubReleasePageUrl = 'https://github.com/$githubRepoOwner/$githubRepoName/releases';
  static const String githubProjectUrl = 'https://github.com/$githubRepoOwner/$githubRepoName';
  
  static const String apiEastmoneyPingzhongdata = 'https://fund.eastmoney.com/pingzhongdata/{code}.js';
  static const String apiEastmoneyFundArchives = 'https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code={code}&topline=10';
  static const String apiGtimgStockQuote = 'https://qt.gtimg.cn/q={codes}';
  
  static const List<String> apiValuationSources = [
    'https://fundgz.1234567.com.cn/js/{code}.js?rt={timestamp}',
  ];

  static const int valuationCacheValidSeconds = 3600;
  static const int fundInfoCacheValidDays = 36500;
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

  static const int maxDecimalPlaces = 4;
  static const int maxIntegerDigits = 10;
  static const String numberPattern = r'^[0-9]*\.?[0-9]*$';

  static const Duration networkRequestTimeout = Duration(seconds: 20);
  static const int maxNetworkRetries = 2;
  static const Duration networkRetryDelayBase = Duration(milliseconds: 500);
  
  static const Duration cacheCleanupInterval = Duration(minutes: 5);
  static const int profitCacheMaxSize = 50;
  static const Duration profitCacheTtl = Duration(minutes: 30);
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

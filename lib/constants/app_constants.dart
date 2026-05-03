/// 应用全局常量定义
class AppConstants {
  AppConstants._();

  // --- SharedPreferences Keys ---
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

  // --- API URLs & Sources ---
  // NAS后端地址（通过Cloudflare Tunnel）
  static const String nasBackendUrl = 'https://fundlink.cr315.com';
  
  // User-Agent 配置
  static const String userAgentApp = 'FundLink-App/1.2.0';
  static const String userAgentVersionChecker = 'FundLink-Version-Checker';
  
  // 版本更新检查 - GitHub Release API（备用）
  static const String githubRepoOwner = 'rizona27';
  static const String githubRepoName = 'fundlink';
  static const String githubReleaseApiUrl = 'https://api.github.com/repos/$githubRepoOwner/$githubRepoName/releases/latest';
  static const String githubReleasePageUrl = 'https://github.com/$githubRepoOwner/$githubRepoName/releases';
  static const String githubProjectUrl = 'https://github.com/$githubRepoOwner/$githubRepoName';  // 项目主页（备用）
  
  static const String apiEastmoneyPingzhongdata = 'https://fund.eastmoney.com/pingzhongdata/{code}.js';
  static const String apiEastmoneyFundArchives = 'https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code={code}&topline=10';
  static const String apiGtimgStockQuote = 'https://qt.gtimg.cn/q={codes}';
  
  // 估值接口冗余配置 (主源 -> 备用源)
  static const List<String> apiValuationSources = [
    'https://fundgz.1234567.com.cn/js/{code}.js?rt={timestamp}', // 天天基金 (主)
    // 未来可在此处添加备用接口，如: 'https://api.example.com/fund/{code}'
  ];

  // --- Cache Configuration ---
  static const int valuationCacheValidSeconds = 180;
  static const int fundInfoCacheValidDays = 7;
  static const int maxCacheSize = 500;
  static const int maxLogEntries = 200;

  // --- UI & Animation Constants ---
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);
  static const Duration fastAnimationDuration = Duration(milliseconds: 200);
  static const Duration slowAnimationDuration = Duration(milliseconds: 400);
  static const Duration searchDebounceDuration = Duration(milliseconds: 400);
  
  static const double scrollThrottleMs = 16.0; // ~60fps
  static const double maxSwipeOffset = 70.0;

  // --- Business Logic Constants ---
  static const int tradingDayCheckBatchSize = 5;
  static const int refreshBatchSize = 5;
  static const double tradeTimeThreshold = 15.0; // 15:00

  // --- Input Validation Constants ---
  /// 输入验证相关常量
  /// 用于 lib/utils/input_formatters.dart 中的各种输入格式化器
  static const int maxDecimalPlaces = 4; // 小数点后最多位数（金额、份额、净值等）
  static const int maxIntegerDigits = 10; // 整数部分最多位数
  static const String numberPattern = r'^[0-9]*\.?[0-9]*$'; // 数字格式正则表达式
}

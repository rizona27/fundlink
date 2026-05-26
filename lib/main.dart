import 'dart:io' as io;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'constants/app_constants.dart';
import 'services/data_manager.dart';
import 'services/version_check_service.dart';
import 'utils/animation_config.dart';
import 'utils/error_handler.dart';
import 'utils/memory_monitor.dart';
import 'views/client_view.dart';
import 'views/config_view.dart';
import 'views/import_holding_view.dart';
import 'views/splash_view.dart';
import 'views/summary_view.dart';
import 'views/top_performers_view.dart';
import 'widgets/floating_tab_bar.dart';
import 'widgets/theme_switch.dart' as theme;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppConstants.init();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  if (!kReleaseMode) {
    final monitor = MemoryMonitor();
    monitor.warningThresholdMB = AppConstants.memoryWarningThresholdMB;
    monitor.criticalThresholdMB = AppConstants.memoryCriticalThresholdMB;

    monitor.onWarning = (snapshot) {};

    monitor.onCritical = (snapshot) {};

    monitor.startMonitoring(interval: AppConstants.memoryMonitorInterval);
  }

  _initShareReceiving();

  final permissionsOk = await _requestPermissionsOnStart();

  if (permissionsOk) {
    runApp(const MyApp());
  } else {
    runApp(const _PermissionDeniedApp());
  }
}

void _initShareReceiving() {
  if (kIsWeb) return;

  // Handle shares that launched the app (cold start)
  ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
    _handleSharedFiles(files);
    ReceiveSharingIntent.instance.reset();
  });

  // Handle shares received while app is running
  ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> files) {
    _handleSharedFiles(files);
  });
}

({Uint8List bytes, String fileName})? _pendingSharedFileData;

void _navigateToImportWithFile(Uint8List bytes, String fileName) {
  final navigator = MyApp.navigatorKey.currentState;
  if (navigator == null) {
    _pendingSharedFileData = (bytes: bytes, fileName: fileName);
    debugPrint('[ShareIntent] 导航器未就绪，暂存文件待处理: $fileName');
    return;
  }

  debugPrint('[ShareIntent] 正在导航到导入页面: $fileName');
  navigator.push(
    CupertinoPageRoute(
      builder: (context) => ImportHoldingView(
        initialFile: (bytes: bytes, fileName: fileName),
      ),
    ),
  );
}

void _processPendingSharedFile() {
  final data = _pendingSharedFileData;
  if (data == null) return;
  _pendingSharedFileData = null;
  _navigateToImportWithFile(data.bytes, data.fileName);
}

void _handleSharedFiles(List<SharedMediaFile> files) {
  if (files.isEmpty) return;

  SharedMediaFile? targetFile;
  for (final file in files) {
    final filePath = (file.path).toLowerCase();
    if (filePath.endsWith('.csv') || filePath.endsWith('.xlsx') || filePath.endsWith('.xls')) {
      targetFile = file;
      break;
    }
  }
  if (targetFile == null) return;

  try {
    final path = targetFile.path;
    final ioFile = io.File(path);
    final bytes = ioFile.readAsBytesSync();
    final fileName = path.split('/').last;

    _navigateToImportWithFile(bytes, fileName);
  } catch (e) {
    debugPrint('[ShareIntent] 读取分享文件失败: $e');
  }
}

/// 请求运行时权限。网络权限在安装时自动授予，无需运行时弹窗。
/// 返回 true 表示全部授予，false 表示有权限被拒绝。
Future<bool> _requestPermissionsOnStart() async {
  if (kIsWeb) return true;

  try {
    if (io.Platform.isAndroid) {
      // 存储权限：API ≤32 弹窗，API ≥33 自动授予
      final storage = await Permission.storage.request();
      if (storage.isDenied || storage.isPermanentlyDenied) {
        debugPrint('[权限] 存储权限被拒绝');
        return false;
      }

      // 相册权限：API ≥33 弹窗（READ_MEDIA_IMAGES），API <33 自动授予
      final photos = await Permission.photos.request();
      if (photos.isDenied || photos.isPermanentlyDenied) {
        debugPrint('[权限] 相册权限被拒绝');
        return false;
      }
    } else if (io.Platform.isIOS) {
      // iOS: 存储由沙盒隐式授权（NSDocumentsFolderUsageDescription），无需弹窗。
      // iOS: 相册权限
      final photos = await Permission.photos.request();
      if (photos.isDenied || photos.isPermanentlyDenied) {
        debugPrint('[权限] 相册权限被拒绝');
        return false;
      }
    }

    return true;
  } catch (e) {
    ErrorHandler.handleError(e, context: '权限请求');
    return false;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late DataManager _dataManager;
  Brightness? _targetBrightness;

  @override
  void initState() {
    super.initState();
    _dataManager = DataManager();
    
    _targetBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    
    _dataManager.addListener(_onThemeChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _waitForNetworkPermissionAndCheck();
    });
  }
  
  Future<void> _waitForNetworkPermissionAndCheck() async {
    await Future.delayed(const Duration(seconds: 1));
    
    await _checkForUpdatesSilently();
    
    _dataManager.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  Future<void> _checkForUpdatesSilently() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      
      bool success = await _tryCheckVersion(currentVersion, '首次尝试');
      
      if (!success) {
        for (int i = 1; i <= AppConstants.versionCheckMaxRetries; i++) {
          await Future.delayed(Duration(seconds: AppConstants.versionCheckRetryDelaySeconds));
          
          success = await _tryCheckVersion(currentVersion, '快速重试 #$i');
          if (success) return;
        }
        
        await Future.delayed(AppConstants.versionCheckLongRetryDelay);
        
        if (mounted) {
          success = await _tryCheckVersion(currentVersion, '5分钟后重试');
          if (success) return;
          
          await Future.delayed(AppConstants.versionCheckFinalRetryDelay);
          
          if (mounted) {
            await _tryCheckVersion(currentVersion, '10分钟后最终尝试');
          }
        }
      }
    } catch (e) {
      ErrorHandler.handleError(e, context: '版本检查');
    }
  }
  
  Future<bool> _tryCheckVersion(String currentVersion, String attemptName) async {
    try {
      final versionInfo = await VersionCheckService.checkLatestVersion(currentVersion);
      
      if (versionInfo != null && mounted) {
        _dataManager.setLatestVersionInfo(versionInfo);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  void _onThemeChanged() {
    if (mounted) {
      final newBrightness = _getBrightness();
      if (newBrightness != _targetBrightness) {
        _targetBrightness = newBrightness;
        setState(() {});
      }
    }
  }

  Brightness _getBrightness() {
    final themeMode = _dataManager.themeMode;
    if (themeMode == theme.ThemeMode.light) {
      return Brightness.light;
    } else if (themeMode == theme.ThemeMode.dark) {
      return Brightness.dark;
    } else {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  @override
  void dispose() {
    _dataManager.removeListener(_onThemeChanged);
    _dataManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _getBrightness();
    final currentBrightness = _targetBrightness ?? brightness;
    final currentIsDarkMode = currentBrightness == Brightness.dark;
    
    return DataManagerProvider(
      dataManager: _dataManager,
      child: CupertinoApp(
        navigatorKey: MyApp.navigatorKey,
        title: '基金持仓管理',
        navigatorObservers: [MyApp.routeObserver],
        theme: CupertinoThemeData(
          brightness: currentIsDarkMode ? Brightness.dark : Brightness.light,
          primaryColor: const Color(0xFF007AFF),
          primaryContrastingColor: CupertinoColors.white,
          scaffoldBackgroundColor: currentIsDarkMode 
              ? const Color(0xFF1C1C1E) 
              : const Color(0xFFF2F2F7),
          textTheme: CupertinoTextThemeData(
            navTitleTextStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: currentIsDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E),
            ),
            textStyle: TextStyle(
              fontSize: 17,
              color: currentIsDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E),
            ),
          ),
        ),
        home: const SplashView(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// 权限被拒绝时显示的占位 App，弹出提示后退出。
class _PermissionDeniedApp extends StatelessWidget {
  const _PermissionDeniedApp();

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: _PermissionDeniedPage(),
    );
  }
}

class _PermissionDeniedPage extends StatefulWidget {
  @override
  State<_PermissionDeniedPage> createState() => _PermissionDeniedPageState();
}

class _PermissionDeniedPageState extends State<_PermissionDeniedPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
  }

  void _showDialog() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('需要权限'),
        content: const Text(
          '本应用需要网络、存储和相册权限才能正常运行。\n'
          '请在系统设置中授予所需权限后重新打开应用。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => io.exit(0),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      backgroundColor: Color(0xFFF2F2F7),
      child: SizedBox.shrink(),
    );
  }
}

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _selectedIndex = 0;
  final GlobalKey<FloatingTabBarState> _tabBarKey = GlobalKey<FloatingTabBarState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processPendingSharedFile();
    });
  }

  final List<String> _pageIds = [
    'summary_view',
    'client_view', 
    'top_performers_view',
    '',
  ];

  final List<Widget> _pages = const [
    SummaryView(),
    ClientView(),
    TopPerformersView(),
    ConfigView(),
  ];

  final List<BottomNavigationBarItem> _tabItems = const [
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar_fill), label: '基金'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.person_2_fill), label: '持仓'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.star_fill), label: '排名'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.ellipsis_circle), label: '更多'),
  ];

  final List<Color> _activeColors = [
    const Color(0xFF667EEA),
    const Color(0xFFF093FB),
    const Color(0xFF4FACFE),
    const Color(0xFF43E97B),
  ];
  final List<Color> _activeColorsEnd = [
    const Color(0xFF764BA2),
    const Color(0xFFF5576C),
    const Color(0xFF00F2FE),
    const Color(0xFF38F9D7),
  ];

  void _onTabTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _tabBarKey.currentState?.restore();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: AnimationConfig.durationMedium,
          switchInCurve: AnimationConfig.curveEaseInOutCubic,
          switchOutCurve: AnimationConfig.curveEaseInOutCubic,
          child: IndexedStack(
            index: _selectedIndex,
            children: _pages,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingTabBar(
              key: _tabBarKey,
              currentIndex: _selectedIndex,
              onTap: _onTabTap,
              items: _tabItems,
              activeColors: _activeColors,
              activeColorsEnd: _activeColorsEnd,
            ),
          ),
        ),
      ],
    );
  }
}

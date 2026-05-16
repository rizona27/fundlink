import 'package:flutter/cupertino.dart';
import 'utils/animation_config.dart';
import 'package:flutter/material.dart' show Colors, RouteObserver, PageRoute;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'services/data_manager.dart';
import 'services/version_check_service.dart';
import 'utils/memory_monitor.dart';
import 'views/client_view.dart';
import 'views/summary_view.dart';
import 'views/top_performers_view.dart';
import 'views/config_view.dart';
import 'widgets/floating_tab_bar.dart';
import 'widgets/theme_switch.dart' as theme;
import 'views/splash_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  if (!kReleaseMode) {
    final monitor = MemoryMonitor();
    monitor.warningThresholdMB = 200;
    monitor.criticalThresholdMB = 400;
    
    monitor.onWarning = (snapshot) {
    };
    
    monitor.onCritical = (snapshot) {
    };
    
    monitor.startMonitoring(interval: const Duration(seconds: 10));
  }

  _requestPermissionsOnStart();

  runApp(const MyApp());
}

Future<void> _requestPermissionsOnStart() async {
  if (kIsWeb) {
    return;
  }

  try {
    PermissionStatus status;

    if (await Permission.storage.isDenied) {
      status = await Permission.storage.request();
    } else {
      status = await Permission.photos.request();
    }

    if (status.isGranted) {
    } else if (status.isPermanentlyDenied) {
    } else {
    }
  } catch (e) {
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

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
        for (int i = 1; i <= 3; i++) {
          await Future.delayed(const Duration(seconds: 3));
          
          success = await _tryCheckVersion(currentVersion, '快速重试 #$i');
          if (success) return;
        }
        
        await Future.delayed(const Duration(minutes: 5));
        
        if (mounted) {
          success = await _tryCheckVersion(currentVersion, '5分钟后重试');
          if (success) return;
          
          await Future.delayed(const Duration(minutes: 10));
          
          if (mounted) {
            await _tryCheckVersion(currentVersion, '10分钟后最终尝试');
          }
        }
      }
    } catch (e) {
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

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _selectedIndex = 0;
  final GlobalKey<FloatingTabBarState> _tabBarKey = GlobalKey<FloatingTabBarState>();

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
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar_fill), label: '一览'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.person_2_fill), label: '客户'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.star_fill), label: '排名'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.settings), label: '设置'),
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

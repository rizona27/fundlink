import 'package:flutter/cupertino.dart';
import 'utils/animation_config.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'services/data_manager.dart';
import 'services/version_check_service.dart';
import 'views/client_view.dart';
import 'views/summary_view.dart';
import 'views/top_performers_view.dart';
import 'views/config_view.dart';
import 'widgets/floating_tab_bar.dart';
import 'widgets/theme_switch.dart' as theme;
import 'widgets/update_dialog.dart';
import 'views/splash_view.dart';
import 'constants/app_constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

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
      debugPrint('Storage permission granted');
    } else if (status.isPermanentlyDenied) {
      debugPrint('Storage permission permanently denied');
    } else {
      debugPrint('Storage permission denied');
    }
  } catch (e) {
    debugPrint('Permission request error: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late DataManager _dataManager;
  Brightness _currentBrightness = Brightness.light;

  @override
  void initState() {
    super.initState();
    _dataManager = DataManager();
    _currentBrightness = _getBrightness();
    _dataManager.addListener(_onThemeChanged);
    
    // 等待网络权限授权后再检查版本
    _waitForNetworkPermissionAndCheck();
    
    // 启动时立即检查主题模式，确保在程序打开时就应用正确的主题
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final newBrightness = _getBrightness();
        if (newBrightness != _currentBrightness) {
          setState(() {
            _currentBrightness = newBrightness;
          });
        }
      }
    });
  }
  
  /// 等待网络就绪后检查版本更新
  Future<void> _waitForNetworkPermissionAndCheck() async {
    // 网络访问不需要特殊权限，直接等待2秒确保网络初始化完成
    debugPrint('等待网络初始化...');
    await Future.delayed(const Duration(seconds: 2));
    
    debugPrint('开始检查版本...');
    await _checkForUpdatesSilently();
    
    // 监听DataManager变化，当版本信息更新时立即通知UI刷新
    _dataManager.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  /// 静默检查版本更新（带多阶段重试机制）
  Future<void> _checkForUpdatesSilently() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      
      debugPrint('当前版本: $currentVersion');
      
      // 首次尝试 + 3次快速重试（间隔5秒）
      bool success = await _tryCheckVersion(currentVersion, '首次尝试');
      
      if (!success) {
        // 3次快速重试，间隔5秒
        for (int i = 1; i <= 3; i++) {
          debugPrint('快速重试 #$i/3，等待5秒...');
          await Future.delayed(const Duration(seconds: 5));
          
          success = await _tryCheckVersion(currentVersion, '快速重试 #$i');
          if (success) return;
        }
        
        // 5分钟后重试
        debugPrint('快速重试全部失败，5分钟后再次尝试...');
        await Future.delayed(const Duration(minutes: 5));
        
        if (mounted) {
          success = await _tryCheckVersion(currentVersion, '5分钟后重试');
          if (success) return;
          
          // 10分钟后最终尝试
          debugPrint('5分钟后重试失败，10分钟后最终尝试...');
          await Future.delayed(const Duration(minutes: 10));
          
          if (mounted) {
            await _tryCheckVersion(currentVersion, '10分钟后最终尝试');
          }
        }
      }
    } catch (e) {
      debugPrint('版本检查异常: $e');
    }
  }
  
  /// 单次尝试检查版本，返回是否成功
  Future<bool> _tryCheckVersion(String currentVersion, String attemptName) async {
    try {
      debugPrint('$attemptName - 开始检查版本...');
      
      final versionInfo = await VersionCheckService.checkLatestVersion(currentVersion);
      
      if (versionInfo != null && mounted) {
        _dataManager.setLatestVersionInfo(versionInfo);
        debugPrint('$attemptName - 成功！最新版本: ${versionInfo.version}, 需要更新: ${versionInfo.hasUpdate}');
        return true;
      } else {
        debugPrint('$attemptName - 失败，未获取到版本信息');
        return false;
      }
    } catch (e) {
      debugPrint('$attemptName - 异常: $e');
      return false;
    }
  }

  void _onThemeChanged() {
    final newBrightness = _getBrightness();
    if (newBrightness != _currentBrightness) {
      setState(() {
        _currentBrightness = newBrightness;
      });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = _currentBrightness == Brightness.dark;
    final backgroundColor = isDarkMode
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);

    return DataManagerProvider(
      dataManager: _dataManager,
      child: CupertinoApp(
        title: '基金持仓管理',
        theme: CupertinoThemeData(
          brightness: _currentBrightness,
          primaryColor: const Color(0xFF007AFF),
          primaryContrastingColor: CupertinoColors.white,
          scaffoldBackgroundColor: backgroundColor,
          textTheme: CupertinoTextThemeData(
            navTitleTextStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E),
            ),
            textStyle: TextStyle(
              fontSize: 17,
              color: isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E),
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
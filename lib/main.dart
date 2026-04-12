import 'package:flutter/cupertino.dart';
import 'providers/data_manager_provider.dart';
import 'services/data_manager.dart';
import 'views/client_view.dart';
import 'views/summary_view.dart';
import 'views/top_performers_view.dart';
import 'views/config_view.dart';
import 'widgets/floating_tab_bar.dart';
import 'widgets/theme_switch.dart' as theme;

void main() {
  debugPrint('==================== 应用启动 ====================');
  runApp(const MyApp());
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
        home: const MainTabView(),
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

  final List<Widget> _pages = [
    const SummaryView(),
    const ClientView(),
    const TopPerformersView(),
    const ConfigView(),
  ];

  final List<BottomNavigationBarItem> _tabItems = const [
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar_fill), label: '一览'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.person_2_fill), label: '客户'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.star_fill), label: '排名'),
    BottomNavigationBarItem(icon: Icon(CupertinoIcons.settings), label: '设置'),
  ];

  // 自定义每个标签的渐变色（起始色、结束色）
  final List<Color> _activeColors = [
    const Color(0xFF667EEA), // 一览
    const Color(0xFFF093FB), // 客户
    const Color(0xFF4FACFE), // 排名
    const Color(0xFF43E97B), // 设置
  ];
  final List<Color> _activeColorsEnd = [
    const Color(0xFF764BA2),
    const Color(0xFFF5576C),
    const Color(0xFF00F2FE),
    const Color(0xFF38F9D7),
  ];

  void _handleScroll() {
    _tabBarKey.currentState?.onScroll();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              _handleScroll();
            }
            return false;
          },
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
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
                });
                _tabBarKey.currentState?.restore();
              },
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
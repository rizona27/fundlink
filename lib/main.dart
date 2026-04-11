import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'providers/data_manager_provider.dart';
import 'services/data_manager.dart';
import 'views/client_view.dart';
import 'views/summary_view.dart';
import 'views/top_performers_view.dart';
import 'views/config_view.dart';
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
    final barBackgroundColor = isDarkMode
        ? CupertinoColors.black.withOpacity(0.8)
        : CupertinoColors.systemBackground.withOpacity(0.92);
    final textColor = isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E);

    final themeData = CupertinoThemeData(
      brightness: _currentBrightness,
      primaryColor: const Color(0xFF007AFF),
      primaryContrastingColor: CupertinoColors.white,
      barBackgroundColor: barBackgroundColor,
      scaffoldBackgroundColor: backgroundColor,
      textTheme: CupertinoTextThemeData(
        navTitleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        textStyle: TextStyle(
          fontSize: 17,
          color: textColor,
        ),
      ),
    );

    return DataManagerProvider(
      dataManager: _dataManager,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        color: backgroundColor,
        child: CupertinoApp(
          title: '基金持仓管理',
          theme: themeData,
          home: MainTabView(dataManager: _dataManager),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}

class MainTabView extends StatefulWidget {
  final DataManager dataManager;

  const MainTabView({super.key, required this.dataManager});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    debugPrint('==================== MainTabView initState ====================');
    debugPrint('持仓数量: ${widget.dataManager.holdings.length}');

    _pages = [
      const ClientView(),
      const SummaryView(),
      const TopPerformersView(),
      const ConfigView(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        activeColor: const Color(0xFF007AFF),
        inactiveColor: const Color(0xFF8E8E93),
        backgroundColor: CupertinoColors.systemBackground,
        height: 50,
        iconSize: 22,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2_fill),
            label: '客户',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chart_bar_fill),
            label: '汇总',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.star_fill),
            label: '排行',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: '设置',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) => _pages[index],
        );
      },
    );
  }
}
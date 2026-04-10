import 'package:flutter/cupertino.dart';
import 'models/fund_holding.dart';
import 'views/client_view.dart';
import 'views/summary_view.dart';
import 'views/top_performers_view.dart';
import 'views/config_view.dart';

void main() {
  // 使用 print 确保日志输出
  print('==================== 应用启动 ====================');
  debugPrint('==================== 应用启动 ====================');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('==================== MyApp build ====================');
    return CupertinoApp(
      title: '基金持仓管理',
      theme: CupertinoThemeData(
        primaryColor: const Color(0xFF007AFF),
        primaryContrastingColor: CupertinoColors.white,
        barBackgroundColor: CupertinoColors.systemBackground.withOpacity(0.92),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        textTheme: const CupertinoTextThemeData(
          navTitleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1C1E),
          ),
          textStyle: TextStyle(
            fontSize: 17,
            color: Color(0xFF1C1C1E),
          ),
        ),
        brightness: Brightness.light,
      ),
      home: const MainTabView(),
      debugShowCheckedModeBanner: false,
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

  final List<FundHolding> _holdings = MockData.getHoldings();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    print('==================== MainTabView initState ====================');
    print('持仓数量: ${_holdings.length}');

    _pages = [
      ClientView(holdings: _holdings),
      SummaryView(holdings: _holdings),
      TopPerformersView(holdings: _holdings),
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
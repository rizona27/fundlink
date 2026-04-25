import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../models/net_worth_point.dart';
import '../services/fund_service.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

class HistoryDialog extends StatefulWidget {
  final String fundCode;

  const HistoryDialog({super.key, required this.fundCode});

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  late FundService _fundService;
  List<NetWorthPoint> _allPoints = [];
  List<NetWorthPoint> _displayList = [];
  bool _loading = true;
  String? _error;

  int _page = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fundService = FundService();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<NetWorthPoint> _calculateDailyChanges(List<NetWorthPoint> points) {
    final calculated = <NetWorthPoint>[];
    for (int i = 0; i < points.length; i++) {
      double? growth;
      if (i > 0) {
        final prevNav = points[i - 1].nav;
        final currentNav = points[i].nav;
        growth = prevNav > 0 ? ((currentNav - prevNav) / prevNav) * 100 : 0.0;
      }
      calculated.add(NetWorthPoint(
        date: points[i].date,
        nav: points[i].nav,
        growth: growth,
        series: 'fund',
      ));
    }
    return calculated;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final rawTrend = await _fundService.fetchNetWorthTrend(widget.fundCode);
      final pointsAsc = List<NetWorthPoint>.from(rawTrend)
        ..sort((a, b) => a.date.compareTo(b.date));
      final pointsWithGrowth = _calculateDailyChanges(pointsAsc);
      final pointsDesc = pointsWithGrowth.reversed.toList();
      _allPoints = pointsDesc;
      _hasMore = pointsDesc.length > _pageSize;
      _displayList = pointsDesc.take(_pageSize).toList();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await Future.delayed(const Duration(milliseconds: 300));
    final start = _page * _pageSize;
    final end = start + _pageSize;
    if (start >= _allPoints.length) {
      _hasMore = false;
    } else {
      final newItems = _allPoints.sublist(start, end.clamp(0, _allPoints.length));
      if (newItems.isNotEmpty) {
        final earliestDate = newItems.last.date;
        if (mounted) {
          context.showToast('已加载到 ${_formatDate(earliestDate)} 的数据');
        }
      }
      setState(() {
        _displayList.addAll(newItems);
        _page++;
        _hasMore = end < _allPoints.length;
      });
    }
    setState(() => _loadingMore = false);
  }

  Widget _buildErrorView(bool isDark) {
    final bool isNetworkError = _error!.contains('ClientException') || 
                                 _error!.contains('SocketException') ||
                                 _error!.contains('Failed host lookup');
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isNetworkError ? CupertinoIcons.wifi_slash : CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: isNetworkError 
                  ? CupertinoColors.systemOrange 
                  : CupertinoColors.systemRed,
            ),
            const SizedBox(height: 12),
            Text(
              isNetworkError ? '网络连接失败' : '加载失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isNetworkError 
                  ? '请检查网络连接后重试' 
                  : '数据加载出现错误',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark 
                    ? CupertinoColors.white.withOpacity(0.6)
                    : CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: isNetworkError ? '重新连接' : '重试',
              icon: CupertinoIcons.refresh,
              onPressed: _loadData,
              isPrimary: true,
              height: 40,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      // 点击弹窗外部关闭
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: GestureDetector(
          // 阻止事件冒泡，防止点击弹窗内容时关闭
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            constraints: BoxConstraints(
              maxWidth: 500,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: CupertinoPopupSurface(
              isSurfacePainted: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '历史净值',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? CupertinoColors.white : CupertinoColors.black,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? CupertinoColors.systemGrey.withOpacity(0.3)
                                  : CupertinoColors.systemGrey.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 16,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? CupertinoColors.white.withOpacity(0.1)
                              : CupertinoColors.black.withOpacity(0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            '日期',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '单位净值',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '日涨幅',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: _loading
                        ? const Center(child: CupertinoActivityIndicator())
                        : _error != null
                        ? _buildErrorView(isDark)
                        : _displayList.isEmpty
                        ? const Center(child: Text('暂无历史净值数据'))
                        : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _displayList.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _displayList.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        }
                        final point = _displayList[index];
                        final growth = point.growth ?? 0.0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDark
                                    ? CupertinoColors.white.withOpacity(0.05)
                                    : CupertinoColors.black.withOpacity(0.05),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  _formatDate(point.date),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  point.nav.toStringAsFixed(4),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  growth == 0
                                      ? '--'
                                      : '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(2)}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: growth > 0
                                        ? CupertinoColors.systemRed
                                        : (growth < 0
                                        ? CupertinoColors.systemGreen
                                        : null),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
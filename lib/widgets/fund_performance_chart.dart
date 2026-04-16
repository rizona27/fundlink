import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/net_worth_point.dart';

/// 业绩走势图表组件（基金净值、同类平均、沪深300）
class FundPerformanceChart extends StatefulWidget {
  final List<NetWorthPoint> fundPoints;      // 基金净值（全量，已排序）
  final List<NetWorthPoint> avgPoints;       // 同类平均（全量，已排序）
  final List<NetWorthPoint> hsPoints;        // 沪深300（全量，已排序）

  const FundPerformanceChart({
    super.key,
    required this.fundPoints,
    required this.avgPoints,
    required this.hsPoints,
  });

  @override
  State<FundPerformanceChart> createState() => _FundPerformanceChartState();
}

class _FundPerformanceChartState extends State<FundPerformanceChart> {
  String _selectedRange = '3m';
  final Map<String, String> _rangeLabels = {
    '1m': '近1月', '3m': '近3月', '6m': '近6月',
    '1y': '近1年', '3y': '近3年', 'all': '成立来',
  };
  bool _showAverage = true;
  bool _showHs300 = true;

  // 当前区间切片 + 归一化后的数据
  List<DateTime> _sliceDates = [];
  List<double> _sliceFundPcts = [];
  List<double> _sliceAvgPcts = [];
  List<double> _sliceHsPcts = [];

  @override
  void initState() {
    super.initState();
    _updateSliceAndNormalize();
  }

  @override
  void didUpdateWidget(FundPerformanceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fundPoints != widget.fundPoints ||
        oldWidget.avgPoints != widget.avgPoints ||
        oldWidget.hsPoints != widget.hsPoints) {
      _updateSliceAndNormalize();
    }
  }

  // ==================== 核心：基于日期的切片 + 归一化 ====================
  void _updateSliceAndNormalize() {
    if (widget.fundPoints.isEmpty) {
      _sliceDates = [];
      _sliceFundPcts = [];
      _sliceAvgPcts = [];
      _sliceHsPcts = [];
      return;
    }

    // 1. 根据当前区间确定起始日期（自然日）
    final now = DateTime.now();
    DateTime startDate;
    switch (_selectedRange) {
      case '1m': startDate = now.subtract(const Duration(days: 30)); break;
      case '3m': startDate = now.subtract(const Duration(days: 90)); break;
      case '6m': startDate = now.subtract(const Duration(days: 180)); break;
      case '1y': startDate = now.subtract(const Duration(days: 365)); break;
      case '3y': startDate = now.subtract(const Duration(days: 1095)); break;
      default: startDate = DateTime(1900); break;
    }

    // 2. 找到基金净值数据中第一个 >= startDate 的交易日（基准日）
    int fundStartIdx = 0;
    for (int i = 0; i < widget.fundPoints.length; i++) {
      if (widget.fundPoints[i].date.isAfter(startDate) ||
          widget.fundPoints[i].date.isAtSameMomentAs(startDate)) {
        fundStartIdx = i;
        break;
      }
    }
    final baseDate = widget.fundPoints[fundStartIdx].date;
    final fundSlice = widget.fundPoints.sublist(fundStartIdx);

    // 3. 辅助：在列表中查找 <= targetDate 的最近净值
    double getNavOnOrBefore(List<NetWorthPoint> points, DateTime target) {
      for (int i = points.length - 1; i >= 0; i--) {
        if (points[i].date.isBefore(target) ||
            points[i].date.isAtSameMomentAs(target)) {
          return points[i].nav;
        }
      }
      return points.isNotEmpty ? points.first.nav : 1.0;
    }

    // 4. 获取基准日对应的净值（各自独立）
    final double fundBase = fundSlice.first.nav;
    final double avgBase = widget.avgPoints.isNotEmpty
        ? getNavOnOrBefore(widget.avgPoints, baseDate)
        : 1.0;
    final double hsBase = widget.hsPoints.isNotEmpty
        ? getNavOnOrBefore(widget.hsPoints, baseDate)
        : 1.0;

    // 5. 构建归一化序列（以基金日期为轴）
    _sliceDates = [];
    _sliceFundPcts = [];
    _sliceAvgPcts = [];
    _sliceHsPcts = [];

    for (final point in fundSlice) {
      final date = point.date;
      _sliceDates.add(date);

      // 基金归一化
      final fundPct = ((point.nav - fundBase) / fundBase) * 100;
      _sliceFundPcts.add(fundPct);

      // 同类平均：取该日期或之前最近净值
      final avgNav = getNavOnOrBefore(widget.avgPoints, date);
      final avgPct = ((avgNav - avgBase) / avgBase) * 100;
      _sliceAvgPcts.add(avgPct);

      // 沪深300同理
      final hsNav = getNavOnOrBefore(widget.hsPoints, date);
      final hsPct = ((hsNav - hsBase) / hsBase) * 100;
      _sliceHsPcts.add(hsPct);
    }
  }

  double _calculateRangeReturn() {
    if (_sliceFundPcts.isEmpty) return 0.0;
    return _sliceFundPcts.last - _sliceFundPcts.first;
  }

  double _getNiceInterval(double minY, double maxY) {
    final range = maxY - minY;
    if (range <= 0) return 0.5;
    final rough = range / 5;
    const nice = [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0];
    for (final n in nice) {
      if (rough <= n) return n;
    }
    return (rough / 10).ceilToDouble() * 10;
  }

  void _onRangeChanged(String newRange) {
    setState(() {
      _selectedRange = newRange;
      _updateSliceAndNormalize();
      if (['1m', '3m', '6m'].contains(newRange)) {
        _showAverage = true;
        _showHs300 = true;
      } else {
        _showAverage = false;
        _showHs300 = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final rangeReturn = _calculateRangeReturn();
    final rangeName = _rangeLabels[_selectedRange] ?? '';
    final returnColor = rangeReturn > 0
        ? CupertinoColors.systemRed
        : (rangeReturn < 0 ? CupertinoColors.systemGreen : CupertinoColors.systemGrey);

    if (_sliceFundPcts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: Text('暂无数据')),
      );
    }

    // 构建 FlSpot
    final fundSpots = <FlSpot>[];
    final avgSpots = <FlSpot>[];
    final hsSpots = <FlSpot>[];
    for (int i = 0; i < _sliceFundPcts.length; i++) {
      fundSpots.add(FlSpot(i.toDouble(), _sliceFundPcts[i]));
      if (_showAverage && i < _sliceAvgPcts.length) {
        avgSpots.add(FlSpot(i.toDouble(), _sliceAvgPcts[i]));
      }
      if (_showHs300 && i < _sliceHsPcts.length) {
        hsSpots.add(FlSpot(i.toDouble(), _sliceHsPcts[i]));
      }
    }

    // 计算 Y 轴范围（带异常保护）
    double minY = _sliceFundPcts.reduce((a, b) => a < b ? a : b);
    double maxY = _sliceFundPcts.reduce((a, b) => a > b ? a : b);
    if (_showAverage && _sliceAvgPcts.isNotEmpty) {
      final avgMin = _sliceAvgPcts.reduce((a, b) => a < b ? a : b);
      final avgMax = _sliceAvgPcts.reduce((a, b) => a > b ? a : b);
      minY = minY < avgMin ? minY : avgMin;
      maxY = maxY > avgMax ? maxY : avgMax;
    }
    if (_showHs300 && _sliceHsPcts.isNotEmpty) {
      final hsMin = _sliceHsPcts.reduce((a, b) => a < b ? a : b);
      final hsMax = _sliceHsPcts.reduce((a, b) => a > b ? a : b);
      minY = minY < hsMin ? minY : hsMin;
      maxY = maxY > hsMax ? maxY : hsMax;
    }

    // 异常值截断
    const double maxAbs = 100.0;
    if (minY < -maxAbs) minY = -maxAbs;
    if (maxY > maxAbs) maxY = maxAbs;
    if (minY > maxY) { minY = -5; maxY = 5; }

    final padding = (maxY - minY) * 0.08;
    minY = minY - padding;
    maxY = maxY + padding;
    if (minY > 0) minY = 0;

    final interval = _getNiceInterval(minY, maxY);
    final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('业绩走势', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: returnColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '$rangeName涨跌幅 ${rangeReturn >= 0 ? '+' : ''}${rangeReturn.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: returnColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: ['1m', '3m', '6m'].map((key) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildGlassButton(
                  label: _rangeLabels[key]!,
                  isSelected: _selectedRange == key,
                  onTap: () => _onRangeChanged(key),
                  isDark: isDark,
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['1y', '3y', 'all'].map((key) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildGlassButton(
                  label: _rangeLabels[key]!,
                  isSelected: _selectedRange == key,
                  onTap: () => _onRangeChanged(key),
                  isDark: isDark,
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDark ? CupertinoColors.white.withOpacity(0.08) : CupertinoColors.systemGrey.withOpacity(0.15),
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: interval,
                      getTitlesWidget: (value, meta) {
                        String label = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
                        return Text('$label%', style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < _sliceDates.length) {
                          return Text(_formatDateShort(_sliceDates[idx]), style: const TextStyle(fontSize: 10));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: isDark ? CupertinoColors.white.withOpacity(0.2) : CupertinoColors.systemGrey.withOpacity(0.5)),
                ),
                minX: 0,
                maxX: (fundSpots.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: fundSpots,
                    isCurved: true,
                    color: CupertinoColors.systemRed,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: CupertinoColors.systemRed.withOpacity(0.05)),
                  ),
                  if (_showAverage && avgSpots.isNotEmpty)
                    LineChartBarData(
                      spots: avgSpots,
                      isCurved: true,
                      color: CupertinoColors.systemBlue,
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  if (_showHs300 && hsSpots.isNotEmpty)
                    LineChartBarData(
                      spots: hsSpots,
                      isCurved: true,
                      color: CupertinoColors.systemGrey,
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isShortRange)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegendItem('本基金', CupertinoColors.systemRed),
                _buildLegendItem('同类平均', CupertinoColors.systemBlue),
                _buildLegendItem('沪深300', CupertinoColors.systemGrey),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? CupertinoColors.activeBlue.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? CupertinoColors.activeBlue
                : (isDark ? CupertinoColors.white.withOpacity(0.3) : CupertinoColors.systemGrey.withOpacity(0.5)),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: isSelected ? CupertinoColors.activeBlue : (isDark ? CupertinoColors.white : CupertinoColors.black),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  String _formatDateShort(DateTime d) => '${d.month}/${d.day}';
}
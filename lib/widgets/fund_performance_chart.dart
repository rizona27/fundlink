import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/net_worth_point.dart';

/// 业绩走势图表组件（基金净值、同类平均、沪深300）
/// 同类平均和沪深300的原始数据为累计收益率（基期通常为1000），
/// 本组件会将其转换为以基准日净值为1的“伪净值”，再与基金净值一起归一化，
/// 保证三条曲线起点一致且量纲统一。
class FundPerformanceChart extends StatefulWidget {
  final List<NetWorthPoint> fundPoints;      // 基金净值（真实净值，已排序）
  final List<NetWorthPoint> avgPoints;       // 同类平均（累计收益率原始值，已排序）
  final List<NetWorthPoint> hsPoints;        // 沪深300（累计收益率原始值，已排序）

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
    '1m': '近1月',
    '3m': '近3月',
    '6m': '近6月',
    '1y': '近1年',
    '3y': '近3年',
    'all': '成立来',
  };
  bool _showAverage = true;
  bool _showHs300 = true;

  // 当前区间切片 + 归一化后的数据（归一化值：起点 = 1.0）
  List<DateTime> _sliceDates = [];
  List<double> _sliceFundValues = [];   // 基金归一化值
  List<double> _sliceAvgValues = [];    // 同类平均归一化值（已转换为伪净值）
  List<double> _sliceHsValues = [];     // 沪深300归一化值（已转换为伪净值）

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

  /// 将累计收益率原始值转换为“伪净值”：
  /// 伪净值 = 1 + (原始值 - 基准日原始值) / 100
  List<NetWorthPoint> _convertToPseudoNav(List<NetWorthPoint> rawPoints, double baseRaw) {
    return rawPoints.map((p) {
      final pseudoNav = 1.0 + (p.nav - baseRaw) / 100.0;
      return NetWorthPoint(date: p.date, nav: pseudoNav);
    }).toList();
  }

  /// 核心：根据选定区间，对三条曲线分别做“起点归一化”
  void _updateSliceAndNormalize() {
    if (widget.fundPoints.isEmpty) {
      print('[归一化日志] 基金净值数据为空，跳过归一化');
      _sliceDates = [];
      _sliceFundValues = [];
      _sliceAvgValues = [];
      _sliceHsValues = [];
      return;
    }

    // 1. 根据当前区间确定起始日期（自然日）
    final now = DateTime.now();
    DateTime startDate;
    switch (_selectedRange) {
      case '1m':
        startDate = now.subtract(const Duration(days: 30));
        break;
      case '3m':
        startDate = now.subtract(const Duration(days: 90));
        break;
      case '6m':
        startDate = now.subtract(const Duration(days: 180));
        break;
      case '1y':
        startDate = now.subtract(const Duration(days: 365));
        break;
      case '3y':
        startDate = now.subtract(const Duration(days: 1095));
        break;
      default:
        startDate = DateTime(1900);
        break;
    }
    print('[归一化日志] 当前区间: $_selectedRange, 起始日期(自然日): $startDate');

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
    print('[归一化日志] 基金基准日期: $baseDate, 基准净值: ${fundSlice.first.nav}');

    // 辅助：在列表中查找 <= targetDate 的最近净值
    double getNavOnOrBefore(List<NetWorthPoint> points, DateTime target) {
      for (int i = points.length - 1; i >= 0; i--) {
        if (points[i].date.isBefore(target) ||
            points[i].date.isAtSameMomentAs(target)) {
          return points[i].nav;
        }
      }
      return points.isNotEmpty ? points.first.nav : 1.0;
    }

    // 3. 获取同类平均和沪深300在基准日的累计收益率原始值
    final double avgBaseRaw = widget.avgPoints.isNotEmpty
        ? getNavOnOrBefore(widget.avgPoints, baseDate)
        : 1000.0;
    final double hsBaseRaw = widget.hsPoints.isNotEmpty
        ? getNavOnOrBefore(widget.hsPoints, baseDate)
        : 1000.0;
    print('[归一化日志] 同类平均基准日原始累计收益率: $avgBaseRaw');
    print('[归一化日志] 沪深300基准日原始累计收益率: $hsBaseRaw');

    // 4. 将同类平均和沪深300的原始累计收益率转换为“伪净值”
    final List<NetWorthPoint> convertedAvgPoints = widget.avgPoints.isNotEmpty
        ? _convertToPseudoNav(widget.avgPoints, avgBaseRaw)
        : [];
    final List<NetWorthPoint> convertedHsPoints = widget.hsPoints.isNotEmpty
        ? _convertToPseudoNav(widget.hsPoints, hsBaseRaw)
        : [];

    // 5. 构建归一化序列（以基金的日期为轴，对每条曲线各自归一化）
    _sliceDates = [];
    _sliceFundValues = [];
    _sliceAvgValues = [];
    _sliceHsValues = [];

    for (final point in fundSlice) {
      final date = point.date;
      _sliceDates.add(date);

      // 基金归一化：当前净值 / 基准净值
      final fundValue = point.nav / fundSlice.first.nav;
      _sliceFundValues.add(fundValue);

      // 同类平均：取该日期或之前最近的伪净值，归一化（基准伪净值 = 1.0）
      if (convertedAvgPoints.isNotEmpty) {
        final avgPseudoNav = getNavOnOrBefore(convertedAvgPoints, date);
        final avgValue = avgPseudoNav / 1.0;  // 基准值就是1.0
        _sliceAvgValues.add(avgValue);
      } else {
        _sliceAvgValues.add(1.0);
      }

      // 沪深300：同理
      if (convertedHsPoints.isNotEmpty) {
        final hsPseudoNav = getNavOnOrBefore(convertedHsPoints, date);
        final hsValue = hsPseudoNav / 1.0;
        _sliceHsValues.add(hsValue);
      } else {
        _sliceHsValues.add(1.0);
      }
    }

    // 输出归一化后的数据范围（用于调试）
    if (_sliceFundValues.isNotEmpty) {
      final fundMin = _sliceFundValues.reduce((a, b) => a < b ? a : b);
      final fundMax = _sliceFundValues.reduce((a, b) => a > b ? a : b);
      print('[归一化日志] 基金归一化值范围: [$fundMin, $fundMax]');
    }
    if (_sliceAvgValues.isNotEmpty) {
      final avgMin = _sliceAvgValues.reduce((a, b) => a < b ? a : b);
      final avgMax = _sliceAvgValues.reduce((a, b) => a > b ? a : b);
      print('[归一化日志] 同类平均归一化值范围: [$avgMin, $avgMax]');
    }
    if (_sliceHsValues.isNotEmpty) {
      final hsMin = _sliceHsValues.reduce((a, b) => a < b ? a : b);
      final hsMax = _sliceHsValues.reduce((a, b) => a > b ? a : b);
      print('[归一化日志] 沪深300归一化值范围: [$hsMin, $hsMax]');
    }
  }

  /// 计算选定区间内基金的收益率（%）
  double _calculateRangeReturn() {
    if (_sliceFundValues.isEmpty) return 0.0;
    final startValue = _sliceFundValues.first;
    final endValue = _sliceFundValues.last;
    return (endValue - startValue) * 100;
  }

  /// 根据数据的动态范围计算合适的 Y 轴刻度间隔
  double _getNiceInterval(double minY, double maxY) {
    final range = maxY - minY;
    if (range <= 0) return 0.05;
    final rough = range / 5;
    const nice = [0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0];
    for (final n in nice) {
      if (rough <= n) return n;
    }
    return (rough / 10).ceilToDouble() * 10;
  }

  void _onRangeChanged(String newRange) {
    setState(() {
      _selectedRange = newRange;
      _updateSliceAndNormalize();
      // 长区间（1y/3y/all）默认隐藏同类平均和沪深300（避免数据稀疏）
      if (['1y', '3y', 'all'].contains(newRange)) {
        _showAverage = false;
        _showHs300 = false;
      } else {
        _showAverage = true;
        _showHs300 = true;
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

    if (_sliceFundValues.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: Text('暂无数据')),
      );
    }

    // 构建 FlSpot（横坐标使用索引）
    final fundSpots = <FlSpot>[];
    final avgSpots = <FlSpot>[];
    final hsSpots = <FlSpot>[];
    for (int i = 0; i < _sliceFundValues.length; i++) {
      fundSpots.add(FlSpot(i.toDouble(), _sliceFundValues[i]));
      if (_showAverage && i < _sliceAvgValues.length) {
        avgSpots.add(FlSpot(i.toDouble(), _sliceAvgValues[i]));
      }
      if (_showHs300 && i < _sliceHsValues.length) {
        hsSpots.add(FlSpot(i.toDouble(), _sliceHsValues[i]));
      }
    }

    // 计算 Y 轴范围（基于所有可见曲线）
    double minY = _sliceFundValues.reduce((a, b) => a < b ? a : b);
    double maxY = _sliceFundValues.reduce((a, b) => a > b ? a : b);
    if (_showAverage && _sliceAvgValues.isNotEmpty) {
      final avgMin = _sliceAvgValues.reduce((a, b) => a < b ? a : b);
      final avgMax = _sliceAvgValues.reduce((a, b) => a > b ? a : b);
      minY = minY < avgMin ? minY : avgMin;
      maxY = maxY > avgMax ? maxY : avgMax;
    }
    if (_showHs300 && _sliceHsValues.isNotEmpty) {
      final hsMin = _sliceHsValues.reduce((a, b) => a < b ? a : b);
      final hsMax = _sliceHsValues.reduce((a, b) => a > b ? a : b);
      minY = minY < hsMin ? minY : hsMin;
      maxY = maxY > hsMax ? maxY : hsMax;
    }

    // 添加内边距，避免曲线贴边
    final padding = (maxY - minY) * 0.1;
    minY = minY - padding;
    maxY = maxY + padding;
    if (minY > 0.95) minY = 0.95; // 保证基准线 1.0 可见
    if (maxY < 1.05) maxY = 1.05;

    final interval = _getNiceInterval(minY, maxY);
    final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 区间收益率
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '业绩走势',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: returnColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$rangeName涨跌幅 ${rangeReturn >= 0 ? '+' : ''}${rangeReturn.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: returnColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 区间选择按钮（两行）
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
          // 图表区域
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDark
                        ? CupertinoColors.white.withOpacity(0.08)
                        : CupertinoColors.systemGrey.withOpacity(0.15),
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      interval: interval,
                      getTitlesWidget: (value, meta) {
                        // 将归一化值转换为百分比： (value - 1) * 100
                        final percent = (value - 1.0) * 100;
                        String label = percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1);
                        if (percent > 0) label = '+$label%';
                        if (percent < 0) label = '$label%';
                        if (percent == 0) label = '0%';
                        return Text(
                          label,
                          style: const TextStyle(fontSize: 10),
                        );
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
                          return Text(
                            _formatDateShort(_sliceDates[idx]),
                            style: const TextStyle(fontSize: 10),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: isDark
                        ? CupertinoColors.white.withOpacity(0.2)
                        : CupertinoColors.systemGrey.withOpacity(0.5),
                  ),
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
                    belowBarData: BarAreaData(
                      show: true,
                      color: CupertinoColors.systemRed.withOpacity(0.05),
                    ),
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
          // 图例（仅短区间显示，长区间用户可选择显示但默认隐藏）
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
          color: isSelected
              ? CupertinoColors.activeBlue.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? CupertinoColors.activeBlue
                : (isDark
                ? CupertinoColors.white.withOpacity(0.3)
                : CupertinoColors.systemGrey.withOpacity(0.5)),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: isSelected
                ? CupertinoColors.activeBlue
                : (isDark ? CupertinoColors.white : CupertinoColors.black),
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
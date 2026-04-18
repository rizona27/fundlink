import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/net_worth_point.dart';

/// 业绩走势图表组件（基金净值、同类平均、沪深300）
class FundPerformanceChart extends StatefulWidget {
  final List<NetWorthPoint> fundPoints;
  final List<NetWorthPoint> avgPoints;
  final List<NetWorthPoint> hsPoints;

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

  List<DateTime> _sliceDates = [];
  List<double> _sliceFundValues = [];
  List<double> _sliceAvgValues = [];
  List<double> _sliceHsValues = [];

  int _hoverIndex = -1;
  double _crosshairX = 0;
  double _crosshairY = 0;
  double _chartWidth = 0;
  double _chartHeight = 0;
  double _currentMinY = 0;
  double _currentMaxY = 0;
  int _maxIndex = 0;
  DateTime _lastUpdateTime = DateTime.now();

  final GlobalKey _chartKey = GlobalKey();
  final GlobalKey _chartContainerKey = GlobalKey();

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

  List<NetWorthPoint> _convertToPseudoNav(List<NetWorthPoint> rawPoints, double baseRaw) {
    return rawPoints.map((p) {
      final pseudoNav = 1.0 + (p.nav - baseRaw) / 100.0;
      return NetWorthPoint(date: p.date, nav: pseudoNav);
    }).toList();
  }

  void _updateSliceAndNormalize() {
    if (widget.fundPoints.isEmpty) {
      _sliceDates = [];
      _sliceFundValues = [];
      _sliceAvgValues = [];
      _sliceHsValues = [];
      return;
    }

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

    double getNavOnOrBefore(List<NetWorthPoint> points, DateTime target) {
      for (int i = points.length - 1; i >= 0; i--) {
        if (points[i].date.isBefore(target) ||
            points[i].date.isAtSameMomentAs(target)) {
          return points[i].nav;
        }
      }
      return points.isNotEmpty ? points.first.nav : 1.0;
    }

    final double avgBaseRaw = widget.avgPoints.isNotEmpty
        ? getNavOnOrBefore(widget.avgPoints, baseDate)
        : 1000.0;
    final double hsBaseRaw = widget.hsPoints.isNotEmpty
        ? getNavOnOrBefore(widget.hsPoints, baseDate)
        : 1000.0;

    final List<NetWorthPoint> convertedAvgPoints = widget.avgPoints.isNotEmpty
        ? _convertToPseudoNav(widget.avgPoints, avgBaseRaw)
        : [];
    final List<NetWorthPoint> convertedHsPoints = widget.hsPoints.isNotEmpty
        ? _convertToPseudoNav(widget.hsPoints, hsBaseRaw)
        : [];

    _sliceDates = [];
    _sliceFundValues = [];
    _sliceAvgValues = [];
    _sliceHsValues = [];

    for (final point in fundSlice) {
      final date = point.date;
      _sliceDates.add(date);

      final fundValue = point.nav / fundSlice.first.nav;
      _sliceFundValues.add(fundValue);

      if (convertedAvgPoints.isNotEmpty) {
        final avgPseudoNav = getNavOnOrBefore(convertedAvgPoints, date);
        _sliceAvgValues.add(avgPseudoNav);
      } else {
        _sliceAvgValues.add(1.0);
      }

      if (convertedHsPoints.isNotEmpty) {
        final hsPseudoNav = getNavOnOrBefore(convertedHsPoints, date);
        _sliceHsValues.add(hsPseudoNav);
      } else {
        _sliceHsValues.add(1.0);
      }
    }
  }

  double _calculateRangeReturn() {
    if (_sliceFundValues.isEmpty) return 0.0;
    final startValue = _sliceFundValues.first;
    final endValue = _sliceFundValues.last;
    return (endValue - startValue) * 100;
  }

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
      _hoverIndex = -1;
      if (['1y', '3y', 'all'].contains(newRange)) {
        _showAverage = false;
        _showHs300 = false;
      } else {
        _showAverage = true;
        _showHs300 = true;
      }
    });
  }

  void _toggleAverage() {
    setState(() {
      _showAverage = !_showAverage;
    });
  }

  void _toggleHs300() {
    setState(() {
      _showHs300 = !_showHs300;
    });
  }

  String _getHoverDate() {
    if (_hoverIndex >= 0 && _hoverIndex < _sliceDates.length) {
      return _formatDate(_sliceDates[_hoverIndex]);
    }
    return '';
  }

  double _getHoverFundReturn() {
    if (_hoverIndex >= 0 && _hoverIndex < _sliceFundValues.length) {
      return (_sliceFundValues[_hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverAvgReturn() {
    if (_showAverage && _hoverIndex >= 0 && _hoverIndex < _sliceAvgValues.length) {
      return (_sliceAvgValues[_hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverHsReturn() {
    if (_showHs300 && _hoverIndex >= 0 && _hoverIndex < _sliceHsValues.length) {
      return (_sliceHsValues[_hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  String _formatDate(DateTime date) {
    if (_selectedRange == '1m') {
      return '${date.month}/${date.day}';
    }
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateShort(DateTime date) {
    if (_selectedRange == '1m') {
      return '${date.month}/${date.day}';
    } else if (_selectedRange == '3m' || _selectedRange == '6m') {
      return '${date.month}/${date.day}';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  int _getBottomTitleInterval() {
    final length = _sliceDates.length;
    if (length <= 6) return 1;
    return (length / 6).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final rangeReturn = _calculateRangeReturn();
    final Color fundLineColor = rangeReturn >= 0
        ? CupertinoColors.systemRed
        : CupertinoColors.systemGreen;
    final returnColor = rangeReturn > 0
        ? CupertinoColors.systemRed
        : (rangeReturn < 0 ? CupertinoColors.systemGreen : CupertinoColors.systemGrey);
    final rangeName = _rangeLabels[_selectedRange] ?? '';

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

    final transformedFundValues = _sliceFundValues.map((v) => v - 1.0).toList();
    final transformedAvgValues = _sliceAvgValues.map((v) => v - 1.0).toList();
    final transformedHsValues = _sliceHsValues.map((v) => v - 1.0).toList();

    final fundSpots = List.generate(transformedFundValues.length,
            (i) => FlSpot(i.toDouble(), transformedFundValues[i]));
    final avgSpots = List.generate(transformedAvgValues.length,
            (i) => FlSpot(i.toDouble(), transformedAvgValues[i]));
    final hsSpots = List.generate(transformedHsValues.length,
            (i) => FlSpot(i.toDouble(), transformedHsValues[i]));

    double minY = transformedFundValues.reduce((a, b) => a < b ? a : b);
    double maxY = transformedFundValues.reduce((a, b) => a > b ? a : b);
    if (_showAverage && transformedAvgValues.isNotEmpty) {
      final avgMin = transformedAvgValues.reduce((a, b) => a < b ? a : b);
      final avgMax = transformedAvgValues.reduce((a, b) => a > b ? a : b);
      minY = minY < avgMin ? minY : avgMin;
      maxY = maxY > avgMax ? maxY : avgMax;
    }
    if (_showHs300 && transformedHsValues.isNotEmpty) {
      final hsMin = transformedHsValues.reduce((a, b) => a < b ? a : b);
      final hsMax = transformedHsValues.reduce((a, b) => a > b ? a : b);
      minY = minY < hsMin ? minY : hsMin;
      maxY = maxY > hsMax ? maxY : hsMax;
    }

    final padding = (maxY - minY) * 0.1;
    minY = minY - padding;
    maxY = maxY + padding;
    if (minY > -0.05) minY = -0.05;
    if (maxY < 0.05) maxY = 0.05;

    _currentMinY = minY;
    _currentMaxY = maxY;
    _maxIndex = fundSpots.length - 1;

    final interval = _getNiceInterval(minY, maxY);
    final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);

    final screenWidth = MediaQuery.of(context).size.width;
    final maxXAxisTicks = screenWidth < 600 ? 4 : 6;
    final bottomInterval = (_maxIndex / maxXAxisTicks).ceilToDouble();

    final fillColor = rangeReturn >= 0
        ? CupertinoColors.systemRed.withOpacity(0.15)
        : CupertinoColors.systemGreen.withOpacity(0.15);

    final currentDate = _getHoverDate();
    final fundValue = _getHoverFundReturn();
    final avgValue = _getHoverAvgReturn();
    final hsValue = _getHoverHsReturn();

    final morandiColor = isDark ? const Color(0xFFB0B0B0) : const Color(0xFF8A8A8A);

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
          RepaintBoundary(
            key: _chartContainerKey,
            child: SizedBox(
              height: 240,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Container(
                      key: _chartKey,
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
                                  final percent = value * 100;
                                  String label = percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1);
                                  if (percent > 0) label = '+$label%';
                                  if (percent < 0) label = '$label%';
                                  if (percent == 0) label = '0%';
                                  return Text(
                                    label,
                                    style: TextStyle(fontSize: 10, color: morandiColor),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: bottomInterval,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx >= 0 && idx < _sliceDates.length) {
                                    return Transform.rotate(
                                      angle: -0.5,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          _formatDateShort(_sliceDates[idx]),
                                          style: TextStyle(fontSize: 10, color: morandiColor),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
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
                          maxX: _maxIndex.toDouble(),
                          minY: minY,
                          maxY: maxY,
                          lineTouchData: LineTouchData(
                            enabled: true,
                            handleBuiltInTouches: true,
                            touchSpotThreshold: 20,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipItems: (touchedSpots) {
                                return List<LineTooltipItem?>.filled(touchedSpots.length, null);
                              },
                            ),
                            getTouchedSpotIndicator: (barData, spotIndexes) {
                              return spotIndexes.map((index) {
                                return TouchedSpotIndicatorData(
                                  FlLine(color: Colors.transparent, strokeWidth: 0),
                                  FlDotData(
                                    show: barData.color == fundLineColor,
                                    getDotPainter: (spot, percent, barData, index) {
                                      return FlDotCirclePainter(
                                        radius: 3,
                                        color: barData.color!,
                                        strokeWidth: 2,
                                        strokeColor: isDark ? Colors.black : Colors.white,
                                      );
                                    },
                                  ),
                                );
                              }).toList();
                            },
                            touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
                              if (!event.isInterestedForInteractions ||
                                  response == null ||
                                  response.lineBarSpots == null ||
                                  response.lineBarSpots!.isEmpty) {
                                if (_hoverIndex != -1) {
                                  setState(() => _hoverIndex = -1);
                                }
                                return;
                              }

                              final spot = response.lineBarSpots!.firstWhere(
                                    (s) => s.bar.color == fundLineColor,
                                orElse: () => response.lineBarSpots!.first,
                              );
                              final newIndex = spot.x.toInt();
                              final now = DateTime.now();
                              if (newIndex != _hoverIndex && now.difference(_lastUpdateTime) > const Duration(milliseconds: 33)) {
                                _lastUpdateTime = now;
                                setState(() {
                                  _hoverIndex = newIndex;
                                  const leftMargin = 45.0;
                                  const bottomMargin = 30.0;
                                  final plotWidth = _chartWidth - leftMargin;
                                  final plotHeight = _chartHeight - bottomMargin;
                                  if (plotWidth > 0 && plotHeight > 0 && _maxIndex > 0) {
                                    _crosshairX = leftMargin + (newIndex / _maxIndex) * plotWidth;
                                    final yRange = _currentMaxY - _currentMinY;
                                    final normalized = yRange > 0 ? (spot.y - _currentMinY) / yRange : 0.5;
                                    _crosshairY = plotHeight * (1 - normalized);
                                  }
                                  final renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
                                  if (renderBox != null) {
                                    _chartWidth = renderBox.size.width;
                                    _chartHeight = renderBox.size.height;
                                    final newPlotWidth = _chartWidth - leftMargin;
                                    final newPlotHeight = _chartHeight - bottomMargin;
                                    if (newPlotWidth > 0 && newPlotHeight > 0 && _maxIndex > 0) {
                                      _crosshairX = leftMargin + (newIndex / _maxIndex) * newPlotWidth;
                                      final yRange2 = _currentMaxY - _currentMinY;
                                      final normalized2 = yRange2 > 0 ? (spot.y - _currentMinY) / yRange2 : 0.5;
                                      _crosshairY = newPlotHeight * (1 - normalized2);
                                    }
                                  }
                                });
                              }
                            },
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: fundSpots,
                              isCurved: true,
                              color: fundLineColor,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: fillColor,
                                cutOffY: 0,
                                applyCutOffY: true,
                              ),
                              aboveBarData: BarAreaData(
                                show: true,
                                color: fillColor,
                                cutOffY: 0,
                                applyCutOffY: true,
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
                                aboveBarData: BarAreaData(show: false),
                              ),
                            if (_showHs300 && hsSpots.isNotEmpty)
                              LineChartBarData(
                                spots: hsSpots,
                                isCurved: true,
                                color: CupertinoColors.systemGrey,
                                barWidth: 1.5,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                                aboveBarData: BarAreaData(show: false),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_hoverIndex >= 0 && _chartWidth > 0 && _chartHeight > 0)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CrosshairPainter(
                          crossX: _crosshairX,
                          crossY: _crosshairY,
                          color: morandiColor,
                        ),
                      ),
                    ),
                  if (_hoverIndex >= 0 && _crosshairX > 0 && _crosshairX < _chartWidth)
                    Positioned(
                      left: _crosshairX - 40,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: morandiColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                          ),
                          child: Text(
                            _getHoverDate(),
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  if (_hoverIndex >= 0 && _crosshairY > 0 && _crosshairY < _chartHeight)
                    Positioned(
                      left: 0,
                      top: _crosshairY - 12,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: morandiColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${fundValue >= 0 ? '+' : ''}${fundValue.toStringAsFixed(2)}%',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
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
                _buildLegendItemWithValue('本基金', fundLineColor, fundValue, isDark, null),
                _buildLegendItemWithValue('同类平均', CupertinoColors.systemBlue, avgValue, isDark, _toggleAverage),
                _buildLegendItemWithValue('沪深300', CupertinoColors.systemGrey, hsValue, isDark, _toggleHs300),
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

  Widget _buildLegendItemWithValue(String label, Color color, double value, bool isDark, VoidCallback? onToggle) {
    final valueStr = value != 0 ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%' : '--';
    final valueColor = value >= 0 ? CupertinoColors.systemRed : CupertinoColors.systemGreen;
    return GestureDetector(
      onTap: onToggle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87)),
              if (onToggle != null) ...[
                const SizedBox(width: 4),
                Icon(
                  (onToggle == _toggleAverage ? _showAverage : _showHs300)
                      ? CupertinoIcons.eye
                      : CupertinoIcons.eye_slash,
                  size: 14,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            valueStr,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final double crossX;
  final double crossY;
  final Color color;

  _CrosshairPainter({
    required this.crossX,
    required this.crossY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    if (crossX >= 0 && crossX <= size.width) {
      _drawDashedLine(canvas, Offset(crossX, 0), Offset(crossX, size.height), paint);
    }
    if (crossY >= 0 && crossY <= size.height) {
      _drawDashedLine(canvas, Offset(0, crossY), Offset(size.width, crossY), paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 4.0;
    final distance = (p2 - p1).distance;
    final steps = (distance / (dashLength + gapLength)).ceil();
    if (steps == 0) return;
    final dx = (p2.dx - p1.dx) / steps;
    final dy = (p2.dy - p1.dy) / steps;
    for (int i = 0; i < steps; i++) {
      final start = Offset(p1.dx + i * dx, p1.dy + i * dy);
      final end = Offset(
        start.dx + dx * (dashLength / (dashLength + gapLength)),
        start.dy + dy * (dashLength / (dashLength + gapLength)),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) {
    return oldDelegate.crossX != crossX || oldDelegate.crossY != crossY;
  }
}
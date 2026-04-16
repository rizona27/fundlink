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

  // 悬停相关状态
  int _hoverIndex = -1;
  double _tooltipX = 0;
  double _tooltipY = 0;

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
        final avgValue = avgPseudoNav / 1.0;
        _sliceAvgValues.add(avgValue);
      } else {
        _sliceAvgValues.add(1.0);
      }

      if (convertedHsPoints.isNotEmpty) {
        final hsPseudoNav = getNavOnOrBefore(convertedHsPoints, date);
        final hsValue = hsPseudoNav / 1.0;
        _sliceHsValues.add(hsValue);
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
    if (_hoverIndex >= 0 && _hoverIndex < _sliceAvgValues.length) {
      return (_sliceAvgValues[_hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverHsReturn() {
    if (_hoverIndex >= 0 && _hoverIndex < _sliceHsValues.length) {
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

    final fundSpots = <FlSpot>[];
    final avgSpots = <FlSpot>[];
    final hsSpots = <FlSpot>[];
    for (int i = 0; i < _sliceFundValues.length; i++) {
      fundSpots.add(FlSpot(i.toDouble(), _sliceFundValues[i]));
      if (i < _sliceAvgValues.length) {
        avgSpots.add(FlSpot(i.toDouble(), _sliceAvgValues[i]));
      }
      if (i < _sliceHsValues.length) {
        hsSpots.add(FlSpot(i.toDouble(), _sliceHsValues[i]));
      }
    }

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

    final padding = (maxY - minY) * 0.1;
    minY = minY - padding;
    maxY = maxY + padding;
    if (minY > 0.95) minY = 0.95;
    if (maxY < 1.05) maxY = 1.05;

    final interval = _getNiceInterval(minY, maxY);
    final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);
    final bottomInterval = _getBottomTitleInterval();

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
          SizedBox(
            height: 240,
            child: Stack(
              children: [
                LineChart(
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
                          interval: bottomInterval.toDouble(),
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx >= 0 && idx < _sliceDates.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _formatDateShort(_sliceDates[idx]),
                                  style: const TextStyle(fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
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
                    maxX: (fundSpots.length - 1).toDouble(),
                    minY: minY,
                    maxY: maxY,
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return [];
                        },
                      ),
                      getTouchedSpotIndicator: (barData, spotIndexes) {
                        // 只为本基金曲线（红色）显示小圆点
                        if (barData.color == CupertinoColors.systemRed && spotIndexes.isNotEmpty) {
                          return spotIndexes.map((index) {
                            return TouchedSpotIndicatorData(
                              FlLine(color: Colors.transparent, strokeWidth: 0),
                              FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, barData, index) {
                                  return FlDotCirclePainter(
                                    radius: 2.5,
                                    color: barData.color!,
                                    strokeWidth: 1,
                                    strokeColor: isDark ? Colors.black : Colors.white,
                                  );
                                },
                              ),
                            );
                          }).toList();
                        }
                        return [];
                      },
                      touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
                        if (event is FlPanEndEvent) {
                          setState(() {
                            _hoverIndex = -1;
                          });
                        } else if (response != null &&
                            response.lineBarSpots != null &&
                            response.lineBarSpots!.isNotEmpty) {
                          setState(() {
                            _hoverIndex = response.lineBarSpots!.first.x.toInt();
                            if (event is FlPanUpdateEvent) {
                              _tooltipX = event.localPosition.dx + 15;
                              _tooltipY = event.localPosition.dy - 70;
                            }
                          });
                        }
                      },
                    ),
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
                // 自定义悬浮框
                if (_hoverIndex >= 0 && _hoverIndex < _sliceFundValues.length)
                  Positioned(
                    left: _tooltipX.clamp(10, MediaQuery.of(context).size.width - 170),
                    top: _tooltipY.clamp(10, 170),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      color: isDark ? Colors.grey[850] : Colors.white,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _getHoverDate(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.grey[400] : Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  color: CupertinoColors.systemRed,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '本基金',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${_getHoverFundReturn() >= 0 ? '+' : ''}${_getHoverFundReturn().toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _getHoverFundReturn() >= 0
                                        ? CupertinoColors.systemRed
                                        : CupertinoColors.systemGreen,
                                  ),
                                ),
                              ],
                            ),
                            if (_showAverage && _hoverIndex < _sliceAvgValues.length) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    color: CupertinoColors.systemBlue,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '同类平均',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${_getHoverAvgReturn() >= 0 ? '+' : ''}${_getHoverAvgReturn().toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _getHoverAvgReturn() >= 0
                                          ? CupertinoColors.systemRed
                                          : CupertinoColors.systemGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (_showHs300 && _hoverIndex < _sliceHsValues.length) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    color: CupertinoColors.systemGrey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '沪深300',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${_getHoverHsReturn() >= 0 ? '+' : ''}${_getHoverHsReturn().toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _getHoverHsReturn() >= 0
                                          ? CupertinoColors.systemRed
                                          : CupertinoColors.systemGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (isShortRange)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegendItem('本基金', CupertinoColors.systemRed, isDark, null),
                _buildLegendItem('同类平均', CupertinoColors.systemBlue, isDark, _toggleAverage),
                _buildLegendItem('沪深300', CupertinoColors.systemGrey, isDark, _toggleHs300),
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

  Widget _buildLegendItem(String label, Color color, bool isDark, VoidCallback? onToggle) {
    return GestureDetector(
      onTap: onToggle,
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
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
    );
  }
}
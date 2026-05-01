import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class StockChartWidget extends StatefulWidget {
  final List<String> klineData; 
  final bool isDark;

  const StockChartWidget({
    super.key,
    required this.klineData,
    required this.isDark,
  });

  @override
  State<StockChartWidget> createState() => _StockChartWidgetState();
}

class _StockChartWidgetState extends State<StockChartWidget> {
  String _selectedPeriod = 'day'; 
  final Map<String, String> _periodLabels = {
    'day': '日K',
    'week': '周K',
    'month': '月K',
  };

  List<FlSpot> _spots = [];
  double _minY = 0;
  double _maxY = 0;
  List<String> _dates = [];

  @override
  void initState() {
    super.initState();
    _parseKlineData();
  }

  @override
  void didUpdateWidget(StockChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.klineData != widget.klineData) {
      _parseKlineData();
    }
  }

  void _parseKlineData() {
    if (widget.klineData.isEmpty) {
      _spots = [];
      _dates = [];
      return;
    }

    final spots = <FlSpot>[];
    final dates = <String>[];
    
    for (int i = 0; i < widget.klineData.length; i++) {
      final parts = widget.klineData[i].split(',');
      if (parts.length >= 6) {
        final date = parts[0];
        final close = double.tryParse(parts[2]) ?? 0;
        
        spots.add(FlSpot(i.toDouble(), close));
        dates.add(date);
      }
    }

    if (spots.isNotEmpty) {
      final values = spots.map((s) => s.y).toList();
      _minY = values.reduce((a, b) => a < b ? a : b);
      _maxY = values.reduce((a, b) => a > b ? a : b);
      
      final padding = (_maxY - _minY) * 0.1;
      _minY = _minY - padding;
      _maxY = _maxY + padding;
    }

    setState(() {
      _spots = spots;
      _dates = dates;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_spots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            '暂无K线数据',
            style: TextStyle(
              fontSize: 14,
              color: widget.isDark 
                  ? CupertinoColors.white.withOpacity(0.5)
                  : CupertinoColors.systemGrey,
            ),
          ),
        ),
      );
    }

    final lineColor = _spots.last.y >= _spots.first.y
        ? CupertinoColors.systemRed
        : CupertinoColors.systemGreen;
    
    final fillColor = _spots.last.y >= _spots.first.y
        ? CupertinoColors.systemRed.withOpacity(0.15)
        : CupertinoColors.systemGreen.withOpacity(0.15);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _periodLabels.keys.map((key) {
              final isSelected = _selectedPeriod == key;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPeriod = key;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (widget.isDark 
                              ? CupertinoColors.white.withOpacity(0.15)
                              : CupertinoColors.black.withOpacity(0.08))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _periodLabels[key]!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? (widget.isDark 
                                ? CupertinoColors.white
                                : CupertinoColors.black)
                            : (widget.isDark
                                ? CupertinoColors.white.withOpacity(0.6)
                                : CupertinoColors.systemGrey),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (_maxY - _minY) / 4,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: widget.isDark
                        ? CupertinoColors.white.withOpacity(0.05)
                        : CupertinoColors.systemGrey.withOpacity(0.1),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    interval: (_maxY - _minY) / 4,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.isDark
                              ? CupertinoColors.white.withOpacity(0.5)
                              : CupertinoColors.systemGrey,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: (_spots.length / 5).ceilToDouble(),
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < _dates.length) {
                        final date = _dates[index];
                        final displayDate = date.length >= 10 
                            ? '${date.substring(5, 7)}/${date.substring(8, 10)}'
                            : date;
                        return Text(
                          displayDate,
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.isDark
                                ? CupertinoColors.white.withOpacity(0.5)
                                : CupertinoColors.systemGrey,
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(
                    color: widget.isDark
                        ? CupertinoColors.white.withOpacity(0.1)
                        : CupertinoColors.systemGrey.withOpacity(0.2),
                  ),
                  left: BorderSide(
                    color: widget.isDark
                        ? CupertinoColors.white.withOpacity(0.1)
                        : CupertinoColors.systemGrey.withOpacity(0.2),
                  ),
                ),
              ),
              minX: 0,
              maxX: _spots.length.toDouble() - 1,
              minY: _minY,
              maxY: _maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: _spots,
                  isCurved: false,
                  color: lineColor,
                  barWidth: 1.5,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        fillColor,
                        fillColor.withOpacity(0.02),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 8,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final index = spot.x.toInt();
                      if (index >= 0 && index < _dates.length) {
                        return LineTooltipItem(
                          '${_dates[index]}\n${spot.y.toStringAsFixed(2)}',
                          TextStyle(
                            color: widget.isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        );
                      }
                      return null;
                    }).toList();
                  },
                ),
                handleBuiltInTouches: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

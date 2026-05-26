import 'dart:io' show File, Platform;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/net_worth_point.dart';
import 'glass_button.dart';

class FundPerformanceChart extends StatefulWidget {
  final List<NetWorthPoint> fundPoints;
  final List<NetWorthPoint> avgPoints;
  final List<NetWorthPoint> hsPoints;
  final List<NetWorthPoint>? zz500Points; 
  final List<NetWorthPoint>? zz1000Points; 
  final List<NetWorthPoint>? customFundPoints; 
  final VoidCallback? onCustomFundConfig; 
  final String? fundCode; 
  final String? customFundCode; 

  const FundPerformanceChart({
    super.key,
    required this.fundPoints,
    required this.avgPoints,
    required this.hsPoints,
    this.zz500Points,
    this.zz1000Points,
    this.customFundPoints,
    this.onCustomFundConfig,
    this.fundCode,
    this.customFundCode,
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
  bool _showAverage = false; 
  bool _showHs300 = false; 
  bool _showZZ500 = false; 
  bool _showZZ1000 = false; 
  bool _showCustomFund = false;
  bool _useCustomRange = false;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _exporting = false;

  List<DateTime> _sliceDates = [];
  List<double> _sliceFundValues = [];
  List<double> _sliceAvgValues = [];
  List<double> _sliceHsValues = [];
  List<double> _sliceZZ500Values = [];
  List<double> _sliceZZ1000Values = [];
  List<double> _sliceCustomFundValues = [];

  final ValueNotifier<int> _hoverIndexNotifier = ValueNotifier(-1);
  final ValueNotifier<double> _crosshairXNotifier = ValueNotifier(0);
  final ValueNotifier<double> _crosshairYNotifier = ValueNotifier(0);
  final ValueNotifier<Offset?> _dotPositionNotifier = ValueNotifier(null);

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
  void dispose() {
    _hoverIndexNotifier.dispose();
    _crosshairXNotifier.dispose();
    _crosshairYNotifier.dispose();
    _dotPositionNotifier.dispose();
    super.dispose();
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

  List<NetWorthPoint> _convertFundToPseudoNav(List<NetWorthPoint> rawPoints, double baseRaw) {
    return rawPoints.map((p) {
      final pseudoNav = baseRaw > 0 ? p.nav / baseRaw : 1.0;
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
    if (_useCustomRange && _customStartDate != null) {
      startDate = _customStartDate!;
    } else {
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
    var fundSlice = widget.fundPoints.sublist(fundStartIdx);

    if (_useCustomRange && _customEndDate != null) {
      int fundEndIdx = fundSlice.length;
      for (int i = 0; i < fundSlice.length; i++) {
        if (fundSlice[i].date.isAfter(_customEndDate!)) {
          fundEndIdx = i;
          break;
        }
      }
      fundSlice = fundSlice.sublist(0, fundEndIdx);
    }

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
        : 1.0;

    final List<NetWorthPoint> convertedAvgPoints = widget.avgPoints.isNotEmpty
        ? _convertToPseudoNav(widget.avgPoints, avgBaseRaw)
        : [];
    final List<NetWorthPoint> convertedHsPoints = widget.hsPoints.isNotEmpty
        ? _convertFundToPseudoNav(widget.hsPoints, hsBaseRaw)
        : [];

    final double zz500BaseRaw = widget.zz500Points != null && widget.zz500Points!.isNotEmpty
        ? getNavOnOrBefore(widget.zz500Points!, baseDate)
        : 1.0;
    final double zz1000BaseRaw = widget.zz1000Points != null && widget.zz1000Points!.isNotEmpty
        ? getNavOnOrBefore(widget.zz1000Points!, baseDate)
        : 1.0;
    final double customFundBaseRaw = widget.customFundPoints != null && widget.customFundPoints!.isNotEmpty
        ? getNavOnOrBefore(widget.customFundPoints!, baseDate)
        : 1.0;

    final List<NetWorthPoint> convertedZZ500Points = widget.zz500Points != null && widget.zz500Points!.isNotEmpty
        ? _convertFundToPseudoNav(widget.zz500Points!, zz500BaseRaw)
        : [];
    final List<NetWorthPoint> convertedZZ1000Points = widget.zz1000Points != null && widget.zz1000Points!.isNotEmpty
        ? _convertFundToPseudoNav(widget.zz1000Points!, zz1000BaseRaw)
        : [];
    final List<NetWorthPoint> convertedCustomFundPoints = widget.customFundPoints != null && widget.customFundPoints!.isNotEmpty
        ? _convertFundToPseudoNav(widget.customFundPoints!, customFundBaseRaw)
        : [];

    _sliceDates = [];
    _sliceFundValues = [];
    _sliceAvgValues = [];
    _sliceHsValues = [];
    _sliceZZ500Values = [];
    _sliceZZ1000Values = [];
    _sliceCustomFundValues = [];

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

      if (convertedZZ500Points.isNotEmpty) {
        final zz500PseudoNav = getNavOnOrBefore(convertedZZ500Points, date);
        _sliceZZ500Values.add(zz500PseudoNav);
      } else {
        _sliceZZ500Values.add(1.0);
      }

      if (convertedZZ1000Points.isNotEmpty) {
        final zz1000PseudoNav = getNavOnOrBefore(convertedZZ1000Points, date);
        _sliceZZ1000Values.add(zz1000PseudoNav);
      } else {
        _sliceZZ1000Values.add(1.0);
      }

      if (convertedCustomFundPoints.isNotEmpty) {
        final customPseudoNav = getNavOnOrBefore(convertedCustomFundPoints, date);
        _sliceCustomFundValues.add(customPseudoNav);
      } else {
        _sliceCustomFundValues.add(1.0);
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
      _useCustomRange = false;
      _customStartDate = null;
      _customEndDate = null;
      _updateSliceAndNormalize();
      _hoverIndexNotifier.value = -1;
      _dotPositionNotifier.value = null;
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

  void _toggleZZ500() {
    setState(() {
      _showZZ500 = !_showZZ500;
    });
  }

  void _toggleZZ1000() {
    setState(() {
      _showZZ1000 = !_showZZ1000;
    });
  }

  void _toggleCustomFund() {
    if (!_showCustomFund && (widget.customFundCode == null || widget.customFundCode!.isEmpty)) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) {
          return CupertinoAlertDialog(
            title: const Text('提示'),
            content: const Text('请先点击"自定义"文字配置基金代码'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
      return;
    }
    
    setState(() {
      _showCustomFund = !_showCustomFund;
    });
  }

  String _getHoverDate() {
    final hoverIndex = _hoverIndexNotifier.value;
    if (hoverIndex >= 0 && hoverIndex < _sliceDates.length) {
      return _formatDate(_sliceDates[hoverIndex]);
    }
    return '';
  }

  double _getHoverFundReturn() {
    final hoverIndex = _hoverIndexNotifier.value;
    if (hoverIndex >= 0 && hoverIndex < _sliceFundValues.length) {
      return (_sliceFundValues[hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverAvgReturn() {
    final hoverIndex = _hoverIndexNotifier.value;
    if (_showAverage && hoverIndex >= 0 && hoverIndex < _sliceAvgValues.length) {
      return (_sliceAvgValues[hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverHsReturn() {
    final hoverIndex = _hoverIndexNotifier.value;
    if (_showHs300 && hoverIndex >= 0 && hoverIndex < _sliceHsValues.length) {
      return (_sliceHsValues[hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverZZ500Return() {
    final hoverIndex = _hoverIndexNotifier.value;
    if (_showZZ500 && hoverIndex >= 0 && hoverIndex < _sliceZZ500Values.length) {
      return (_sliceZZ500Values[hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverZZ1000Return() {
    final hoverIndex = _hoverIndexNotifier.value;
    if (_showZZ1000 && hoverIndex >= 0 && hoverIndex < _sliceZZ1000Values.length) {
      return (_sliceZZ1000Values[hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getHoverCustomFundReturn() {
    final hoverIndex = _hoverIndexNotifier.value;
    if (_showCustomFund && hoverIndex >= 0 && hoverIndex < _sliceCustomFundValues.length) {
      return (_sliceCustomFundValues[hoverIndex] - 1) * 100;
    }
    return 0.0;
  }

  double _getPeriodEndFundReturn() => _sliceFundValues.isNotEmpty ? (_sliceFundValues.last - 1) * 100 : 0.0;
  double _getPeriodEndHsReturn() => _sliceHsValues.isNotEmpty ? (_sliceHsValues.last - 1) * 100 : 0.0;
  double _getPeriodEndZZ500Return() => _sliceZZ500Values.isNotEmpty ? (_sliceZZ500Values.last - 1) * 100 : 0.0;
  double _getPeriodEndZZ1000Return() => _sliceZZ1000Values.isNotEmpty ? (_sliceZZ1000Values.last - 1) * 100 : 0.0;
  double _getPeriodEndAvgReturn() => _sliceAvgValues.isNotEmpty ? (_sliceAvgValues.last - 1) * 100 : 0.0;
  double _getPeriodEndCustomFundReturn() => _sliceCustomFundValues.isNotEmpty ? (_sliceCustomFundValues.last - 1) * 100 : 0.0;

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

  void _updateHoverFromPosition(Offset globalPosition) {
    final renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(globalPosition);
    if (localPosition.dx < 0 || localPosition.dx > renderBox.size.width ||
        localPosition.dy < 0 || localPosition.dy > renderBox.size.height) {
      _clearHover();
      return;
    }

    _chartWidth = renderBox.size.width;
    _chartHeight = renderBox.size.height;

    const leftMargin = 45.0;
    final chartWidth = renderBox.size.width - leftMargin;

    if (chartWidth <= 0) return;

    double relativeX = (localPosition.dx - leftMargin) / chartWidth;
    relativeX = relativeX.clamp(0.0, 1.0);

    final index = (relativeX * _maxIndex).round();
    final clampedIndex = index.clamp(0, _maxIndex);

    final transformedFundValues = _sliceFundValues.map((v) => v - 1.0).toList();
    if (clampedIndex < transformedFundValues.length) {
      _updateHoverPosition(clampedIndex, transformedFundValues[clampedIndex]);
    }
  }

  void _updateHoverPosition(int newIndex, double spotY) {
    if (newIndex == _hoverIndexNotifier.value) return;

    final now = DateTime.now();
    if (now.difference(_lastUpdateTime) < const Duration(milliseconds: 16)) return;
    _lastUpdateTime = now;

    _hoverIndexNotifier.value = newIndex;

    const leftMargin = 45.0;
    const bottomMargin = 30.0;
    final plotWidth = _chartWidth - leftMargin;
    final plotHeight = _chartHeight - bottomMargin;

    if (plotWidth > 0 && plotHeight > 0 && _maxIndex > 0) {
      final crossX = leftMargin + (newIndex / _maxIndex) * plotWidth;
      _crosshairXNotifier.value = crossX;
      final yRange = _currentMaxY - _currentMinY;
      final normalized = yRange > 0 ? (spotY - _currentMinY) / yRange : 0.5;
      final crossY = plotHeight * (1 - normalized);
      _crosshairYNotifier.value = crossY;

      _dotPositionNotifier.value = Offset(crossX, crossY);
    }
  }

  void _clearHover() {
    if (_hoverIndexNotifier.value != -1) {
      _hoverIndexNotifier.value = -1;
      _dotPositionNotifier.value = null;
    }
  }

  void _handlePointerEvent(PointerEvent event) {
    _updateHoverFromPosition(event.position);
  }

  Future<void> _exportChart() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      _hoverIndexNotifier.value = -1;
      _dotPositionNotifier.value = null;
      await Future.delayed(const Duration(milliseconds: 100));

      final boundary = _chartContainerKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _showExportResult(false, '截图失败');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showExportResult(false, '图片转换失败');
        return;
      }

      final pngBytes = byteData.buffer.asUint8List();

      if (Platform.isAndroid || Platform.isIOS) {
        await Gal.putImageBytes(pngBytes, album: 'FundLink');
        _showExportResult(true, '已保存到相册');
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${dir.path}${Platform.pathSeparator}fund_performance_$timestamp.png';
        final file = File(filePath);
        await file.writeAsBytes(pngBytes);
        _showExportResult(true, '已保存到 $filePath');
      }
    } catch (e) {
      _showExportResult(false, '保存失败: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showExportResult(bool success, String message) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(success ? '导出成功' : '导出失败'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDatePickerAndApply({required bool isStart}) async {
    final now = DateTime.now();
    final initialDate = isStart
        ? (_customStartDate ?? now.subtract(const Duration(days: 90)))
        : (_customEndDate ?? now);

    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (ctx) => _DatePickerModal(
        initialDate: initialDate,
        title: isStart ? '选择开始日期' : '选择结束日期',
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _customStartDate = picked;
        } else {
          _customEndDate = picked;
        }
        if (_customStartDate != null && _customEndDate != null) {
          _useCustomRange = true;
          _selectedRange = '';
          _updateSliceAndNormalize();
          _hoverIndexNotifier.value = -1;
          _dotPositionNotifier.value = null;
        }
      });
    }
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
    final transformedZZ500Values = _sliceZZ500Values.map((v) => v - 1.0).toList();
    final transformedZZ1000Values = _sliceZZ1000Values.map((v) => v - 1.0).toList();
    final transformedCustomFundValues = _sliceCustomFundValues.map((v) => v - 1.0).toList();

    final fundSpots = List.generate(transformedFundValues.length,
            (i) => FlSpot(i.toDouble(), transformedFundValues[i]));
    final avgSpots = List.generate(transformedAvgValues.length,
            (i) => FlSpot(i.toDouble(), transformedAvgValues[i]));
    final hsSpots = List.generate(transformedHsValues.length,
            (i) => FlSpot(i.toDouble(), transformedHsValues[i]));
    final zz500Spots = List.generate(transformedZZ500Values.length,
            (i) => FlSpot(i.toDouble(), transformedZZ500Values[i]));
    final zz1000Spots = List.generate(transformedZZ1000Values.length,
            (i) => FlSpot(i.toDouble(), transformedZZ1000Values[i]));
    final customFundSpots = List.generate(transformedCustomFundValues.length,
            (i) => FlSpot(i.toDouble(), transformedCustomFundValues[i]));

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
    if (_showZZ500 && transformedZZ500Values.isNotEmpty) {
      final zz500Min = transformedZZ500Values.reduce((a, b) => a < b ? a : b);
      final zz500Max = transformedZZ500Values.reduce((a, b) => a > b ? a : b);
      minY = minY < zz500Min ? minY : zz500Min;
      maxY = maxY > zz500Max ? maxY : zz500Max;
    }
    if (_showZZ1000 && transformedZZ1000Values.isNotEmpty) {
      final zz1000Min = transformedZZ1000Values.reduce((a, b) => a < b ? a : b);
      final zz1000Max = transformedZZ1000Values.reduce((a, b) => a > b ? a : b);
      minY = minY < zz1000Min ? minY : zz1000Min;
      maxY = maxY > zz1000Max ? maxY : zz1000Max;
    }
    if (_showCustomFund && transformedCustomFundValues.isNotEmpty) {
      final customMin = transformedCustomFundValues.reduce((a, b) => a < b ? a : b);
      final customMax = transformedCustomFundValues.reduce((a, b) => a > b ? a : b);
      minY = minY < customMin ? minY : customMin;
      maxY = maxY > customMax ? maxY : customMax;
    }

    final range = maxY - minY;
    final interval = _getNiceInterval(minY, maxY);

    // Snap to interval grid with padding, so labels never overlap or appear redundant
    final paddedMin = minY - range * 0.1;
    final paddedMax = maxY + range * 0.1;
    minY = (paddedMin / interval).floorToDouble() * interval;
    maxY = (paddedMax / interval).ceilToDouble() * interval;

    if (maxY - minY < interval * 2) {
      final center = (maxY + minY) / 2;
      minY = center - interval;
      maxY = center + interval;
    }

    _currentMinY = minY;
    _currentMaxY = maxY;
    _maxIndex = fundSpots.length - 1;

    final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);

    final screenWidth = MediaQuery.of(context).size.width;
    final maxXAxisTicks = screenWidth < 600 ? 4 : 6;
    final bottomInterval = (_maxIndex / maxXAxisTicks).ceilToDouble();

    final fillColor = rangeReturn >= 0
        ? CupertinoColors.systemRed.withOpacity(0.15)
        : CupertinoColors.systemGreen.withOpacity(0.15);

    final gradientFillColor = rangeReturn >= 0
        ? LinearGradient(
            colors: [
              CupertinoColors.systemRed.withOpacity(isDark ? 0.3 : 0.2),
              CupertinoColors.systemRed.withOpacity(isDark ? 0.05 : 0.02),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : LinearGradient(
            colors: [
              CupertinoColors.systemGreen.withOpacity(isDark ? 0.3 : 0.2),
              CupertinoColors.systemGreen.withOpacity(isDark ? 0.05 : 0.02),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '业绩走势',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  _buildExportButton(isDark),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: returnColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_useCustomRange ? '自定义区间' : rangeName}涨跌幅 ${rangeReturn >= 0 ? '+' : ''}${rangeReturn.toStringAsFixed(2)}%${_useCustomRange && _customStartDate != null && _customEndDate != null ? ' [${_customEndDate!.difference(_customStartDate!).inDays}天]' : ''}',
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
                  isSelected: _selectedRange == key && !_useCustomRange,
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
                  isSelected: _selectedRange == key && !_useCustomRange,
                  onTap: () => _onRangeChanged(key),
                  isDark: isDark,
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          _buildCustomDateRow(isDark),
          const SizedBox(height: 12),
          RepaintBoundary(
            key: _chartContainerKey,
            child: Container(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _useCustomRange && _customStartDate != null && _customEndDate != null
                          ? '${_customStartDate!.year}/${_customStartDate!.month.toString().padLeft(2, '0')}/${_customStartDate!.day.toString().padLeft(2, '0')} - ${_customEndDate!.year}/${_customEndDate!.month.toString().padLeft(2, '0')}/${_customEndDate!.day.toString().padLeft(2, '0')} 期间业绩走势'
                          : '${_rangeLabels[_selectedRange] ?? ''}业绩走势',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? CupertinoColors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 240,
                    child: MouseRegion(
                onExit: (_) => _clearHover(),
                child: Listener(
                  onPointerDown: _handlePointerEvent,
                  onPointerMove: _handlePointerEvent,
                  onPointerHover: _handlePointerEvent,
                  onPointerUp: (_) => _clearHover(),
                  onPointerCancel: (_) => _clearHover(),
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
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
                              sideTitles: SideTitles(showTitles: false, reservedSize: 38),
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
                          lineTouchData: const LineTouchData(
                            enabled: false,
                            handleBuiltInTouches: false,
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
                                gradient: gradientFillColor,
                                cutOffY: 0,
                                applyCutOffY: true,
                              ),
                              aboveBarData: BarAreaData(
                                show: true,
                                gradient: gradientFillColor,
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
                            if (_showZZ500 && zz500Spots.isNotEmpty)
                              LineChartBarData(
                                spots: zz500Spots,
                                isCurved: true,
                                color: const Color(0xFFFF9800), 
                                barWidth: 1.5,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                                aboveBarData: BarAreaData(show: false),
                              ),
                            if (_showZZ1000 && zz1000Spots.isNotEmpty)
                              LineChartBarData(
                                spots: zz1000Spots,
                                isCurved: true,
                                color: const Color(0xFF9C27B0), 
                                barWidth: 1.5,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                                aboveBarData: BarAreaData(show: false),
                              ),
                            if (_showCustomFund && customFundSpots.isNotEmpty)
                              LineChartBarData(
                                spots: customFundSpots,
                                isCurved: true,
                                color: const Color(0xFF00BCD4), 
                                barWidth: 1.5,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                                aboveBarData: BarAreaData(show: false),
                              ),
                          ],
                        ),
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _hoverIndexNotifier,
                      builder: (context, hoverIndex, child) {
                        if (hoverIndex == -1 || _chartWidth == 0 || _chartHeight == 0) {
                          return const SizedBox.shrink();
                        }
                        return ValueListenableBuilder<double>(
                          valueListenable: _crosshairXNotifier,
                          builder: (context, crossX, _) {
                            return ValueListenableBuilder<double>(
                              valueListenable: _crosshairYNotifier,
                              builder: (context, crossY, __) {
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _CrosshairPainter(
                                          crossX: crossX,
                                          crossY: crossY,
                                          color: morandiColor,
                                        ),
                                      ),
                                    ),
                                    if (crossX > 0 && crossX < _chartWidth)
                                      Positioned(
                                        left: crossX < 80 ? crossX : (crossX > _chartWidth - 80 ? _chartWidth - 80 : crossX - 40),
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
                                    if (crossY > 0 && crossY < _chartHeight)
                                      Positioned(
                                        left: 0,
                                        top: crossY < 24 ? crossY : (crossY > _chartHeight - 24 ? _chartHeight - 24 : crossY - 12),
                                        child: IgnorePointer(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: morandiColor,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${_getHoverFundReturn() >= 0 ? '+' : ''}${_getHoverFundReturn().toStringAsFixed(2)}%',
                                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    ValueListenableBuilder<Offset?>(
                      valueListenable: _dotPositionNotifier,
                      builder: (context, dotPosition, child) {
                        if (dotPosition == null) return const SizedBox.shrink();
                        return Positioned(
                          left: dotPosition.dx - 5,
                          top: dotPosition.dy - 5,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: fundLineColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.black : Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
            valueListenable: _hoverIndexNotifier,
            builder: (context, hoverIndex, child) {
              final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);
              final exporting = _exporting;

              final toggleHs300 = exporting ? null : _toggleHs300;
              final toggleZZ500 = exporting ? null : _toggleZZ500;
              final toggleZZ1000 = exporting ? null : _toggleZZ1000;
              final toggleAvg = exporting ? null : _toggleAverage;

              final showHs300 = exporting ? _showHs300 : true;
              final showZZ500 = exporting ? _showZZ500 : true;
              final showZZ1000 = exporting ? _showZZ1000 : true;
              final showAvg = exporting ? _showAverage : isShortRange;
              final showCustom = exporting ? _showCustomFund : true;

              final allItems = <Widget>[
                _buildLegendItemWithValue(
                  widget.fundCode != null ? '本基金(${widget.fundCode})' : '本基金',
                  fundLineColor,
                  exporting ? _getPeriodEndFundReturn() : _getHoverFundReturn(),
                  isDark,
                  null,
                  forceShowValue: exporting,
                ),
                if (showHs300)
                  _buildLegendItemWithValue('沪深300', CupertinoColors.systemGrey, exporting ? _getPeriodEndHsReturn() : _getHoverHsReturn(), isDark, toggleHs300, forceShowValue: exporting),
                if (showZZ500)
                  _buildLegendItemWithValue('中证500', const Color(0xFFFF9800), exporting ? _getPeriodEndZZ500Return() : _getHoverZZ500Return(), isDark, toggleZZ500, forceShowValue: exporting),
                if (showZZ1000)
                  _buildLegendItemWithValue('中证1000', const Color(0xFF9C27B0), exporting ? _getPeriodEndZZ1000Return() : _getHoverZZ1000Return(), isDark, toggleZZ1000, forceShowValue: exporting),
                if (showCustom)
                  _buildCustomFundLegendItem(isDark, showEye: !exporting, forceShowValue: exporting),
                if (showAvg)
                  _buildLegendItemWithValue('同类平均', CupertinoColors.systemBlue, exporting ? _getPeriodEndAvgReturn() : _getHoverAvgReturn(), isDark, toggleAvg, forceShowValue: exporting),
              ];

              final rows = <Widget>[];
              for (int i = 0; i < allItems.length; i += 3) {
                final end = (i + 3).clamp(0, allItems.length);
                rows.add(
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: allItems.sublist(i, end),
                  ),
                );
                if (end < allItems.length) {
                  rows.add(const SizedBox(height: 8));
                }
              }

              return Column(children: rows);
            },
                ),
              ],
            ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '*因API接口关系，宽基指数采用跟踪ETF联接基金(沪深300-460300|中证500-004348|中证1000-011860)，实际指数可能存在细微跟踪误差。',
              style: TextStyle(
                fontSize: 9,
                color: isDark ? Colors.white38 : Colors.black38,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(bool isDark) {
    final bgColor = isDark
        ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
        : CupertinoColors.white.withValues(alpha: 0.85);

    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CupertinoButton(
        onPressed: _exporting ? null : _exportChart,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        borderRadius: BorderRadius.circular(15),
        child: _exporting
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CupertinoActivityIndicator(),
              )
            : Text(
                '导出走势图',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? CupertinoColors.white : CupertinoColors.label,
                ),
              ),
      ),
    );
  }

  Widget _buildCustomDateRow(bool isDark) {
    final isActive = _useCustomRange;

    String startLabel;
    if (_customStartDate != null) {
      startLabel = '${_customStartDate!.year}-${_customStartDate!.month.toString().padLeft(2, '0')}-${_customStartDate!.day.toString().padLeft(2, '0')}';
    } else {
      startLabel = '开始日期';
    }

    String endLabel;
    if (_customEndDate != null) {
      endLabel = '${_customEndDate!.year}-${_customEndDate!.month.toString().padLeft(2, '0')}-${_customEndDate!.day.toString().padLeft(2, '0')}';
    } else {
      endLabel = '结束日期';
    }

    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildGlassButton(
              label: startLabel,
              isSelected: isActive,
              onTap: () => _showDatePickerAndApply(isStart: true),
              isDark: isDark,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildGlassButton(
              label: endLabel,
              isSelected: isActive,
              onTap: () => _showDatePickerAndApply(isStart: false),
              isDark: isDark,
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: _useCustomRange ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          builder: (context, value, child) {
            return Padding(
              padding: EdgeInsets.only(left: 4.0 * value),
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: _buildClearButton(isDark),
        ),
      ],
    );
  }

  Widget _buildClearButton(bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _useCustomRange = false;
          _customStartDate = null;
          _customEndDate = null;
          _selectedRange = '3m';
          _updateSliceAndNormalize();
          _hoverIndexNotifier.value = -1;
          _dotPositionNotifier.value = null;
        });
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
              : CupertinoColors.white.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.xmark,
          size: 14,
          color: isDark ? CupertinoColors.white : CupertinoColors.label,
        ),
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

  Widget _buildLegendItemWithValue(String label, Color color, double value, bool isDark, VoidCallback? onToggle, {bool forceShowValue = false}) {
    final valueStr = (value != 0 || forceShowValue) ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%' : '--';
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
                  _getEyeIconState(onToggle),
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

  IconData _getEyeIconState(VoidCallback toggle) {
    if (toggle == _toggleAverage) return _showAverage ? CupertinoIcons.eye : CupertinoIcons.eye_slash;
    if (toggle == _toggleHs300) return _showHs300 ? CupertinoIcons.eye : CupertinoIcons.eye_slash;
    if (toggle == _toggleZZ500) return _showZZ500 ? CupertinoIcons.eye : CupertinoIcons.eye_slash;
    if (toggle == _toggleZZ1000) return _showZZ1000 ? CupertinoIcons.eye : CupertinoIcons.eye_slash;
    if (toggle == _toggleCustomFund) return _showCustomFund ? CupertinoIcons.eye : CupertinoIcons.eye_slash;
    return CupertinoIcons.eye;
  }

  Widget _buildCustomFundLegendItem(bool isDark, {bool showEye = true, bool forceShowValue = false}) {
    final value = forceShowValue ? _getPeriodEndCustomFundReturn() : _getHoverCustomFundReturn();
    final valueStr = (value != 0 || forceShowValue) ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%' : '--';
    final valueColor = value >= 0 ? CupertinoColors.systemRed : CupertinoColors.systemGreen;
    final displayLabel = widget.customFundCode != null ? '自定义(${widget.customFundCode})' : '自定义';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: widget.onCustomFundConfig,
              child: Row(
                children: [
                  Container(width: 12, height: 12, color: const Color(0xFF00BCD4)),
                  const SizedBox(width: 4),
                  Text(displayLabel, style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87)),
                ],
              ),
            ),
            if (showEye) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _toggleCustomFund,
                child: Icon(
                  _showCustomFund ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 14,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
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

class _DatePickerModal extends StatefulWidget {
  final DateTime initialDate;
  final String title;

  const _DatePickerModal({
    required this.initialDate,
    required this.title,
  });

  @override
  State<_DatePickerModal> createState() => _DatePickerModalState();
}

class _DatePickerModalState extends State<_DatePickerModal> {
  late DateTime _tempDate;

  @override
  void initState() {
    super.initState();
    _tempDate = widget.initialDate;
  }

  void _updateTempDate({int? year, int? month, int? day}) {
    setState(() {
      int y = year ?? _tempDate.year;
      int m = month ?? _tempDate.month;
      int d = day ?? _tempDate.day;
      int maxDays = DateTime(y, m + 1, 0).day;
      if (d > maxDays) d = maxDays;
      _tempDate = DateTime(y, m, d);
    });
  }

  Widget _buildPickerColumn({
    required List<int> items,
    required int selectedIndex,
    required String suffix,
    required ValueChanged<int> onChanged,
    required Color bgColor,
    required Color textColor,
    required Widget selectionOverlay,
  }) {
    return Expanded(
      child: CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: selectedIndex.clamp(0, items.length - 1)),
        itemExtent: 36,
        backgroundColor: bgColor,
        selectionOverlay: selectionOverlay,
        onSelectedItemChanged: onChanged,
        children: items.map((item) => Center(
          child: Text(
            '$item$suffix',
            style: TextStyle(fontSize: 18, color: textColor),
          ),
        )).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final now = DateTime.now();
    final years = List.generate(10, (i) => now.year - 5 + i);
    final months = List.generate(12, (i) => i + 1);
    final maxDay = DateTime(_tempDate.year, _tempDate.month + 1, 0).day;
    final days = List.generate(maxDay, (i) => i + 1);

    final panelBgColor = isDarkMode ? const Color(0xFF1C1C1E) : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final selectionOverlay = CupertinoPickerDefaultSelectionOverlay(
      background: isDarkMode
          ? CupertinoColors.white.withValues(alpha: 0.05)
          : CupertinoColors.black.withValues(alpha: 0.03),
    );

    final yearIndex = years.indexOf(_tempDate.year);

    return CupertinoPopupSurface(
      child: Container(
        height: 310,
        decoration: BoxDecoration(
          color: panelBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  _buildPickerColumn(
                    items: years,
                    selectedIndex: yearIndex >= 0 ? yearIndex : 0,
                    suffix: '年',
                    onChanged: (i) => _updateTempDate(year: years[i]),
                    bgColor: panelBgColor,
                    textColor: textColor,
                    selectionOverlay: selectionOverlay,
                  ),
                  _buildPickerColumn(
                    items: months,
                    selectedIndex: _tempDate.month - 1,
                    suffix: '月',
                    onChanged: (i) => _updateTempDate(month: i + 1),
                    bgColor: panelBgColor,
                    textColor: textColor,
                    selectionOverlay: selectionOverlay,
                  ),
                  _buildPickerColumn(
                    items: days,
                    selectedIndex: _tempDate.day - 1,
                    suffix: '日',
                    onChanged: (i) => _updateTempDate(day: i + 1),
                    bgColor: panelBgColor,
                    textColor: textColor,
                    selectionOverlay: selectionOverlay,
                  ),
                ],
              ),
            ),
            Container(
              height: 0.5,
              color: isDarkMode
                  ? CupertinoColors.separator
                  : CupertinoColors.opaqueSeparator,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassButton(
                    label: '取消',
                    onPressed: () => Navigator.pop(context),
                    isPrimary: false,
                    height: 44,
                    borderRadius: 30,
                  ),
                  const SizedBox(width: 12),
                  GlassButton(
                    label: '完成',
                    onPressed: () => Navigator.pop(context, _tempDate),
                    isPrimary: true,
                    height: 44,
                    borderRadius: 30,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
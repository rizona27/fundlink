import 'package:flutter/cupertino.dart';
import '../services/fund_service.dart';
import '../services/data_manager.dart';
import '../models/net_worth_point.dart';
import '../models/fund_holding.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

class FundPerformanceDialog extends StatefulWidget {
  final String fundCode;
  final String fundName;
  final DataManager? dataManager;
  final FundHolding? holding; 

  const FundPerformanceDialog({
    super.key,
    required this.fundCode,
    required this.fundName,
    this.dataManager,
    this.holding,
  });

  @override
  State<FundPerformanceDialog> createState() => _FundPerformanceDialogState();
}

class _FundPerformanceDialogState extends State<FundPerformanceDialog> {
  late FundService _fundService;
  bool _loading = true;
  String? _error;
  
  Map<String, double?> _performanceData = {};
  Set<String> _calculatedPeriods = {};
  Map<String, String> _periodDateRanges = {};
  DateTime? _fundEstablishDate; 
  DateTime? _dataEndDate; 
  
  final List<Map<String, dynamic>> _periods = [
    {'label': '近1周', 'days': 7},
    {'label': '近2周', 'days': 14},
    {'label': '近3周', 'days': 21},
    {'label': '近1月', 'days': 30},
    {'label': '近2月', 'days': 60},
    {'label': '近3月', 'days': 90},
    {'label': '近6月', 'days': 180},
    {'label': '近1年', 'days': 365},
    {'label': '近2年', 'days': 730},
    {'label': '近3年', 'days': 1095},
    {'label': '近5年', 'days': 1825},
    {'label': '今年来', 'special': 'ytd'},
    {'label': '成立来', 'special': 'inception'},
  ];

  @override
  void initState() {
    super.initState();
    _fundService = FundService(widget.dataManager);
    _loadPerformanceData();
  }

  Future<void> _loadPerformanceData() async {
    if (mounted) setState(() {  // ✅ 添加 mounted 检查
      _loading = true;
      _error = null;
    });

    try {
      final historyPoints = await _fundService.fetchNetWorthTrend(widget.fundCode);
      
      if (historyPoints.isEmpty) {
        throw Exception('无法获取历史净值数据');
      }

      historyPoints.sort((a, b) => a.date.compareTo(b.date));
      
      _fundEstablishDate = historyPoints.first.date;
      _dataEndDate = historyPoints.last.date;
      
      final cachedInfo = widget.dataManager?.getFundInfoCache(widget.fundCode);
      if (cachedInfo != null) {
        _performanceData['近1月'] = cachedInfo.navReturn1m;
        _performanceData['近3月'] = cachedInfo.navReturn3m;
        _performanceData['近6月'] = cachedInfo.navReturn6m;
        _performanceData['近1年'] = cachedInfo.navReturn1y;
      } else if (widget.holding != null) {
        final h = widget.holding!;
        _performanceData['近1月'] = h.navReturn1m;
        _performanceData['近3月'] = h.navReturn3m;
        _performanceData['近6月'] = h.navReturn6m;
        _performanceData['近1年'] = h.navReturn1y;
      }
      
      final latestPoint = historyPoints.last;
      final latestDate = latestPoint.date;
      
      for (var period in _periods) {
        final label = period['label'] as String;
        
        if (_performanceData.containsKey(label) && _performanceData[label] != null) {
          continue;
        }
        
        DateTime? startDate;
        DateTime? endDate;
        
        if (period['special'] == 'ytd') {
          startDate = DateTime(latestDate.year, 1, 1);
          endDate = latestDate;
          _performanceData[label] = 
            _calculateReturn(historyPoints, startDate, endDate);
          _calculatedPeriods.add(label); 
        } else if (period['special'] == 'inception') {
          startDate = _fundEstablishDate!;
          endDate = latestDate;
          _performanceData[label] = 
            _calculateReturn(historyPoints, startDate, endDate);
          _calculatedPeriods.add(label); 
        } else {
          final days = period['days'] as int;
          
          final fundAgeDays = latestDate.difference(_fundEstablishDate!).inDays;
          if (fundAgeDays < days) {
            _performanceData[label] = null;
            _periodDateRanges[label] = '基金成立不足${_getPeriodText(days)}';
            continue;
          }
          
          final targetStartDate = latestDate.subtract(Duration(days: days));
          
          NetWorthPoint? actualStartPoint;
          for (int i = historyPoints.length - 1; i >= 0; i--) {
            if (historyPoints[i].date.isBefore(targetStartDate) || 
                historyPoints[i].date.isAtSameMomentAs(targetStartDate)) {
              actualStartPoint = historyPoints[i];
              break;
            }
          }
          
          startDate = actualStartPoint?.date ?? historyPoints.first.date;
          endDate = latestDate;
          
          _performanceData[label] = 
            _calculateReturn(historyPoints, startDate!, endDate!);
          _calculatedPeriods.add(label); 
        }
        
        if (startDate != null && endDate != null) {
          _periodDateRanges[label] = '${_formatDate(startDate)} ~ ${_formatDate(endDate)}';
        }
      }
      
      if (mounted) setState(() {  // ✅ 添加 mounted 检查
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {  // ✅ 添加 mounted 检查
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double? _calculateReturn(
    List<NetWorthPoint> points,
    DateTime startDate,
    DateTime endDate,
  ) {
    NetWorthPoint? startPoint;
    int minStartDiff = 999999;
    
    for (var point in points) {
      final diff = point.date.difference(startDate).inDays.abs();
      if (diff < minStartDiff) {
        startPoint = point;
        minStartDiff = diff;
      }
    }
    
    startPoint ??= points.first;
    
    NetWorthPoint? endPoint;
    int minEndDiff = 999999;
    
    for (var point in points) {
      final diff = point.date.difference(endDate).inDays.abs();
      if (diff < minEndDiff) {
        endPoint = point;
        minEndDiff = diff;
      }
    }
    
    endPoint ??= points.last;

    if (startPoint.nav <= 0) {
      return null;
    }

    return ((endPoint.nav - startPoint.nav) / startPoint.nav) * 100;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _getPeriodText(int days) {
    if (days < 30) {
      return '${days}天';
    } else if (days < 365) {
      final months = (days / 30).round();
      return '${months}个月';
    } else {
      final years = (days / 365).round();
      return '${years}年';
    }
  }

  Color _getReturnColor(double? value) {
    if (value == null) return CupertinoColors.systemGrey;
    if (value > 0) return const Color(0xFFFF3B30); 
    if (value < 0) return const Color(0xFF34C759); 
    return CupertinoColors.systemGrey; 
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.75,
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '业绩详情',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.fundName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark 
                                  ? CupertinoColors.systemGrey2 
                                  : CupertinoColors.systemGrey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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
              
              Flexible(
                child: _loading
                    ? const Center(child: CupertinoActivityIndicator())
                    : _error != null
                        ? _buildErrorView(isDark)
                        : _buildPerformanceList(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(bool isDark) {
    final bool isNetworkError = _error!.contains('ClientException') || 
                                 _error!.contains('SocketException') ||
                                 _error!.contains('Failed host lookup');
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNetworkError ? CupertinoIcons.wifi_slash : CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: isNetworkError 
                  ? CupertinoColors.systemOrange 
                  : CupertinoColors.systemRed,
            ),
            const SizedBox(height: 16),
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
                    ? CupertinoColors.systemGrey2 
                    : CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: isNetworkError ? '重新连接' : '重试',
              icon: CupertinoIcons.refresh,
              onPressed: _loadPerformanceData,
              isPrimary: true,
              height: 40,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _periods.length + 3, 
      itemBuilder: (context, index) {
        if (index == _periods.length) {
          return _buildEstablishmentDateRow(isDark);
        }
        if (index == _periods.length + 1) {
          return _buildDataEndDateRow(isDark);
        }
        if (index == _periods.length + 2) {
          return _buildDisclaimerRow(isDark);
        }

        final period = _periods[index];
        final label = period['label'] as String;
        final value = _performanceData[label];

        return _buildPerformanceRow(label, value, isDark);
      },
    );
  }

  Widget _buildPerformanceRow(String label, double? value, bool isDark) {
    final dateRange = _periodDateRanges[label];
    final showDateRange = dateRange != null && dateRange.isNotEmpty;
    final isCalculated = _calculatedPeriods.contains(label);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? CupertinoColors.white.withOpacity(0.1)
                : CupertinoColors.black.withOpacity(0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    if (isCalculated)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '*',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark 
                                ? CupertinoColors.systemGrey.withOpacity(0.5)
                                : CupertinoColors.systemGrey.withOpacity(0.6),
                          ),
                        ),
                      ),
                  ],
                ),
                if (showDateRange)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      dateRange!,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark 
                            ? CupertinoColors.systemGrey.withOpacity(0.6)
                            : CupertinoColors.systemGrey.withOpacity(0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value != null ? '${value.toStringAsFixed(2)}%' : '--',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _getReturnColor(value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstablishmentDateRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.systemGrey.withOpacity(0.2)
            : CupertinoColors.systemGrey6.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.calendar,
            size: 16,
            color: isDark 
                ? CupertinoColors.systemGrey2 
                : CupertinoColors.systemGrey,
          ),
          const SizedBox(width: 8),
          Text(
            '基金成立日:',
            style: TextStyle(
              fontSize: 13,
              color: isDark 
                  ? CupertinoColors.systemGrey2 
                  : CupertinoColors.systemGrey,
            ),
          ),
          const Spacer(),
          Text(
            _fundEstablishDate != null 
                ? _formatDate(_fundEstablishDate!) 
                : '--',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataEndDateRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.systemGrey.withOpacity(0.2)
            : CupertinoColors.systemGrey6.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.clock,
            size: 16,
            color: isDark 
                ? CupertinoColors.systemGrey2 
                : CupertinoColors.systemGrey,
          ),
          const SizedBox(width: 8),
          Text(
            '数据截止日:',
            style: TextStyle(
              fontSize: 13,
              color: isDark 
                  ? CupertinoColors.systemGrey2 
                  : CupertinoColors.systemGrey,
            ),
          ),
          const Spacer(),
          Text(
            _dataEndDate != null 
                ? _formatDate(_dataEndDate!) 
                : '--',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.systemOrange.withOpacity(0.1)
            : CupertinoColors.systemOrange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? CupertinoColors.systemOrange.withOpacity(0.3)
              : CupertinoColors.systemOrange.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.info_circle,
            size: 14,
            color: isDark 
                ? CupertinoColors.systemOrange 
                : CupertinoColors.systemOrange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '带*周期为计算数据，仅供参考(更新T日更为准确)。',
              style: TextStyle(
                fontSize: 11,
                color: isDark 
                    ? CupertinoColors.systemOrange.withOpacity(0.9)
                    : CupertinoColors.systemOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

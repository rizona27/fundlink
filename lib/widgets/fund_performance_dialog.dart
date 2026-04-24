import 'package:flutter/cupertino.dart';
import '../services/fund_service.dart';
import '../services/data_manager.dart';
import '../models/net_worth_point.dart';
import '../models/fund_holding.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

/// 基金业绩详情弹窗
/// 展示多个周期的业绩表现
class FundPerformanceDialog extends StatefulWidget {
  final String fundCode;
  final String fundName;
  final DataManager? dataManager;
  final FundHolding? holding; // 可选，用于获取API返回的收益率数据

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
  
  // 存储各周期的业绩数据
  Map<String, double?> _performanceData = {};
  // 标记哪些是计算数据(非API数据)
  Set<String> _calculatedPeriods = {};
  // 存储各周期的日期区间说明
  Map<String, String> _periodDateRanges = {};
  DateTime? _fundEstablishDate; // 基金成立日期
  DateTime? _dataEndDate; // 数据截止日期
  
  // 周期定义
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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 获取历史净值数据
      final historyPoints = await _fundService.fetchNetWorthTrend(widget.fundCode);
      
      if (historyPoints.isEmpty) {
        throw Exception('无法获取历史净值数据');
      }

      // 按日期排序（升序）
      historyPoints.sort((a, b) => a.date.compareTo(b.date));
      
      // 获取基金成立日期（最早的数据日期）
      _fundEstablishDate = historyPoints.first.date;
      // 获取数据截止日期（最新的数据日期）
      _dataEndDate = historyPoints.last.date;
      
      // 优先从 DataManager 缓存读取 API 返回的收益率数据
      final cachedInfo = widget.dataManager?.getFundInfoCache(widget.fundCode);
      if (cachedInfo != null) {
        _performanceData['近1月'] = cachedInfo.navReturn1m;
        _performanceData['近3月'] = cachedInfo.navReturn3m;
        _performanceData['近6月'] = cachedInfo.navReturn6m;
        _performanceData['近1年'] = cachedInfo.navReturn1y;
      } else if (widget.holding != null) {
        // 如果没有缓存，尝试从 holding 中获取
        final h = widget.holding!;
        _performanceData['近1月'] = h.navReturn1m;
        _performanceData['近3月'] = h.navReturn3m;
        _performanceData['近6月'] = h.navReturn6m;
        _performanceData['近1年'] = h.navReturn1y;
      }
      
      // 计算各周期业绩（只计算没有API数据的周期）
      // 使用最新净值日期作为基准，而不是当前日期
      final latestPoint = historyPoints.last;
      final latestDate = latestPoint.date;
      
      for (var period in _periods) {
        final label = period['label'] as String;
        
        // 如果已经有API数据，跳过
        if (_performanceData.containsKey(label) && _performanceData[label] != null) {
          continue;
        }
        
        DateTime? startDate;
        DateTime? endDate;
        
        if (period['special'] == 'ytd') {
          // 今年来：从今年1月1日到最新净值日期
          startDate = DateTime(latestDate.year, 1, 1);
          endDate = latestDate;
          _performanceData[label] = 
            _calculateReturn(historyPoints, startDate, endDate);
          _calculatedPeriods.add(label); // 标记为计算数据
        } else if (period['special'] == 'inception') {
          // 成立来：从成立日到最新净值日期
          startDate = _fundEstablishDate!;
          endDate = latestDate;
          _performanceData[label] = 
            _calculateReturn(historyPoints, startDate, endDate);
          _calculatedPeriods.add(label); // 标记为计算数据
        } else {
          // 固定天数周期：从最新净值日期往前推N天
          final days = period['days'] as int;
          
          // 检查基金成立时间是否足够
          final fundAgeDays = latestDate.difference(_fundEstablishDate!).inDays;
          if (fundAgeDays < days) {
            // 基金成立时间不足该周期，显示--
            _performanceData[label] = null;
            _periodDateRanges[label] = '基金成立不足${_getPeriodText(days)}';
            continue;
          }
          
          // 计算起始日期（自然日）
          final targetStartDate = latestDate.subtract(Duration(days: days));
          
          // 找到targetStartDate之前最后一个有净值的交易日作为起点
          NetWorthPoint? actualStartPoint;
          for (int i = historyPoints.length - 1; i >= 0; i--) {
            if (historyPoints[i].date.isBefore(targetStartDate) || 
                historyPoints[i].date.isAtSameMomentAs(targetStartDate)) {
              actualStartPoint = historyPoints[i];
              break;
            }
          }
          
          // 如果找不到，使用最早的点
          startDate = actualStartPoint?.date ?? historyPoints.first.date;
          endDate = latestDate;
          
          _performanceData[label] = 
            _calculateReturn(historyPoints, startDate!, endDate!);
          _calculatedPeriods.add(label); // 标记为计算数据
        }
        
        // 保存日期区间说明（显示实际使用的净值日期）
        if (startDate != null && endDate != null) {
          _periodDateRanges[label] = '${_formatDate(startDate)} ~ ${_formatDate(endDate)}';
        }
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 计算指定区间的收益率
  double? _calculateReturn(
    List<NetWorthPoint> points,
    DateTime startDate,
    DateTime endDate,
  ) {
    // 找到最接近起始日期的净值点
    NetWorthPoint? startPoint;
    int minStartDiff = 999999;
    
    for (var point in points) {
      final diff = point.date.difference(startDate).inDays.abs();
      if (diff < minStartDiff) {
        startPoint = point;
        minStartDiff = diff;
      }
    }
    
    // 如果找不到合适的起始点，使用最早的点
    startPoint ??= points.first;
    
    // 找到最接近结束日期的净值点
    NetWorthPoint? endPoint;
    int minEndDiff = 999999;
    
    for (var point in points) {
      final diff = point.date.difference(endDate).inDays.abs();
      if (diff < minEndDiff) {
        endPoint = point;
        minEndDiff = diff;
      }
    }
    
    // 如果找不到合适的结束点，使用最新的点
    endPoint ??= points.last;

    if (startPoint.nav <= 0) {
      return null;
    }

    // 计算收益率
    return ((endPoint.nav - startPoint.nav) / startPoint.nav) * 100;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 将天数转换为易读的周期文本
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
    if (value > 0) return const Color(0xFFFF3B30); // 红色（正收益）
    if (value < 0) return const Color(0xFF34C759); // 绿色（负收益）
    return CupertinoColors.systemGrey; // 灰色（0）
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
              // 标题栏
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
              
              // 内容区域
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
      itemCount: _periods.length + 3, // +3 for establishment date, data end date, and disclaimer
      itemBuilder: (context, index) {
        // 倒数第三行显示基金成立日期
        if (index == _periods.length) {
          return _buildEstablishmentDateRow(isDark);
        }
        // 倒数第二行显示数据截止日期
        if (index == _periods.length + 1) {
          return _buildDataEndDateRow(isDark);
        }
        // 最后一行显示免责声明
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
              '带*号为估算数据，仅供参考，实际收益以基金公司公布为准',
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

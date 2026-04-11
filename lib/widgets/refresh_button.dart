import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Material;
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import 'toast.dart';

/// 刷新按钮组件 - 封装刷新逻辑
class RefreshButton extends StatefulWidget {
  final DataManager dataManager;
  final FundService fundService;
  final VoidCallback? onRefreshStart;
  final VoidCallback? onRefreshComplete;
  final int maxConcurrentRequests;

  const RefreshButton({
    super.key,
    required this.dataManager,
    required this.fundService,
    this.onRefreshStart,
    this.onRefreshComplete,
    this.maxConcurrentRequests = 3,
  });

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton> {
  bool _isRefreshing = false;
  OverlayEntry? _loadingOverlayEntry;

  DateTime _getPreviousWorkday(DateTime date) {
    var result = DateTime(date.year, date.month, date.day);
    while (true) {
      result = result.subtract(const Duration(days: 1));
      final weekday = result.weekday;
      if (weekday >= 1 && weekday <= 5) {
        return result;
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<(String, FundHolding?)> _fetchHoldingWithRetry(FundHolding holding) async {
    var retryCount = 0;

    while (retryCount < 3) {
      final fundInfo = await widget.fundService.fetchFundInfo(holding.fundCode);
      final isValid = fundInfo['isValid'] as bool? ?? false;

      if (isValid) {
        final updatedHolding = holding.copyWith(
          fundName: fundInfo['fundName'] as String? ?? holding.fundName,
          currentNav: fundInfo['currentNav'] as double? ?? holding.currentNav,
          navDate: fundInfo['navDate'] as DateTime? ?? holding.navDate,
          isValid: true,
        );
        return (holding.id, updatedHolding);
      }

      retryCount++;
      if (retryCount < 3) {
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }

    return (holding.id, null);
  }

  void _showLoadingOverlay(BuildContext context) {
    _loadingOverlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CupertinoActivityIndicator(radius: 20),
                const SizedBox(height: 16),
                const Text(
                  '正在刷新基金数据...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '请稍候',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_loadingOverlayEntry!);
  }

  void _hideLoadingOverlay() {
    _loadingOverlayEntry?.remove();
    _loadingOverlayEntry = null;
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    widget.onRefreshStart?.call();

    if (mounted) {
      _showLoadingOverlay(context);
    }

    await widget.dataManager.addLog('开始刷新所有基金信息', type: LogType.info);

    final previousWorkday = _getPreviousWorkday(DateTime.now());
    final holdings = widget.dataManager.holdings;
    final totalCount = holdings.length;

    final needsRefreshHoldings = <FundHolding>[];
    for (final holding in holdings) {
      final isLatest = holding.isValid &&
          holding.currentNav > 0 &&
          _isSameDay(holding.navDate, previousWorkday);
      if (!isLatest) {
        needsRefreshHoldings.add(holding);
      }
    }

    var successCount = 0;
    var skipCount = totalCount - needsRefreshHoldings.length;
    var failCount = 0;

    if (needsRefreshHoldings.isNotEmpty) {
      final results = <(String, FundHolding?)>[];

      for (int i = 0; i < needsRefreshHoldings.length; i += widget.maxConcurrentRequests) {
        final end = (i + widget.maxConcurrentRequests < needsRefreshHoldings.length)
            ? i + widget.maxConcurrentRequests
            : needsRefreshHoldings.length;
        final batch = needsRefreshHoldings.sublist(i, end);

        final batchResults = await Future.wait(
            batch.map((holding) => _fetchHoldingWithRetry(holding))
        );
        results.addAll(batchResults);
      }

      for (final result in results) {
        final (id, updatedHolding) = result;
        if (updatedHolding != null) {
          await widget.dataManager.updateHolding(updatedHolding);
          successCount++;
        } else {
          failCount++;
        }
      }
    }

    await widget.dataManager.addLog(
      '刷新完成: 成功 $successCount, 跳过 $skipCount, 失败 $failCount',
      type: LogType.success,
    );

    _hideLoadingOverlay();

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
      widget.onRefreshComplete?.call();

      if (successCount > 0 || skipCount > 0) {
        context.showToast(
            '刷新完成: 成功 $successCount, 跳过 $skipCount${failCount > 0 ? ', 失败 $failCount' : ''}'
        );
      } else if (failCount > 0) {
        context.showToast('刷新失败，请检查网络');
      } else {
        context.showToast('所有数据已是最新');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: _isRefreshing ? null : _refresh,
      child: _isRefreshing
          ? const SizedBox(
        width: 22,
        height: 22,
        child: CupertinoActivityIndicator(),
      )
          : const Icon(CupertinoIcons.arrow_clockwise, size: 20),
    );
  }
}
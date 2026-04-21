import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Material;
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import 'toast.dart';

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

class _RefreshButtonState extends State<RefreshButton> with TickerProviderStateMixin {
  bool _isRefreshing = false;
  OverlayEntry? _loadingOverlayEntry;
  AnimationController? _fadeController;
  double _overlayOpacity = 0.0;

  bool _hasNoReturnData(FundHolding holding) {
    return holding.navReturn1m == null &&
        holding.navReturn3m == null &&
        holding.navReturn6m == null &&
        holding.navReturn1y == null;
  }

  Future<(String, FundHolding?)> _fetchHoldingWithRetry(FundHolding holding, {bool forceRefresh = false}) async {
    var retryCount = 0;

    while (retryCount < 3) {
      final fundInfo = await widget.fundService.fetchFundInfo(holding.fundCode, forceRefresh: forceRefresh);
      final isValid = fundInfo['isValid'] as bool? ?? false;

      if (isValid) {
        final updatedHolding = holding.copyWith(
          fundName: fundInfo['fundName'] as String? ?? holding.fundName,
          currentNav: fundInfo['currentNav'] as double? ?? holding.currentNav,
          navDate: fundInfo['navDate'] as DateTime? ?? holding.navDate,
          isValid: true,
          navReturn1m: fundInfo['navReturn1m'] as double?,
          navReturn3m: fundInfo['navReturn3m'] as double?,
          navReturn6m: fundInfo['navReturn6m'] as double?,
          navReturn1y: fundInfo['navReturn1y'] as double?,
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

  void _hideLoadingOverlay() {
    if (_fadeController != null) {
      _fadeController!.dispose();
      _fadeController = null;
    }
    if (_loadingOverlayEntry != null && _loadingOverlayEntry!.mounted) {
      _loadingOverlayEntry!.remove();
      _loadingOverlayEntry = null;
    }
    _overlayOpacity = 0.0;
  }

  void _showLoadingOverlay(BuildContext context, {String message = '刷新中...'}) {
    _hideLoadingOverlay();

    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final overlayColor = isDarkMode
        ? Colors.black.withOpacity(0.7 * _overlayOpacity)
        : Colors.black.withOpacity(0.3 * _overlayOpacity);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    )..addListener(() {
      _overlayOpacity = _fadeController!.value;
      if (_loadingOverlayEntry != null && _loadingOverlayEntry!.mounted) {
        _loadingOverlayEntry!.markNeedsBuild();
      }
    });

    _loadingOverlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: overlayColor,
        child: Center(
          child: Opacity(
            opacity: _overlayOpacity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1C1C1E).withOpacity(0.95)
                    : CupertinoColors.systemBackground,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(radius: 20),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.label,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_loadingOverlayEntry!);
    _fadeController!.forward();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    await _performRefresh(forceAll: false);
  }

  Future<void> _forceRefresh() async {
    if (_isRefreshing) return;
    await _performRefresh(forceAll: true);
  }

  Future<void> _performRefresh({required bool forceAll}) async {
    setState(() {
      _isRefreshing = true;
    });

    widget.onRefreshStart?.call();

    if (mounted) {
      _showLoadingOverlay(context, message: forceAll ? '强制刷新所有基金...' : '刷新中...');
    }

    await widget.dataManager.addLog(forceAll ? '开始强制刷新所有基金信息' : '开始刷新基金信息', type: LogType.info);

    final holdings = widget.dataManager.holdings;
    final totalCount = holdings.length;

    List<FundHolding> needsRefreshHoldings;
    if (forceAll) {
      needsRefreshHoldings = List.from(holdings);
    } else {
      needsRefreshHoldings = [];
      for (final holding in holdings) {
        if (_hasNoReturnData(holding)) {
          needsRefreshHoldings.add(holding);
        }
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
            batch.map((holding) => _fetchHoldingWithRetry(holding, forceRefresh: forceAll))
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
      forceAll
          ? '强制刷新完成: 成功 $successCount, 失败 $failCount'
          : '刷新完成: 成功 $successCount, 跳过 $skipCount, 失败 $failCount',
      type: LogType.success,
    );

    final overlayStartTime = DateTime.now();
    _hideLoadingOverlay();
    final elapsed = DateTime.now().difference(overlayStartTime);
    if (elapsed < const Duration(milliseconds: 500)) {
      await Future.delayed(Duration(milliseconds: 500 - elapsed.inMilliseconds));
    }

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
      widget.onRefreshComplete?.call();

      String message;
      if (forceAll) {
        message = '强制刷新完成: 成功 $successCount${failCount > 0 ? ', 失败 $failCount' : ''}';
      } else {
        if (successCount > 0) {
          message = '刷新完成: 成功更新 $successCount 支基金${failCount > 0 ? ', 失败 $failCount' : ''}';
        } else if (skipCount > 0 && skipCount == totalCount) {
          message = '所有基金已有收益率数据，无需刷新';
        } else if (skipCount > 0) {
          message = '已有收益率数据的基金已跳过，未发现需要更新的基金';
        } else if (failCount > 0) {
          message = '刷新失败，请检查网络';
        } else {
          message = '所有数据已是最新';
        }
      }
      context.showToast(message);
    }
  }

  @override
  void dispose() {
    _hideLoadingOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.dataManager.holdings.isNotEmpty;

    return GestureDetector(
      onLongPress: (hasData && !_isRefreshing) ? _forceRefresh : null,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: (hasData && !_isRefreshing) ? _refresh : null,
        child: _isRefreshing
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CupertinoActivityIndicator(),
        )
            : Icon(
          CupertinoIcons.arrow_clockwise,
          size: 20,
          color: hasData ? null : CupertinoColors.systemGrey3,
        ),
      ),
    );
  }
}
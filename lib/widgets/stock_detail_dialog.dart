import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'stock_candle_chart.dart';
import '../constants/app_constants.dart';
import '../services/stock_quote_service.dart';

class StockDetailDialog extends StatefulWidget {
  final String stockCode;
  final String stockName;

  const StockDetailDialog({
    super.key,
    required this.stockCode,
    required this.stockName,
  });

  @override
  State<StockDetailDialog> createState() => _StockDetailDialogState();
}

class _StockDetailDialogState extends State<StockDetailDialog> with TickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stockInfo;
  List<String> _klineData = [];
  Timer? _updateTimer;
  bool _isTradingTime = false;
  AnimationController? _priceAnimationController;
  double _previousPrice = 0;
  double _previousChangePercent = 0;
  
  final GlobalKey<StockCandleChartState> _candleChartKey = GlobalKey();
  
  @override
  void initState() {
    super.initState();
    _checkTradingTime();
    _loadStockData();
    _startAutoUpdate();

    _priceAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _priceAnimationController?.dispose();
    super.dispose();
  }

  void _checkTradingTime() {
    _isTradingTime = AppConstants.isInTradingHours();
  }

  void _startAutoUpdate() {
    _updateTimer?.cancel();
    // Only poll during trading hours; outside trading hours there is
    // nothing new to fetch, so skip the 5-second timer entirely.
    if (!_isTradingTime) return;

    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Double-check trading time on each tick — stop polling once
      // the market closes while the dialog is still open.
      if (!AppConstants.isInTradingHours()) {
        timer.cancel();
        _updateTimer = null;
        return;
      }
      _loadStockData(refreshOnly: true);
    });
  }

  Future<void> _loadStockData({bool refreshOnly = false}) async {
    if (!refreshOnly && mounted) {
      setState(() => _loading = true);
    }
    
    try {
      final infoFuture = _fetchStockInfo(widget.stockCode);
      
      final klineFuture = !refreshOnly ? _fetchKlineData(widget.stockCode) : Future.value(_klineData);
      
      final results = await Future.wait([infoFuture, klineFuture]);
      
      if (mounted) {
        setState(() {
          final newPrice = (results[0] as Map<String, dynamic>?)?['price'] ?? 0.0;
          final newChangePercent = (results[0] as Map<String, dynamic>?)?['changePercent'] ?? 0.0;
          
          if (_previousPrice != 0 && (newPrice != _previousPrice || newChangePercent != _previousChangePercent)) {
            _priceAnimationController?.forward(from: 0);
          }
          
          _previousPrice = newPrice;
          _previousChangePercent = newChangePercent;
          
          _stockInfo = results[0] as Map<String, dynamic>?;
          _klineData = results[1] as List<String>;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchStockInfo(String secid) async {
    return StockQuoteService.fetchStockInfo(secid, widget.stockName);
  }

  Future<List<String>> _fetchKlineData(String secid) async {
    final result = await StockQuoteService.fetchKlineData(secid);
    return result ?? [];
  }

  String _formatStockCode(String code) {
    if (code.startsWith('sh')) {
      return '沪A ${code.substring(2)}';
    } else if (code.startsWith('sz')) {
      return '深A ${code.substring(2)}';
    } else if (code.startsWith('hk')) {
      return '港股 ${code.substring(2)}';
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppConstants.isDark(context);
    final bgColor = isDark ? AppConstants.darkCardBg : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : AppConstants.darkBackground;
    final secondaryTextColor = isDark 
        ? CupertinoColors.white.withOpacity(0.6)
        : AppConstants.systemGray;

    return GestureDetector(
      onTap: () {
        _candleChartKey.currentState?.clearCrosshair();
      },
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          constraints: const BoxConstraints(maxWidth: 420),
          height: 520, 
          child: CupertinoPopupSurface(
            isSurfacePainted: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppConstants.darkBorder : CupertinoColors.systemGrey6,
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
                              widget.stockName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatStockCode(widget.stockCode),
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 0,
                        onPressed: () => Navigator.pop(context),
                        child: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 24,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                
                Expanded(
                  child: _loading
                      ? const Center(child: CupertinoActivityIndicator())
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  '加载失败',
                                  style: TextStyle(color: secondaryTextColor),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              physics: const BouncingScrollPhysics(), 
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildPriceCard(isDark, textColor, secondaryTextColor),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppConstants.darkBackground : CupertinoColors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark
                                            ? CupertinoColors.white.withOpacity(0.1)
                                            : CupertinoColors.systemGrey.withOpacity(0.2),
                                      ),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) => SizedBox(
                                        width: constraints.maxWidth,
                                        child: StockCandleChart(
                                          key: _candleChartKey,
                                          stockCode: widget.stockCode,
                                          isDark: isDark,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceCard(bool isDark, Color textColor, Color secondaryTextColor) {
    if (_stockInfo == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppConstants.darkBackground : CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? CupertinoColors.white.withOpacity(0.1)
                : CupertinoColors.systemGrey.withOpacity(0.2),
          ),
        ),
        child: const Center(
          child: Text('暂无行情数据'),
        ),
      );
    }

    final info = _stockInfo;
    if (info == null) {
      return const Center(child: Text('暂无行情数据'));
    }
    final price = info['price'] as double;
    final change = info['change'] as double;
    final changePercent = info['changePercent'] as double;
    final high = info['high'] as double;
    final low = info['low'] as double;
    final open = info['open'] as double;
    final prevClose = info['prevClose'] as double;

    Color changeColor;
    if (changePercent > 0) {
      changeColor = CupertinoColors.systemRed;
    } else if (changePercent < 0) {
      changeColor = CupertinoColors.systemGreen;
    } else {
      changeColor = CupertinoColors.systemGrey;
    }
    
    Color priceColor;
    if (price > prevClose) {
      priceColor = CupertinoColors.systemRed;
    } else if (price < prevClose) {
      priceColor = CupertinoColors.systemGreen;
    } else {
      priceColor = CupertinoColors.systemGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.darkBackground : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? CupertinoColors.white.withOpacity(0.1)
              : CupertinoColors.systemGrey.withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '最新价',
                  style: TextStyle(
                    fontSize: 11,
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedBuilder(
                  animation: _priceAnimationController ?? AlwaysStoppedAnimation(0),
                  builder: (context, child) {
                    final opacity = 1.0 - (sin(_priceAnimationController!.value * 3.14159) * 0.4);
                    
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          price.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: priceColor.withOpacity(opacity),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: changeColor.withOpacity(opacity),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCompactPriceItem('高', high, prevClose, secondaryTextColor),
                    _buildCompactPriceItem('开', open, prevClose, secondaryTextColor),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCompactPriceItem('低', low, prevClose, secondaryTextColor),
                    _buildCompactInfoItem('昨', prevClose.toStringAsFixed(2), secondaryTextColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, Color secondaryTextColor) {
    return Column(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceItem(String label, double price, double prevClose, Color secondaryTextColor) {
    Color priceColor;
    if (price > prevClose) {
      priceColor = CupertinoColors.systemRed;  
    } else if (price < prevClose) {
      priceColor = CupertinoColors.systemGreen;  
    } else {
      priceColor = secondaryTextColor;  
    }

    return Column(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          price.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: priceColor,
          ),
        ),
      ],
    );
  }
  
  Widget _buildCompactPriceItem(String label, double price, double prevClose, Color secondaryTextColor) {
    Color priceColor;
    if (price > prevClose) {
      priceColor = CupertinoColors.systemRed;
    } else if (price < prevClose) {
      priceColor = CupertinoColors.systemGreen;
    } else {
      priceColor = secondaryTextColor;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          price.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: priceColor,
          ),
        ),
      ],
    );
  }
  
  Widget _buildCompactInfoItem(String label, String value, Color secondaryTextColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: secondaryTextColor,
          ),
        ),
      ],
    );
  }
}

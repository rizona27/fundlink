import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'stock_candle_chart.dart';

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
  
  bool _candleChartInitialized = false;

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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _candleChartInitialized = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _priceAnimationController?.dispose();
    super.dispose();
  }

  void _checkTradingTime() {
    final now = DateTime.now();
    final weekday = now.weekday; 
    
    if (weekday >= 1 && weekday <= 5) {
      final hour = now.hour;
      final minute = now.minute;
      final currentTime = hour * 60 + minute;
      
      final morningStart = 9 * 60 + 30;  
      final morningEnd = 11 * 60 + 30;   
      final afternoonStart = 13 * 60;     
      final afternoonEnd = 15 * 60;       
      
      _isTradingTime = (currentTime >= morningStart && currentTime <= morningEnd) ||
                       (currentTime >= afternoonStart && currentTime <= afternoonEnd);
    } else {
      _isTradingTime = false;
    }
  }

  void _startAutoUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _loadStockData(refreshOnly: true);
      }
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
    try {
      String formattedSecid = secid;
      if (secid.startsWith('sh')) {
        formattedSecid = '1.${secid.substring(2)}';
      } else if (secid.startsWith('sz')) {
        formattedSecid = '0.${secid.substring(2)}';
      } else if (secid.startsWith('hk')) {
        formattedSecid = '116.${secid.substring(2)}';
      }
      
      final url = Uri.parse(
        'https://push2.eastmoney.com/api/qt/stock/get'
        '?secid=$formattedSecid'
        '&ut=b2884a393a59ad64002292a3e90d46a5'
        '&fields=f43,f57,f58,f169,f170,f46,f44,f51,f168,f47,f164,f163,f116,f60,f45,f52,f50,f48,f167,f117,f71,f161,f49,f530',
      );
      
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        
        final data = json['data'];
        if (data != null) {
          return {
            'name': data['f57'] ?? widget.stockName,
            'code': data['f58'] ?? '',
            'price': (data['f43'] ?? 0).toDouble() / 100,  
            'change': (data['f169'] ?? 0).toDouble() / 100,  
            'changePercent': (data['f170'] ?? 0).toDouble() / 100,  
            'high': (data['f44'] ?? 0).toDouble() / 100,  
            'low': (data['f45'] ?? 0).toDouble() / 100,  
            'open': (data['f46'] ?? 0).toDouble() / 100,  
            'prevClose': (data['f60'] ?? 0).toDouble() / 100,  
            'volume': (data['f47'] ?? 0).toInt(),
            'amount': (data['f48'] ?? 0).toDouble(),
          };
        } else {
          return null;
        }
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> _fetchKlineData(String secid) async {
    try {
      String formattedSecid = secid;
      if (secid.startsWith('sh')) {
        formattedSecid = '1.${secid.substring(2)}';
      } else if (secid.startsWith('sz')) {
        formattedSecid = '0.${secid.substring(2)}';
      } else if (secid.startsWith('hk')) {
        formattedSecid = '116.${secid.substring(2)}';
      }
      
      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$formattedSecid'
        '&klt=101'  
        '&fqt=1'    
        '&beg=0'    
        '&end=20500101'  
        '&lmt=100'  
        '&fields1=f1,f2,f3,f4,f5,f6'
        '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'
        '&ut=b2884a393a59ad64002292a3e90d46a5',
      );
      
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        
        final data = json['data'];
        if (data != null && data['klines'] != null) {
          final klines = List<String>.from(data['klines']);
          return klines;
        } else {
          return [];
        }
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
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
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDark 
        ? CupertinoColors.white.withOpacity(0.6)
        : const Color(0xFF8E8E93);

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
                    color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
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
                                  if (_candleChartInitialized)
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isDark
                                              ? CupertinoColors.white.withOpacity(0.1)
                                              : CupertinoColors.systemGrey.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          StockCandleChart(
                                            key: _candleChartKey,
                                            stockCode: widget.stockCode,
                                            isDark: isDark,
                                          ),
                                        ],
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
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
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

    final price = _stockInfo!['price'] as double;
    final change = _stockInfo!['change'] as double;
    final changePercent = _stockInfo!['changePercent'] as double;
    final high = _stockInfo!['high'] as double;
    final low = _stockInfo!['low'] as double;
    final open = _stockInfo!['open'] as double;
    final prevClose = _stockInfo!['prevClose'] as double;

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
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
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

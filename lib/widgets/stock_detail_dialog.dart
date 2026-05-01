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
  
  // 蜡烛图Key，用于清除十字线
  final GlobalKey<StockCandleChartState> _candleChartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkTradingTime();
    _loadStockData();
    _startAutoUpdate();
    
    // 初始化呼吸动画
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

  /// 检查当前是否为交易时间
  void _checkTradingTime() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Monday, 7=Sunday
    
    // 判断是否为工作日（周一到周五）
    if (weekday >= 1 && weekday <= 5) {
      final hour = now.hour;
      final minute = now.minute;
      final currentTime = hour * 60 + minute;
      
      // 交易时间：9:30-11:30, 13:00-15:00
      final morningStart = 9 * 60 + 30;  // 9:30
      final morningEnd = 11 * 60 + 30;   // 11:30
      final afternoonStart = 13 * 60;     // 13:00
      final afternoonEnd = 15 * 60;       // 15:00
      
      _isTradingTime = (currentTime >= morningStart && currentTime <= morningEnd) ||
                       (currentTime >= afternoonStart && currentTime <= afternoonEnd);
    } else {
      _isTradingTime = false;
    }
  }

  /// 启动自动更新（无论是否交易时间，都每5秒刷新）
  void _startAutoUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _loadStockData(refreshOnly: true);
      }
    });
  }

  Future<void> _loadStockData({bool refreshOnly = false}) async {
    if (!refreshOnly) {
      setState(() => _loading = true);
    }
    
    try {
      // 获取实时行情
      final infoFuture = _fetchStockInfo(widget.stockCode);
      
      // 获取K线数据（只在首次加载时获取）
      final klineFuture = !refreshOnly ? _fetchKlineData(widget.stockCode) : Future.value(_klineData);
      
      final results = await Future.wait([infoFuture, klineFuture]);
      
      if (mounted) {
        setState(() {
          // 检测价格变化，触发动画
          final newPrice = (results[0] as Map<String, dynamic>?)?['price'] ?? 0.0;
          final newChangePercent = (results[0] as Map<String, dynamic>?)?['changePercent'] ?? 0.0;
          
          if (_previousPrice != 0 && (newPrice != _previousPrice || newChangePercent != _previousChangePercent)) {
            // 价格或涨跌幅变化，触发呼吸动画
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
      // 转换股票代码格式：sh600519 -> 1.600519, sz000001 -> 0.000001
      String formattedSecid = secid;
      if (secid.startsWith('sh')) {
        formattedSecid = '1.${secid.substring(2)}';
      } else if (secid.startsWith('sz')) {
        formattedSecid = '0.${secid.substring(2)}';
      } else if (secid.startsWith('hk')) {
        formattedSecid = '116.${secid.substring(2)}';
      }
      
      // 使用东方财富实时行情API
      final url = Uri.parse(
        'https://push2.eastmoney.com/api/qt/stock/get'
        '?secid=$formattedSecid'
        '&ut=b2884a393a59ad64002292a3e90d46a5'
        '&fields=f43,f57,f58,f169,f170,f46,f44,f51,f168,f47,f164,f163,f116,f60,f45,f52,f50,f48,f167,f117,f71,f161,f49,f530',
      );
      
      print('请求股票行情: $url');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        print('行情响应: ${json.toString().substring(0, json.toString().length > 200 ? 200 : json.toString().length)}');
        
        final data = json['data'];
        if (data != null) {
          // 东方财富API返回的价格单位是分，需要除以100转换为元
          // f170涨跌幅是百分比*100，需要除以100
          return {
            'name': data['f57'] ?? widget.stockName,
            'code': data['f58'] ?? '',
            'price': (data['f43'] ?? 0).toDouble() / 100,  // 分转元
            'change': (data['f169'] ?? 0).toDouble() / 100,  // 分转元
            'changePercent': (data['f170'] ?? 0).toDouble() / 100,  // 百分比*100转百分比
            'high': (data['f44'] ?? 0).toDouble() / 100,  // 分转元
            'low': (data['f45'] ?? 0).toDouble() / 100,  // 分转元
            'open': (data['f46'] ?? 0).toDouble() / 100,  // 分转元
            'prevClose': (data['f60'] ?? 0).toDouble() / 100,  // 分转元
            'volume': (data['f47'] ?? 0).toInt(),
            'amount': (data['f48'] ?? 0).toDouble(),
          };
        } else {
          print('行情数据为空');
          return null;
        }
      } else {
        print('行情请求失败，状态码: ${res.statusCode}');
        return null;
      }
    } catch (e) {
      print('获取股票行情失败: $e');
      return null;
    }
  }

  Future<List<String>> _fetchKlineData(String secid) async {
    try {
      // 转换股票代码格式：sh600519 -> 1.600519, sz000001 -> 0.000001
      String formattedSecid = secid;
      if (secid.startsWith('sh')) {
        formattedSecid = '1.${secid.substring(2)}';
      } else if (secid.startsWith('sz')) {
        formattedSecid = '0.${secid.substring(2)}';
      } else if (secid.startsWith('hk')) {
        formattedSecid = '116.${secid.substring(2)}';
      }
      
      // 使用东方财富K线API（日K线）
      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$formattedSecid'
        '&klt=101'  // 101=日K线
        '&fqt=1'    // 1=前复权
        '&beg=0'    // 开始日期（0表示最早）
        '&end=20500101'  // 结束日期
        '&lmt=100'  // 限制返回100条
        '&fields1=f1,f2,f3,f4,f5,f6'
        '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'
        '&ut=b2884a393a59ad64002292a3e90d46a5',
      );
      
      print('请求K线数据: $url');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        print('K线响应: ${json.toString().substring(0, json.toString().length > 200 ? 200 : json.toString().length)}');
        
        // 安全检查数据结构
        final data = json['data'];
        if (data != null && data['klines'] != null) {
          final klines = List<String>.from(data['klines']);
          print('成功获取 ${klines.length} 条K线数据');
          return klines;
        } else {
          print('K线数据为空或结构错误: data=$data');
          return [];
        }
      } else {
        print('K线请求失败，状态码: ${res.statusCode}');
        return [];
      }
    } catch (e) {
      print('获取K线数据失败: $e');
      return [];
    }
  }

  /// 格式化股票代码显示
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
      // 点击弹窗外部区域时清除十字线
      onTap: () {
        _candleChartKey.currentState?.clearCrosshair();
      },
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          constraints: const BoxConstraints(maxWidth: 420),
          height: 520, // 固定弹窗高度
          child: CupertinoPopupSurface(
            isSurfacePainted: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题栏
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
                
                // 内容区域（固定高度，内部可滚动）
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
                              physics: const BouncingScrollPhysics(), // 允许滚动
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildPriceCard(isDark, textColor, secondaryTextColor),
                                  const SizedBox(height: 10),
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

    // 涨跌幅颜色：红涨绿跌
    Color changeColor;
    if (changePercent > 0) {
      changeColor = CupertinoColors.systemRed;
    } else if (changePercent < 0) {
      changeColor = CupertinoColors.systemGreen;
    } else {
      changeColor = CupertinoColors.systemGrey;
    }
    
    // 最新价颜色：高于昨收价红色，低于绿色，等于灰色
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
          // 左侧：最新价和涨跌幅
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
                    // 呼吸效果：透明度从1.0 -> 0.6 -> 1.0
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
          
          // 右侧：高/开、低/昨 两行布局
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：高、开
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCompactPriceItem('高', high, prevClose, secondaryTextColor),
                    _buildCompactPriceItem('开', open, prevClose, secondaryTextColor),
                  ],
                ),
                const SizedBox(height: 6),
                // 第二行：低、昨（与左侧价格基线对齐）
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

  /// 构建价格项，根据与昨收价的比较着色
  Widget _buildPriceItem(String label, double price, double prevClose, Color secondaryTextColor) {
    Color priceColor;
    if (price > prevClose) {
      priceColor = CupertinoColors.systemRed;  // 高于昨收，红色
    } else if (price < prevClose) {
      priceColor = CupertinoColors.systemGreen;  // 低于昨收，绿色
    } else {
      priceColor = secondaryTextColor;  // 等于昨收，灰色
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
  
  /// 构建紧凑价格项（水平排列）
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
  
  /// 构建紧凑信息项（水平排列）
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

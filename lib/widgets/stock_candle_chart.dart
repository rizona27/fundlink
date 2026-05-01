import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// K线数据模型
class CandleData {
  final String date;
  final double open;
  final double close;
  final double high;
  final double low;
  final double volume;

  CandleData({
    required this.date,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
  });

  bool get isBullish => close >= open;
  
  Color get bodyColor => isBullish 
      ? CupertinoColors.systemRed 
      : CupertinoColors.systemGreen;
}

class StockCandleChart extends StatefulWidget {
  final String stockCode;
  final bool isDark;

  const StockCandleChart({
    super.key,
    required this.stockCode,
    required this.isDark,
  });

  @override
  State<StockCandleChart> createState() => StockCandleChartState();
}

class StockCandleChartState extends State<StockCandleChart> {
  String _selectedPeriod = 'day'; // day, week, month
  final Map<String, String> _periodLabels = {
    'day': '日K',
    'week': '周K',
    'month': '月K',
  };

  List<CandleData> _candleDataList = [];
  bool _isLoading = false;
  
  // 十字交叉线相关
  int _selectedIndex = -1;
  bool _isPanning = false; // 是否正在平移
  
  // 懒加载相关
  DateTime? _earliestDate; // 最早日期，用于加载更多
  int _displayOffset = 0; // 显示偏移量，0表示显示最新数据，正数表示向左偏移
  
  // 动态价格范围
  double _visibleMinPrice = 0;
  double _visibleMaxPrice = 0;
  
  // 常量
  static const int visibleCandleCount = 45; // 默认显示45根蜡烛
  
  // 加载阶段标记
  bool _hasLoadedInitial = false;  // 是否已加载初始数据
  bool _hasPreloaded = false;      // 是否已预加载历史数据
  
  /// 根据周期获取可见蜡烛数量（周K和月K更粗）
  int get _actualVisibleCount {
    switch (_selectedPeriod) {
      case 'day':
        return 45;  // 日K标准宽度
      case 'week':
        return 35;  // 周K稍粗（35条铺满屏幕）
      case 'month':
        return 25;  // 月K更粗（25条铺满屏幕）
      default:
        return 45;
    }
  }

  @override
  void initState() {
    super.initState();
    // 阶段1: 先尝试从缓存加载
    _loadFromCache().then((_) {
      // 阶段2: 然后加载最新的视口数据
      _loadInitialData();
    });
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  /// 清除十字交叉线（供外部调用）
  void clearCrosshair() {
    if (_selectedIndex != -1) {
      setState(() {
        _selectedIndex = -1;
      });
    }
  }
  
  /// 生成缓存key
  String _getCacheKey() {
    return 'candle_cache_${widget.stockCode}_$_selectedPeriod';
  }
  
  /// 阶段1: 从缓存加载历史数据
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey();
      final cachedData = prefs.getString(cacheKey);
      
      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(cachedData);
        final cachedCandles = jsonList.map((json) => CandleData(
          date: json['date'] as String,
          open: (json['open'] as num).toDouble(),
          close: (json['close'] as num).toDouble(),
          high: (json['high'] as num).toDouble(),
          low: (json['low'] as num).toDouble(),
          volume: (json['volume'] as num).toDouble(),
        )).toList();
        
        if (cachedCandles.isNotEmpty) {
          print('✅ 从缓存加载 ${cachedCandles.length} 条K线数据');
          setState(() {
            _candleDataList = cachedCandles;
            _earliestDate = DateTime.parse(cachedCandles.first.date);
            _displayOffset = cachedCandles.length > _actualVisibleCount
                ? cachedCandles.length - _actualVisibleCount
                : 0;
            _hasLoadedInitial = true;
          });
        }
      } else {
        print('⚠️ 无缓存数据');
      }
    } catch (e) {
      print('❌ 缓存加载失败: $e');
    }
  }
  
  /// 阶段2: 加载最新的视口数据（增量更新）
  Future<void> _loadInitialData() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      // 只请求最近的数据用于增量更新
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 60)); // 最近60天
      
      final begDate = '${startDate.year}${startDate.month.toString().padLeft(2, '0')}${startDate.day.toString().padLeft(2, '0')}';
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      
      String formattedSecid = widget.stockCode;
      if (widget.stockCode.startsWith('sh')) {
        formattedSecid = '1.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('sz')) {
        formattedSecid = '0.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('hk')) {
        formattedSecid = '116.${widget.stockCode.substring(2)}';
      }
      
      int klt;
      switch (_selectedPeriod) {
        case 'day':
          klt = 101;
          break;
        case 'week':
          klt = 102;
          break;
        case 'month':
          klt = 103;
          break;
        default:
          klt = 101;
      }
      
      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$formattedSecid'
        '&klt=$klt'
        '&fqt=0'
        '&beg=$begDate'
        '&end=$endDate'
        '&lmt=100'
        '&fields1=f1,f2,f3,f4,f5,f6'
        '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'
        '&ut=b2884a393a59ad64002292a3e90d46a5',
      );
      
      print('🔄 加载最新数据: $url');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'];
        
        if (data != null && data['klines'] != null) {
          final klines = List<String>.from(data['klines']);
          final newCandles = <CandleData>[];
          
          for (final line in klines) {
            final parts = line.split(',');
            if (parts.length >= 6) {
              newCandles.add(CandleData(
                date: parts[0],
                open: double.tryParse(parts[1]) ?? 0,
                close: double.tryParse(parts[2]) ?? 0,
                high: double.tryParse(parts[3]) ?? 0,
                low: double.tryParse(parts[4]) ?? 0,
                volume: double.tryParse(parts[5]) ?? 0,
              ));
            }
          }
          
          if (newCandles.isNotEmpty) {
            print('✅ 获取到 ${newCandles.length} 条新数据');
            
            // 合并缓存数据和新数据（去重）
            final mergedList = _mergeCandleData(_candleDataList, newCandles);
            
            setState(() {
              _candleDataList = mergedList;
              _earliestDate = DateTime.parse(mergedList.first.date);
              _displayOffset = mergedList.length > _actualVisibleCount
                  ? mergedList.length - _actualVisibleCount
                  : 0;
              _hasLoadedInitial = true;
            });
            
            // 保存到缓存
            _saveToCache(mergedList);
            
            // 阶段3: 后台预加载更多历史数据
            _preloadMoreHistory();
          }
        }
      }
    } catch (e) {
      print('❌ 加载最新数据失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  /// 阶段3: 后台预加载更多历史数据（用户无感）
  Future<void> _preloadMoreHistory() async {
    if (_hasPreloaded || _earliestDate == null) return;
    
    print('📥 后台预加载历史数据...');
    
    try {
      String formattedSecid = widget.stockCode;
      if (widget.stockCode.startsWith('sh')) {
        formattedSecid = '1.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('sz')) {
        formattedSecid = '0.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('hk')) {
        formattedSecid = '116.${widget.stockCode.substring(2)}';
      }
      
      int klt;
      int loadCount;
      switch (_selectedPeriod) {
        case 'day':
          klt = 101;
          loadCount = 200;  // 预加载200天
          break;
        case 'week':
          klt = 102;
          loadCount = 150;  // 预加载150周
          break;
        case 'month':
          klt = 103;
          loadCount = 120;  // 预加载120个月
          break;
        default:
          klt = 101;
          loadCount = 200;
      }
      
      final newStartDate = _earliestDate!.subtract(
        _selectedPeriod == 'day' 
            ? Duration(days: loadCount)
            : _selectedPeriod == 'week'
                ? Duration(days: loadCount * 7)
                : Duration(days: loadCount * 30),
      );
      
      final endDate = _earliestDate!.subtract(const Duration(days: 1));
      final begDate = '${newStartDate.year}${newStartDate.month.toString().padLeft(2, '0')}${newStartDate.day.toString().padLeft(2, '0')}';
      final endDateStr = '${endDate.year}${endDate.month.toString().padLeft(2, '0')}${endDate.day.toString().padLeft(2, '0')}';
      
      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$formattedSecid'
        '&klt=$klt'
        '&fqt=0'
        '&beg=$begDate'
        '&end=$endDateStr'
        '&lmt=$loadCount'
        '&fields1=f1,f2,f3,f4,f5,f6'
        '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'
        '&ut=b2884a393a59ad64002292a3e90d46a5',
      );
      
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'];
        
        if (data != null && data['klines'] != null) {
          final klines = List<String>.from(data['klines']);
          final historyCandles = <CandleData>[];
          
          for (final line in klines) {
            final parts = line.split(',');
            if (parts.length >= 6) {
              historyCandles.add(CandleData(
                date: parts[0],
                open: double.tryParse(parts[1]) ?? 0,
                close: double.tryParse(parts[2]) ?? 0,
                high: double.tryParse(parts[3]) ?? 0,
                low: double.tryParse(parts[4]) ?? 0,
                volume: double.tryParse(parts[5]) ?? 0,
              ));
            }
          }
          
          if (historyCandles.isNotEmpty) {
            print('✅ 预加载 ${historyCandles.length} 条历史数据');
            
            final mergedList = _mergeCandleData(historyCandles, _candleDataList);
            
            setState(() {
              _candleDataList = mergedList;
              _earliestDate = DateTime.parse(mergedList.first.date);
              _displayOffset += historyCandles.length;
              _hasPreloaded = true;
            });
            
            // 更新缓存
            _saveToCache(mergedList);
          }
        }
      }
    } catch (e) {
      print('❌ 预加载失败: $e');
    }
  }
  
  /// 合并K线数据（去重）
  List<CandleData> _mergeCandleData(List<CandleData> existing, List<CandleData> newData) {
    if (existing.isEmpty) return newData;
    if (newData.isEmpty) return existing;
    
    // 使用Map去重（以日期为key）
    final Map<String, CandleData> mergedMap = {};
    
    // 先加入现有数据
    for (final candle in existing) {
      mergedMap[candle.date] = candle;
    }
    
    // 再加入新数据（覆盖重复的）
    for (final candle in newData) {
      mergedMap[candle.date] = candle;
    }
    
    // 转换为列表并按日期排序
    final mergedList = mergedMap.values.toList();
    mergedList.sort((a, b) => a.date.compareTo(b.date));
    
    return mergedList;
  }
  
  /// 保存数据到缓存
  Future<void> _saveToCache(List<CandleData> candles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey();
      
      final jsonList = candles.map((c) => {
        'date': c.date,
        'open': c.open,
        'close': c.close,
        'high': c.high,
        'low': c.low,
        'volume': c.volume,
      }).toList();
      
      await prefs.setString(cacheKey, jsonEncode(jsonList));
      print('💾 已缓存 ${candles.length} 条K线数据');
    } catch (e) {
      print('❌ 缓存保存失败: $e');
    }
  }

  Future<void> _loadData({int retryCount = 0}) async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);

    try {
      String formattedSecid = widget.stockCode;
      if (widget.stockCode.startsWith('sh')) {
        formattedSecid = '1.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('sz')) {
        formattedSecid = '0.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('hk')) {
        formattedSecid = '116.${widget.stockCode.substring(2)}';
      }

      // 根据周期设置K线类型和加载条数
      int klt;
      int lmt; // 加载条数限制（初始加载）
      int preloadLmt; // 预加载条数（后台加载更早数据）
      
      switch (_selectedPeriod) {
        case 'day':
          klt = 101; // 日K
          lmt = 45;  // 初始显示45个交易日
          preloadLmt = 120;  // 预加载120天（约半年交易日）
          break;
        case 'week':
          klt = 102; // 周K
          lmt = 35;  // 初始显示35周
          preloadLmt = 100;  // 预加载100周（约2年）
          break;
        case 'month':
          klt = 103; // 月K
          lmt = 25;  // 初始显示25个月
          preloadLmt = 72;  // 预加载72个月（6年）
          break;
        default:
          klt = 101;
          lmt = 45;
          preloadLmt = 120;
      }

      // 初始加载时获取全部可用数据（不限制日期范围）
      final begDate = '0';  // 从最早开始
      final endDate = '20500101';  // 到未来

      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$formattedSecid'
        '&klt=$klt'
        '&fqt=0'  // 不复权，显示真实股价
        '&beg=$begDate'
        '&end=$endDate'
        '&lmt=$preloadLmt'  // 使用预加载数量，获取更多历史数据
        '&fields1=f1,f2,f3,f4,f5,f6'
        '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'
        '&ut=b2884a393a59ad64002292a3e90d46a5',
      );

      print('请求K线数据 (尝试 ${retryCount + 1}/3): $url');
      
      // 增加超时时间到15秒，适应慢速网络
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'];
        
        if (data != null && data['klines'] != null) {
          final klines = List<String>.from(data['klines']);
          final candles = <CandleData>[];
          
          for (final line in klines) {
            final parts = line.split(',');
            if (parts.length >= 6) {
              candles.add(CandleData(
                date: parts[0],
                open: double.tryParse(parts[1]) ?? 0,
                close: double.tryParse(parts[2]) ?? 0,
                high: double.tryParse(parts[3]) ?? 0,
                low: double.tryParse(parts[4]) ?? 0,
                volume: double.tryParse(parts[5]) ?? 0,
              ));
            }
          }

          if (candles.isNotEmpty) {
            print('成功加载 ${candles.length} 条K线数据');
            // API返回的是从旧到新，不需要反转
            setState(() {
              _candleDataList = candles;
              // 记录最早日期，用于懒加载
              if (candles.isNotEmpty) {
                final firstDate = candles.first.date;
                _earliestDate = DateTime.parse(firstDate);
                // 初始显示最新的数据（offset指向末尾）
                _displayOffset = candles.length > _actualVisibleCount 
                    ? candles.length - _actualVisibleCount 
                    : 0;
              }
            });
          } else {
            print('警告: K线数据为空');
            // 重试机制
            if (retryCount < 2) {
              print('准备重试...');
              await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
              await _loadData(retryCount: retryCount + 1);
              return;
            }
          }
        } else {
          print('警告: API返回数据格式错误');
          // 重试机制
          if (retryCount < 2) {
            print('准备重试...');
            await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
            await _loadData(retryCount: retryCount + 1);
            return;
          }
        }
      } else {
        print('警告: HTTP请求失败，状态码: ${res.statusCode}');
        // 重试机制
        if (retryCount < 2) {
          print('准备重试...');
          await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
          await _loadData(retryCount: retryCount + 1);
          return;
        }
      }
    } catch (e) {
      print('加载K线数据失败: $e');
      // 网络错误或超时，重试机制
      if (retryCount < 2) {
        print('网络错误，准备重试...');
        await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
        await _loadData(retryCount: retryCount + 1);
        return;
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onPeriodChanged(String period) {
    if (_selectedPeriod == period) return;
    setState(() {
      _selectedPeriod = period;
      // 不清空数据，保持显示直到新数据加载完成
      _selectedIndex = -1;
      // 注意：不重置 _displayOffset，等待 _loadData() 重新计算
    });
    _loadData();
  }
  
  double _calculateCrosshairY(int index, double minPrice, double maxPrice, double chartHeight) {
    if (index < 0 || index >= _candleDataList.length) return 0;
    final candle = _candleDataList[index];
    final priceRange = maxPrice - minPrice;
    if (priceRange <= 0) return chartHeight / 2;
    final normalizedY = (candle.close - minPrice) / priceRange;
    return chartHeight * (1 - normalizedY);
  }
  
  /// 计算当前视口内的价格范围
  void _calculateVisiblePriceRange(
    int offset, 
    int visibleCount,
    List<CandleData> candles,
  ) {
    if (candles.isEmpty) {
      _visibleMinPrice = 0;
      _visibleMaxPrice = 0;
      return;
    }
    
    // 计算可见的起始和结束索引
    final startIndex = offset;
    final endIndex = (offset + visibleCount).clamp(0, candles.length - 1);
    
    // 提取可见范围内的蜡烛
    final visibleCandles = candles.sublist(startIndex, endIndex + 1);
    
    if (visibleCandles.isEmpty) {
      _visibleMinPrice = 0;
      _visibleMaxPrice = 0;
      return;
    }
    
    // 计算可见范围内的最高价和最低价
    _visibleMinPrice = visibleCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    _visibleMaxPrice = visibleCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    
    // 添加5%的边距
    final priceRange = _visibleMaxPrice - _visibleMinPrice;
    _visibleMinPrice -= priceRange * 0.05;
    _visibleMaxPrice += priceRange * 0.05;
  }
  
  /// 加载更多历史数据（向左拖动时）
  Future<void> _loadMoreHistory() async {
    if (_isLoading || _earliestDate == null) return;
    
    // 注意：这里不设置 _isLoading = true，避免显示转圈动画

    try {
      String formattedSecid = widget.stockCode;
      if (widget.stockCode.startsWith('sh')) {
        formattedSecid = '1.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('sz')) {
        formattedSecid = '0.${widget.stockCode.substring(2)}';
      } else if (widget.stockCode.startsWith('hk')) {
        formattedSecid = '116.${widget.stockCode.substring(2)}';
      }

      int klt;
      int loadCount; // 每次增量加载的数量
      
      switch (_selectedPeriod) {
        case 'day':
          klt = 101;
          loadCount = 45;  // 每次加载45天（与视口一致）
          break;
        case 'week':
          klt = 102;
          loadCount = 35;  // 每次加载35周（与视口一致）
          break;
        case 'month':
          klt = 103;
          loadCount = 25;  // 每次加载25个月（与视口一致）
          break;
        default:
          klt = 101;
          loadCount = 45;
      }

      // 计算新的开始日期（往前推一个视口的时间）
      final newStartDate = _earliestDate!.subtract(
        _selectedPeriod == 'day' 
            ? Duration(days: loadCount)
            : _selectedPeriod == 'week'
                ? Duration(days: loadCount * 7)
                : Duration(days: loadCount * 30),
      );
      
      // endDate 设置为最早日期的前一天，避免数据重叠
      final endDate = _earliestDate!.subtract(const Duration(days: 1));
      
      final begDate = '${newStartDate.year}${newStartDate.month.toString().padLeft(2, '0')}${newStartDate.day.toString().padLeft(2, '0')}';
      final endDateStr = '${endDate.year}${endDate.month.toString().padLeft(2, '0')}${endDate.day.toString().padLeft(2, '0')}';

      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$formattedSecid'
        '&klt=$klt'
        '&fqt=0'  // 不复权，显示真实股价
        '&beg=$begDate'
        '&end=$endDateStr'
        '&lmt=$loadCount'  // 增量加载一个视口的数据
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
          final newCandles = <CandleData>[];
          
          for (final line in klines) {
            final parts = line.split(',');
            if (parts.length >= 6) {
              newCandles.add(CandleData(
                date: parts[0],
                open: double.tryParse(parts[1]) ?? 0,
                close: double.tryParse(parts[2]) ?? 0,
                high: double.tryParse(parts[3]) ?? 0,
                low: double.tryParse(parts[4]) ?? 0,
                volume: double.tryParse(parts[5]) ?? 0,
              ));
            }
          }

          // 将新数据添加到现有数据前面（需要去重）
          if (newCandles.isNotEmpty) {
            setState(() {
              // 过滤掉与已有数据重复的日期
              final existingDates = _candleDataList.map((c) => c.date).toSet();
              final uniqueNewCandles = newCandles.where((c) => !existingDates.contains(c.date)).toList();
              
              if (uniqueNewCandles.isNotEmpty) {
                _candleDataList = [...uniqueNewCandles, ..._candleDataList];
                _earliestDate = DateTime.parse(uniqueNewCandles.first.date);
                // 更新偏移量，保持当前视图位置
                _displayOffset += uniqueNewCandles.length;
                
                // 保存更新后的数据到缓存
                _saveToCache(_candleDataList);
              }
            });
          }
        }
      }
    } catch (e) {
      print('加载历史数据失败: $e');
    }
    // 注意：这里不设置 _isLoading = false，因为根本没设置为true
  }

  @override
  Widget build(BuildContext context) {
    // 只在首次加载且无数据时显示加载指示器
    if (_isLoading && _candleDataList.isEmpty && _earliestDate == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    if (_candleDataList.isEmpty) {
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

    // 计算全局最大成交量（用于所有数据）
    double maxVolume = _candleDataList.map((c) => c.volume).reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        // 周期选择器
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _periodLabels.keys.map((key) {
              final isSelected = _selectedPeriod == key;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => _onPeriodChanged(key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                            ? (widget.isDark ? CupertinoColors.white : CupertinoColors.black)
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

        // K线图表
        SizedBox(
          height: 200,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = constraints.maxWidth;
              final chartHeight = constraints.maxHeight;
              
              // 计算可见的数据范围
              final totalCandles = _candleDataList.length;
              final int maxOffset = totalCandles > _actualVisibleCount ? totalCandles - _actualVisibleCount : 0;
              final int actualOffset = _displayOffset.clamp(0, maxOffset);
              
              // 计算当前视口内的动态价格范围
              _calculateVisiblePriceRange(actualOffset, _actualVisibleCount, _candleDataList);
              final minPrice = _visibleMinPrice;
              final maxPrice = _visibleMaxPrice;
              
              // 根据周期使用不同的可见数量（周K和月K更粗）
              final barWidth = chartWidth / _actualVisibleCount;
              
              return Stack(
                children: [
                  // 背景网格和坐标轴
                  CustomPaint(
                    painter: _GridPainter(
                      minPrice: minPrice,
                      maxPrice: maxPrice,
                      isDark: widget.isDark,
                      candleDataList: _candleDataList,
                      selectedPeriod: _selectedPeriod,
                      selectedIndex: _selectedIndex,
                      displayOffset: actualOffset,
                      visibleCount: _actualVisibleCount,  // 使用周期对应的可见数量
                    ),
                    size: Size(chartWidth, chartHeight),
                  ),
                  
                  // 蜡烛图（无需平移，Painter已只绘制可见部分）
                  ClipRect(  // 裁剪超出边界的部凈
                    child: CustomPaint(
                      painter: _CandleChartPainter(
                        candles: _candleDataList,
                        minPrice: minPrice,
                        maxPrice: maxPrice,
                        selectedIndex: _selectedIndex,
                        isDark: widget.isDark,
                        barWidth: barWidth,
                        displayOffset: actualOffset,
                        visibleCount: _actualVisibleCount,  // 使用周期对应的可见数量
                      ),
                      size: Size(chartWidth, chartHeight),
                    ),
                  ),
                  
                  // 十字交叉线和数据标签
                  if (_selectedIndex != -1)
                    CustomPaint(
                      painter: _CrosshairWithLabelsPainter(
                        crossX: (_selectedIndex - actualOffset + 0.5) * barWidth,  // 相对于视口的位置
                        crossY: _calculateCrosshairY(_selectedIndex, minPrice, maxPrice, chartHeight),
                        candle: _candleDataList[_selectedIndex],
                        selectedPeriod: _selectedPeriod,
                        color: widget.isDark 
                            ? CupertinoColors.white.withOpacity(0.3)
                            : CupertinoColors.black.withOpacity(0.2),
                        labelColor: widget.isDark
                            ? CupertinoColors.white.withOpacity(0.9)
                            : CupertinoColors.black.withOpacity(0.8),
                        isDark: widget.isDark,
                      ),
                      size: Size(chartWidth, chartHeight),
                    ),
                  
                  // 触摸检测层
                  GestureDetector(
                    onTapUp: (details) {
                      if (_isPanning == false) {
                        final dx = details.localPosition.dx;
                        // 直接使用外层计算的barWidth
                        final visualIndex = (dx / barWidth).floor();
                        final actualIndex = actualOffset + visualIndex;
                        if (actualIndex >= 0 && actualIndex < _candleDataList.length) {
                          setState(() {
                            _selectedIndex = actualIndex;
                          });
                        }
                      }
                    },
                    onTapDown: (details) {
                      // 点击图表区域时，如果已经显示十字线且再次点击相同位置，则清除十字线
                      if (_isPanning == false && _selectedIndex != -1) {
                        final dx = details.localPosition.dx;
                        final visualIndex = (dx / barWidth).floor();
                        final actualIndex = actualOffset + visualIndex;
                        if (actualIndex == _selectedIndex) {
                          setState(() {
                            _selectedIndex = -1;
                          });
                        }
                      }
                    },
                    onHorizontalDragStart: (details) {
                      // 开始平移（PC端和移动端）
                      setState(() {
                        _isPanning = true;
                        _selectedIndex = -1; // 清除十字线
                      });
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_isPanning == false) return;
                      
                      // 计算平移距离（像素）
                      final dragDelta = details.delta.dx;
                      // 直接使用外层计算的barWidth
                      
                      // 将像素转换为蜡烛数量
                      final candleDelta = dragDelta / barWidth;
                      
                      // 累积更新偏移量（基于当前offset，而不是起始offset）
                      final newOffset = _displayOffset - candleDelta;
                      
                      // 计算最大偏移量（避免clamp参数错误）
                      final maxOffset = _candleDataList.length > _actualVisibleCount 
                          ? _candleDataList.length - _actualVisibleCount 
                          : 0;
                      
                      setState(() {
                        _displayOffset = newOffset.round().clamp(0, maxOffset);
                      });
                      
                      // 如果接近边界且向右拖动，加载更多历史数据
                      // 提前10条触发加载，实现无缝滚动
                      if (dragDelta > 0 && _displayOffset >= maxOffset - 10) {
                        _loadMoreHistory();
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      // 结束平移
                      setState(() {
                        _isPanning = false;
                      });
                    },
                    onHorizontalDragCancel: () {
                      // 取消平移
                      setState(() {
                        _isPanning = false;
                      });
                    },
                    behavior: HitTestBehavior.translucent,
                    child: MouseRegion(
                      onHover: (event) {
                        // PC端鼠标悬停移动十字线（只在非平移状态下）
                        if (_isPanning == false) {
                          final dx = event.localPosition.dx;
                          // 直接使用外层计算的barWidth
                          final visualIndex = (dx / barWidth).floor();
                          final actualIndex = actualOffset + visualIndex;
                          if (actualIndex >= 0 && actualIndex < _candleDataList.length && actualIndex != _selectedIndex) {
                            setState(() {
                              _selectedIndex = actualIndex;
                            });
                          }
                        }
                      },
                      onExit: (event) {
                        // 鼠标离开时清除选中状态（PC端）
                        if (_selectedIndex != -1 && _isPanning == false) {
                          setState(() {
                            _selectedIndex = -1;
                          });
                        }
                      },
                      child: Container(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // 成交量图表
        if (maxVolume > 0) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 45,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 根据周期使用不同的可见数量，与蜡烛图保持一致
                final volumeBarWidth = constraints.maxWidth / _actualVisibleCount;
                
                return ClipRect(  // 裁剪超出边界的部分
                  child: CustomPaint(
                    painter: _VolumeChartPainter(
                      candles: _candleDataList,
                      maxVolume: maxVolume,
                      selectedIndex: _selectedIndex,
                      isDark: widget.isDark,
                      barWidth: volumeBarWidth,
                      displayOffset: _displayOffset,
                      visibleCount: _actualVisibleCount,  // 使用周期对应的可见数量
                    ),
                    size: Size(constraints.maxWidth, 45),
                  ),
                );
              },
            ),
          ),
        ],


      ],
    );
  }
}

/// 网格绘制器
class _GridPainter extends CustomPainter {
  final double minPrice;
  final double maxPrice;
  final bool isDark;
  final List<CandleData> candleDataList;
  final String selectedPeriod;
  final int selectedIndex;
  final int displayOffset;
  final int visibleCount;

  _GridPainter({
    required this.minPrice,
    required this.maxPrice,
    required this.isDark,
    required this.candleDataList,
    required this.selectedPeriod,
    required this.selectedIndex,
    required this.displayOffset,
    required this.visibleCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = isDark
          ? CupertinoColors.white.withOpacity(0.05)
          : CupertinoColors.systemGrey.withOpacity(0.1)
      ..strokeWidth = 1;

    final borderPaint = Paint()
      ..color = isDark
          ? CupertinoColors.white.withOpacity(0.1)
          : CupertinoColors.systemGrey.withOpacity(0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 绘制水平网格线
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 绘制边框
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      borderPaint,
    );

    // 绘制Y轴价格标签
    final pricePaint = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );
    
    final priceRange = maxPrice - minPrice;
    for (int i = 0; i <= 4; i++) {
      final price = minPrice + priceRange * (1 - i / 4);
      final y = size.height * (i / 4);
      
      pricePaint.text = TextSpan(
        text: price.toStringAsFixed(2),
        style: TextStyle(
          fontSize: 9,
          color: isDark
              ? CupertinoColors.white.withOpacity(0.5)
              : CupertinoColors.systemGrey,
        ),
      );
      pricePaint.layout();
      pricePaint.paint(canvas, Offset(2, y - pricePaint.height / 2));
    }

    // 绘制X轴日期标签（最多3个）
    if (candleDataList.isNotEmpty) {
      final datePaint = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      
      // 只考虑可见范围内的蜡烛
      final startIndex = displayOffset;
      final endIndex = (displayOffset + visibleCount).clamp(0, candleDataList.length - 1);
      final visibleCandlesCount = endIndex - startIndex + 1;
      
      if (visibleCandlesCount <= 0) return;
      
      final barWidth = size.width / visibleCount;  // 使用可见数量计算宽度
      final labelCount = visibleCandlesCount > 6 ? 3 : (visibleCandlesCount > 3 ? 2 : 1);
      final interval = (visibleCandlesCount / labelCount).floor();
      
      for (int i = 0; i < labelCount; i++) {
        final visibleIndex = i * interval;
        final actualIndex = startIndex + visibleIndex;  // 转换为实际索引
        if (actualIndex >= candleDataList.length) break;
        
        final candle = candleDataList[actualIndex];
        String displayDate;
        
        if (selectedPeriod == 'month') {
          displayDate = candle.date.length >= 7 
              ? '${candle.date.substring(2, 4)}/${candle.date.substring(5, 7)}'
              : candle.date;
        } else {
          displayDate = candle.date.length >= 10 
              ? '${candle.date.substring(5, 7)}/${candle.date.substring(8, 10)}'
              : candle.date;
        }
        
        // 使用可见索引计算x位置
        final x = visibleIndex * barWidth + barWidth / 2;
        
        datePaint.text = TextSpan(
          text: displayDate,
          style: TextStyle(
            fontSize: 9,
            color: isDark
                ? CupertinoColors.white.withOpacity(0.5)
                : CupertinoColors.systemGrey,
          ),
        );
        datePaint.layout();
        datePaint.paint(canvas, Offset(x - datePaint.width / 2, size.height - datePaint.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.isDark != isDark ||
        oldDelegate.candleDataList != candleDataList ||
        oldDelegate.selectedPeriod != selectedPeriod ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}

/// 蜡烛图绘制器
class _CandleChartPainter extends CustomPainter {
  final List<CandleData> candles;
  final double minPrice;
  final double maxPrice;
  final int selectedIndex;
  final bool isDark;
  final double barWidth;
  final int displayOffset;
  final int visibleCount;

  _CandleChartPainter({
    required this.candles,
    required this.minPrice,
    required this.maxPrice,
    required this.selectedIndex,
    required this.isDark,
    required this.barWidth,
    required this.displayOffset,
    required this.visibleCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final candleWidth = barWidth * 0.6; // 蜡烛宽度占柱体宽度的60%
    final shadowWidth = 1.0; // 影线宽度

    // 只绘制可见范围内的蜡烛
    final startIndex = displayOffset;
    final endIndex = (displayOffset + visibleCount).clamp(0, candles.length - 1);

    if (startIndex > endIndex) return;

    for (int i = startIndex; i <= endIndex; i++) {
      final candle = candles[i];
      final isSelected = i == selectedIndex;
      
      // 计算在视口中的位置（相对于视口左边界）
      final visualIndex = i - displayOffset;
      final x = visualIndex * barWidth + barWidth / 2; // 柱体中心x坐标
      
      // 计算Y坐标
      final priceRange = maxPrice - minPrice;
      if (priceRange <= 0) continue;
      
      final highY = size.height * (1 - (candle.high - minPrice) / priceRange);
      final lowY = size.height * (1 - (candle.low - minPrice) / priceRange);
      final openY = size.height * (1 - (candle.open - minPrice) / priceRange);
      final closeY = size.height * (1 - (candle.close - minPrice) / priceRange);

      final color = candle.bodyColor.withOpacity(isSelected ? 1.0 : 0.9);

      // 绘制影线（细线，居中）
      final shadowPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..strokeWidth = shadowWidth
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), shadowPaint);

      // 绘制实体（矩形，居中）
      final bodyTop = candle.isBullish ? closeY : openY;
      final bodyBottom = candle.isBullish ? openY : closeY;
      final bodyHeight = (bodyBottom - bodyTop).abs();
      
      if (bodyHeight > 0) {
        final bodyRect = Rect.fromCenter(
          center: Offset(x, (bodyTop + bodyBottom) / 2),
          width: candleWidth,
          height: bodyHeight,
        );
        
        final bodyPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawRect(bodyRect, bodyPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CandleChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.isDark != isDark ||
        oldDelegate.barWidth != barWidth ||
        oldDelegate.displayOffset != displayOffset ||
        oldDelegate.visibleCount != visibleCount;
  }
}

/// 十字交叉线绘制器（带数据标签）
class _CrosshairWithLabelsPainter extends CustomPainter {
  final double crossX;
  final double crossY;
  final CandleData candle;
  final String selectedPeriod;
  final Color color;
  final Color labelColor;
  final bool isDark;

  _CrosshairWithLabelsPainter({
    required this.crossX,
    required this.crossY,
    required this.candle,
    required this.selectedPeriod,
    required this.color,
    required this.labelColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 绘制虚线十字交叉
    _drawDashedLine(canvas, Offset(crossX, 0), Offset(crossX, size.height), linePaint);
    _drawDashedLine(canvas, Offset(0, crossY), Offset(size.width, crossY), linePaint);

    // 绘制X轴日期标签
    final dateText = candle.date; // yyyy-mm-dd格式
    final datePainter = TextPainter(
      text: TextSpan(
        text: dateText,
        style: TextStyle(
          fontSize: 10,
          color: isDark ? CupertinoColors.white : CupertinoColors.black,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    datePainter.layout();
    
    // 标签背景
    final dateBgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(crossX, size.height - 10),
        width: datePainter.width + 8,
        height: datePainter.height + 4,
      ),
      const Radius.circular(4),
    );
    
    final bgPaint = Paint()
      ..color = isDark 
          ? const Color(0xFF2C2C2E).withOpacity(0.9)
          : CupertinoColors.white.withOpacity(0.9);
    canvas.drawRRect(dateBgRect, bgPaint);
    
    datePainter.paint(canvas, Offset(crossX - datePainter.width / 2, size.height - 12));

    // 绘制Y轴价格标签
    final priceText = candle.close.toStringAsFixed(2);
    final pricePainter = TextPainter(
      text: TextSpan(
        text: priceText,
        style: TextStyle(
          fontSize: 10,
          color: isDark ? CupertinoColors.white : CupertinoColors.black,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    pricePainter.layout();
    
    // 标签背景
    final priceBgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(35, crossY),
        width: pricePainter.width + 8,
        height: pricePainter.height + 4,
      ),
      const Radius.circular(4),
    );
    
    canvas.drawRRect(priceBgRect, bgPaint);
    pricePainter.paint(canvas, Offset(30 - pricePainter.width / 2, crossY - pricePainter.height / 2));
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
  bool shouldRepaint(covariant _CrosshairWithLabelsPainter oldDelegate) {
    return oldDelegate.crossX != crossX ||
        oldDelegate.crossY != crossY ||
        oldDelegate.candle != candle;
  }
}

/// 成交量图表绘制器
class _VolumeChartPainter extends CustomPainter {
  final List<CandleData> candles;
  final double maxVolume;
  final int selectedIndex;
  final bool isDark;
  final double barWidth;
  final int displayOffset;
  final int visibleCount;

  _VolumeChartPainter({
    required this.candles,
    required this.maxVolume,
    required this.selectedIndex,
    required this.isDark,
    required this.barWidth,
    required this.displayOffset,
    required this.visibleCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || maxVolume <= 0) return;

    final volumeBarWidth = barWidth * 0.6;

    // 只绘制可见范围内的成交量
    final startIndex = displayOffset;
    final endIndex = (displayOffset + visibleCount).clamp(0, candles.length - 1);

    if (startIndex > endIndex) return;

    for (int i = startIndex; i <= endIndex; i++) {
      final candle = candles[i];
      final isSelected = i == selectedIndex;
      
      // 计算在视口中的位置
      final visualIndex = i - displayOffset;
      final x = visualIndex * barWidth + barWidth / 2;
      final volumeHeight = (candle.volume / maxVolume) * size.height;
      
      final color = candle.bodyColor.withOpacity(isSelected ? 0.8 : 0.4);
      
      final rect = Rect.fromCenter(
        center: Offset(x, size.height - volumeHeight / 2),
        width: volumeBarWidth,
        height: volumeHeight,
      );
      
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.maxVolume != maxVolume ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.isDark != isDark ||
        oldDelegate.barWidth != barWidth ||
        oldDelegate.displayOffset != displayOffset ||
        oldDelegate.visibleCount != visibleCount;
  }
}

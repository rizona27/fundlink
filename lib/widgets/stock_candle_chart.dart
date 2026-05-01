import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _selectedPeriod = 'day'; 
  final Map<String, String> _periodLabels = {
    'day': '日K',
    'week': '周K',
    'month': '月K',
  };

  List<CandleData> _candleDataList = [];
  bool _isLoading = false;
  
  int _selectedIndex = -1;
  bool _isPanning = false; 
  
  DateTime? _earliestDate; 
  int _displayOffset = 0; 
  
  double _visibleMinPrice = 0;
  double _visibleMaxPrice = 0;
  
  static const int visibleCandleCount = 45; 
  
  bool _hasLoadedInitial = false;  
  bool _hasPreloaded = false;      
  
  int get _actualVisibleCount {
    switch (_selectedPeriod) {
      case 'day':
        return 45;  
      case 'week':
        return 35;  
      case 'month':
        return 25;  
      default:
        return 45;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFromCache().then((_) {
      _loadInitialData();
    });
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  void clearCrosshair() {
    if (_selectedIndex != -1) {
      setState(() {
        _selectedIndex = -1;
      });
    }
  }
  
  String _getCacheKey() {
    return 'candle_cache_${widget.stockCode}_$_selectedPeriod';
  }
  
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
      }
    } catch (e) {
    }
  }
  
  Future<void> _loadInitialData() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 60)); 
      
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
            
            final mergedList = _mergeCandleData(_candleDataList, newCandles);
            
            setState(() {
              _candleDataList = mergedList;
              _earliestDate = DateTime.parse(mergedList.first.date);
              _displayOffset = mergedList.length > _actualVisibleCount
                  ? mergedList.length - _actualVisibleCount
                  : 0;
              _hasLoadedInitial = true;
            });
            
            _saveToCache(mergedList);
            
            _preloadMoreHistory();
          }
        }
      }
    } catch (e) {
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _preloadMoreHistory() async {
    if (_hasPreloaded || _earliestDate == null) return;
    
    
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
          loadCount = 200;  
          break;
        case 'week':
          klt = 102;
          loadCount = 150;  
          break;
        case 'month':
          klt = 103;
          loadCount = 120;  
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
            
            final mergedList = _mergeCandleData(historyCandles, _candleDataList);
            
            setState(() {
              _candleDataList = mergedList;
              _earliestDate = DateTime.parse(mergedList.first.date);
              _displayOffset += historyCandles.length;
              _hasPreloaded = true;
            });
            
            _saveToCache(mergedList);
          }
        }
      }
    } catch (e) {
    }
  }
  
  List<CandleData> _mergeCandleData(List<CandleData> existing, List<CandleData> newData) {
    if (existing.isEmpty) return newData;
    if (newData.isEmpty) return existing;
    
    final Map<String, CandleData> mergedMap = {};
    
    for (final candle in existing) {
      mergedMap[candle.date] = candle;
    }
    
    for (final candle in newData) {
      mergedMap[candle.date] = candle;
    }
    
    final mergedList = mergedMap.values.toList();
    mergedList.sort((a, b) => a.date.compareTo(b.date));
    
    return mergedList;
  }
  
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
    } catch (e) {
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

      int klt;
      int lmt; 
      int preloadLmt; 
      
      switch (_selectedPeriod) {
        case 'day':
          klt = 101; 
          lmt = 45;  
          preloadLmt = 120;  
          break;
        case 'week':
          klt = 102; 
          lmt = 35;  
          preloadLmt = 100;  
          break;
        case 'month':
          klt = 103; 
          lmt = 25;  
          preloadLmt = 72;  
          break;
        default:
          klt = 101;
          lmt = 45;
          preloadLmt = 120;
      }

      final begDate = '0';  
      final endDate = '20500101';  

      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$formattedSecid'
        '&klt=$klt'
        '&fqt=0'  
        '&beg=$begDate'
        '&end=$endDate'
        '&lmt=$preloadLmt'  
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
            setState(() {
              _candleDataList = candles;
              if (candles.isNotEmpty) {
                final firstDate = candles.first.date;
                _earliestDate = DateTime.parse(firstDate);
                _displayOffset = candles.length > _actualVisibleCount 
                    ? candles.length - _actualVisibleCount 
                    : 0;
              }
            });
          } else {
            if (retryCount < 2) {
              await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
              await _loadData(retryCount: retryCount + 1);
              return;
            }
          }
        } else {
          if (retryCount < 2) {
            await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
            await _loadData(retryCount: retryCount + 1);
            return;
          }
        }
      } else {
        if (retryCount < 2) {
          await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
          await _loadData(retryCount: retryCount + 1);
          return;
        }
      }
    } catch (e) {
      if (retryCount < 2) {
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
      _selectedIndex = -1;
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
    
    final startIndex = offset;
    final endIndex = (offset + visibleCount).clamp(0, candles.length - 1);
    
    final visibleCandles = candles.sublist(startIndex, endIndex + 1);
    
    if (visibleCandles.isEmpty) {
      _visibleMinPrice = 0;
      _visibleMaxPrice = 0;
      return;
    }
    
    _visibleMinPrice = visibleCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    _visibleMaxPrice = visibleCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    
    final priceRange = _visibleMaxPrice - _visibleMinPrice;
    _visibleMinPrice -= priceRange * 0.05;
    _visibleMaxPrice += priceRange * 0.05;
  }
  
  Future<void> _loadMoreHistory() async {
    if (_isLoading || _earliestDate == null) return;
    

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
          loadCount = 45;  
          break;
        case 'week':
          klt = 102;
          loadCount = 35;  
          break;
        case 'month':
          klt = 103;
          loadCount = 25;  
          break;
        default:
          klt = 101;
          loadCount = 45;
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
            setState(() {
              final existingDates = _candleDataList.map((c) => c.date).toSet();
              final uniqueNewCandles = newCandles.where((c) => !existingDates.contains(c.date)).toList();
              
              if (uniqueNewCandles.isNotEmpty) {
                _candleDataList = [...uniqueNewCandles, ..._candleDataList];
                _earliestDate = DateTime.parse(uniqueNewCandles.first.date);
                _displayOffset += uniqueNewCandles.length;
                
                _saveToCache(_candleDataList);
              }
            });
          }
        }
      }
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
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

    double maxVolume = _candleDataList.map((c) => c.volume).reduce((a, b) => a > b ? a : b);

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

        SizedBox(
          height: 200,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = constraints.maxWidth;
              final chartHeight = constraints.maxHeight;
              
              final totalCandles = _candleDataList.length;
              final int maxOffset = totalCandles > _actualVisibleCount ? totalCandles - _actualVisibleCount : 0;
              final int actualOffset = _displayOffset.clamp(0, maxOffset);
              
              _calculateVisiblePriceRange(actualOffset, _actualVisibleCount, _candleDataList);
              final minPrice = _visibleMinPrice;
              final maxPrice = _visibleMaxPrice;
              
              final barWidth = chartWidth / _actualVisibleCount;
              
              return Stack(
                children: [
                  CustomPaint(
                    painter: _GridPainter(
                      minPrice: minPrice,
                      maxPrice: maxPrice,
                      isDark: widget.isDark,
                      candleDataList: _candleDataList,
                      selectedPeriod: _selectedPeriod,
                      selectedIndex: _selectedIndex,
                      displayOffset: actualOffset,
                      visibleCount: _actualVisibleCount,  
                    ),
                    size: Size(chartWidth, chartHeight),
                  ),
                  
                  ClipRect(  
                    child: CustomPaint(
                      painter: _CandleChartPainter(
                        candles: _candleDataList,
                        minPrice: minPrice,
                        maxPrice: maxPrice,
                        selectedIndex: _selectedIndex,
                        isDark: widget.isDark,
                        barWidth: barWidth,
                        displayOffset: actualOffset,
                        visibleCount: _actualVisibleCount,  
                      ),
                      size: Size(chartWidth, chartHeight),
                    ),
                  ),
                  
                  if (_selectedIndex != -1)
                    CustomPaint(
                      painter: _CrosshairWithLabelsPainter(
                        crossX: (_selectedIndex - actualOffset + 0.5) * barWidth,  
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
                  
                  GestureDetector(
                    onTapUp: (details) {
                      if (_isPanning == false) {
                        final dx = details.localPosition.dx;
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
                      setState(() {
                        _isPanning = true;
                        _selectedIndex = -1; 
                      });
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_isPanning == false) return;
                      
                      final dragDelta = details.delta.dx;
                      
                      final candleDelta = dragDelta / barWidth;
                      
                      final newOffset = _displayOffset - candleDelta;
                      
                      final maxOffset = _candleDataList.length > _actualVisibleCount 
                          ? _candleDataList.length - _actualVisibleCount 
                          : 0;
                      
                      setState(() {
                        _displayOffset = newOffset.round().clamp(0, maxOffset);
                      });
                      
                      if (dragDelta > 0 && _displayOffset >= maxOffset - 10) {
                        _loadMoreHistory();
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      setState(() {
                        _isPanning = false;
                      });
                    },
                    onHorizontalDragCancel: () {
                      setState(() {
                        _isPanning = false;
                      });
                    },
                    behavior: HitTestBehavior.translucent,
                    child: MouseRegion(
                      onHover: (event) {
                        if (_isPanning == false) {
                          final dx = event.localPosition.dx;
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

        if (maxVolume > 0) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 45,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final volumeBarWidth = constraints.maxWidth / _actualVisibleCount;
                
                return ClipRect(  
                  child: CustomPaint(
                    painter: _VolumeChartPainter(
                      candles: _candleDataList,
                      maxVolume: maxVolume,
                      selectedIndex: _selectedIndex,
                      isDark: widget.isDark,
                      barWidth: volumeBarWidth,
                      displayOffset: _displayOffset,
                      visibleCount: _actualVisibleCount,  
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

    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      borderPaint,
    );

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

    if (candleDataList.isNotEmpty) {
      final datePaint = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      
      final startIndex = displayOffset;
      final endIndex = (displayOffset + visibleCount).clamp(0, candleDataList.length - 1);
      final visibleCandlesCount = endIndex - startIndex + 1;
      
      if (visibleCandlesCount <= 0) return;
      
      final barWidth = size.width / visibleCount;  
      final labelCount = visibleCandlesCount > 6 ? 3 : (visibleCandlesCount > 3 ? 2 : 1);
      final interval = (visibleCandlesCount / labelCount).floor();
      
      for (int i = 0; i < labelCount; i++) {
        final visibleIndex = i * interval;
        final actualIndex = startIndex + visibleIndex;  
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

    final candleWidth = barWidth * 0.6; 
    final shadowWidth = 1.0; 

    final startIndex = displayOffset;
    final endIndex = (displayOffset + visibleCount).clamp(0, candles.length - 1);

    if (startIndex > endIndex) return;

    for (int i = startIndex; i <= endIndex; i++) {
      final candle = candles[i];
      final isSelected = i == selectedIndex;
      
      final visualIndex = i - displayOffset;
      final x = visualIndex * barWidth + barWidth / 2; 
      
      final priceRange = maxPrice - minPrice;
      if (priceRange <= 0) continue;
      
      final highY = size.height * (1 - (candle.high - minPrice) / priceRange);
      final lowY = size.height * (1 - (candle.low - minPrice) / priceRange);
      final openY = size.height * (1 - (candle.open - minPrice) / priceRange);
      final closeY = size.height * (1 - (candle.close - minPrice) / priceRange);

      final color = candle.bodyColor.withOpacity(isSelected ? 1.0 : 0.9);

      final shadowPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..strokeWidth = shadowWidth
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), shadowPaint);

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

    _drawDashedLine(canvas, Offset(crossX, 0), Offset(crossX, size.height), linePaint);
    _drawDashedLine(canvas, Offset(0, crossY), Offset(size.width, crossY), linePaint);

    final dateText = candle.date; 
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

    final startIndex = displayOffset;
    final endIndex = (displayOffset + visibleCount).clamp(0, candles.length - 1);

    if (startIndex > endIndex) return;

    for (int i = startIndex; i <= endIndex; i++) {
      final candle = candles[i];
      final isSelected = i == selectedIndex;
      
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

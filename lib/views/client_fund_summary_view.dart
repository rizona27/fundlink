import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import '../models/fund_holding.dart';
import '../models/top_holding.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../services/stock_quote_service.dart';

class ClientFundSummaryPage extends StatefulWidget {
  final String clientName;
  final String clientId;
  final List<FundHolding> holdings;
  final DataManager dataManager;
  final FundService fundService;

  const ClientFundSummaryPage({
    super.key,
    required this.clientName,
    required this.clientId,
    required this.holdings,
    required this.dataManager,
    required this.fundService,
  });

  @override
  State<ClientFundSummaryPage> createState() => _ClientFundSummaryPageState();
}

class _ClientFundSummaryPageState extends State<ClientFundSummaryPage> {
  final StockQuoteService _quoteService = StockQuoteService();
  final Map<String, List<TopHolding>> _fundTopHoldings = {};

  bool _loadingTopHoldings = true;
  bool _loadingQuotes = true;
  bool _profitBarExpanded = false;
  int _touchedPieIndex = -1;

  Map<String, StockQuote> _stockQuotes = {};
  List<_WeightedHolding> _weightedHoldings = [];

  // --- Chart colour palette ---
  static const List<Color> _chartColors = [
    Color(0xFF4A90D9), Color(0xFFE85D75), Color(0xFF50C878),
    Color(0xFFFFB347), Color(0xFF9B59B6), Color(0xFF1ABC9C),
    Color(0xFFE74C3C), Color(0xFF3498DB), Color(0xFF2ECC71),
    Color(0xFFF39C12), Color(0xFF8E44AD), Color(0xFF16A085),
    Color(0xFFD35400), Color(0xFF2980B9), Color(0xFFC0392B),
    Color(0xFF27AE60),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait(
        widget.holdings.map((h) => widget.fundService
            .fetchTopHoldingsFromHtml(h.fundCode)
            .catchError((_) => <TopHolding>[])),
      );
      if (!mounted) return;

      for (int i = 0; i < widget.holdings.length; i++) {
        _fundTopHoldings[widget.holdings[i].fundCode] = results[i];
      }

      _computeWeightedHoldings();
      setState(() => _loadingTopHoldings = false);

      await _fetchStockQuotes();
      if (mounted) setState(() => _loadingQuotes = false);
    } catch (_) {
      if (mounted) {
        setState(() { _loadingTopHoldings = false; _loadingQuotes = false; });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  void _computeWeightedHoldings() {
    final totalInv = _totalInvestment;
    if (totalInv <= 0) return;

    final map = <String, _WeightedHolding>{};
    for (final h in widget.holdings) {
      final weight = h.totalCost / totalInv;
      final holdings = _fundTopHoldings[h.fundCode] ?? [];
      for (final th in holdings) {
        final key = '${th.stockCode}_${th.stockName}';
        final wr = weight * th.ratio;
        if (map.containsKey(key)) {
          map[key] = map[key]!.add(wr, th.ratio, h.fundCode, h.fundName);
        } else {
          map[key] = _WeightedHolding(
            stockCode: th.stockCode, stockName: th.stockName,
            weightedRatio: wr, totalRatio: th.ratio,
            fundCodes: {h.fundCode}, fundNames: {h.fundName},
          );
        }
      }
    }

    final list = map.values.toList();
    list.sort((a, b) => b.weightedRatio.compareTo(a.weightedRatio));
    _weightedHoldings = list;
  }

  Future<void> _fetchStockQuotes() async {
    final allCodes = _weightedHoldings.map((w) => w.stockCode).toList();
    if (allCodes.isEmpty) return;
    _stockQuotes = await _quoteService.fetchQuotes(allCodes);
  }

  double get _totalInvestment =>
      widget.holdings.fold(0.0, (sum, h) => sum + h.totalCost);
  double get _totalProfit =>
      widget.holdings.fold(0.0, (sum, h) => sum + h.profit);
  double get _totalAbsProfit =>
      widget.holdings.fold(0.0, (sum, h) => sum + h.profit.abs());
  double get _maxAbsProfit {
    double m = 0;
    for (final h in widget.holdings) { if (h.profit.abs() > m) m = h.profit.abs(); }
    return m;
  }

  // ---------------------------------------------------------------------------
  // Style & industry helpers
  // ---------------------------------------------------------------------------

  /// Asset-weighted style distribution.
  /// Instead of counting stocks, each stock's vote is multiplied by its
  /// final weighted ratio in the client's total portfolio:
  ///   StyleRatio = Σ (FundWeight × StockInFundWeight) × IsStyle
  /// This ensures the numbers reflect real capital exposure, not just
  /// head-count of holdings.
  Map<String, double> _calculateStyleDistribution() {
    double largeW = 0, midW = 0, smallW = 0;
    double valueW = 0, growthW = 0, balancedW = 0;

    for (final wh in _weightedHoldings) {
      final w = wh.weightedRatio;
      if (w <= 0) continue;

      final fullCode = _quoteService.toFullCode(wh.stockCode);
      final q = _stockQuotes[fullCode];

      // Market cap style — use API data if available; otherwise fallback.
      String cap;
      if (q != null && q.totalMv != null) {
        cap = q.marketCapStyle;
      } else {
        cap = StockQuoteService.fallbackMarketCapStyle(wh.stockCode);
      }
      switch (cap) {
        case '大盘': largeW += w; break;
        case '中盘': midW += w; break;
        case '小盘': smallW += w; break;
        default: midW += w; break; // treat unknown as mid
      }

      // Value / Growth style — use API data if available.
      String style;
      if (q != null && (q.pe != null || q.pb != null)) {
        style = q.valueStyle;
      } else {
        style = '均衡';
      }
      switch (style) {
        case '价值': valueW += w; break;
        case '成长': growthW += w; break;
        case '均衡': balancedW += w; break;
        default: balancedW += w; break;
      }
    }

    final totalW = largeW + midW + smallW;
    if (totalW <= 0) return {};
    return {
      '大盘占比': largeW / totalW, '中盘占比': midW / totalW,
      '小盘占比': smallW / totalW, '价值占比': valueW / totalW,
      '成长占比': growthW / totalW, '均衡占比': balancedW / totalW,
    };
  }

  int _getOverlapStockCount() =>
      _weightedHoldings.where((w) => w.fundCodes.length > 1).length;

  List<MapEntry<String, double>> _getTopIndustries({int count = 3}) {
    final industryMap = <String, double>{};
    for (final wh in _weightedHoldings) {
      final label = _classifyIndustry(wh.stockName, code: wh.stockCode);
      industryMap[label] = (industryMap[label] ?? 0) + wh.weightedRatio;
    }
    if (industryMap.isEmpty) return [];
    final sorted = industryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).toList();
  }

  /// Hardcoded precision mapping for well-known heavy-weight stocks.
  /// Stock code → industry label.  Checked BEFORE keyword matching so
  /// stocks with ambiguous names (e.g. "某某发展", "某某股份") land in the
  /// correct bucket regardless of their name.
  static const Map<String, String> _hardcodedIndustryMap = {
    // Finance & Insurance
    '601318': '保险',     // 中国平安
    '601628': '保险',     // 中国人寿
    '601601': '保险',     // 中国太保
    '601336': '保险',     // 新华保险
    '600036': '银行',     // 招商银行
    '601398': '银行',     // 工商银行
    '601939': '银行',     // 建设银行
    '601288': '银行',     // 农业银行
    '601988': '银行',     // 中国银行
    '600016': '银行',     // 民生银行
    '601166': '银行',     // 兴业银行
    '000001': '银行',     // 平安银行
    '002142': '银行',     // 宁波银行
    '600030': '券商',     // 中信证券
    '300059': '券商',     // 东方财富
    // Energy & Resources
    '601857': '石油石化', // 中国石油
    '600028': '石油石化', // 中国石化
    '600938': '石油石化', // 中国海油
    '601088': '煤炭',     // 中国神华
    '601225': '煤炭',     // 陕西煤业
    '601899': '有色金属', // 紫金矿业
    '603993': '有色金属', // 洛阳钼业
    '600547': '有色金属', // 山东黄金
    '002460': '有色金属', // 赣锋锂业
    '002466': '有色金属', // 天齐锂业
    '600111': '有色金属', // 北方稀土
    // Power & Utilities
    '600900': '电力/公用事业', // 长江电力
    '600025': '电力/公用事业', // 华能水电
    '601985': '电力/公用事业', // 中国核电
    '003816': '电力/公用事业', // 中国广核
    // Electronics & Semiconductors
    '688981': '电子/半导体', // 中芯国际
    '603501': '电子/半导体', // 韦尔股份
    '002371': '电子/半导体', // 北方华创
    '603986': '电子/半导体', // 兆易创新
    '002049': '电子/半导体', // 紫光国微
    '688041': '电子/半导体', // 海光信息
    '688256': '电子/半导体', // 寒武纪
    '002415': '安防',       // 海康威视
    '002236': '安防',       // 大华股份
    '002475': '电子元器件', // 立讯精密
    '601138': '电子元器件', // 工业富联
    '000725': '面板/显示',  // 京东方
    // Consumer
    '600519': '白酒',       // 贵州茅台
    '000858': '白酒',       // 五粮液
    '000568': '白酒',       // 泸州老窖
    '600809': '白酒',       // 山西汾酒
    '002304': '白酒',       // 洋河股份
    '600887': '乳制品',     // 伊利股份
    '603288': '食品饮料',   // 海天味业
    '000333': '家电',       // 美的集团
    '000651': '家电',       // 格力电器
    '600690': '家电',       // 海尔智家
    // Auto & New Energy
    '002594': '汽车',       // 比亚迪
    '601633': '汽车',       // 长城汽车
    '000625': '汽车',       // 长安汽车
    '300750': '锂电池',     // 宁德时代
    '300014': '锂电池',     // 亿纬锂能
    '002074': '锂电池',     // 国轩高科
    '601012': '光伏',       // 隆基绿能
    '600438': '光伏',       // 通威股份
    '300274': '光伏',       // 阳光电源
    '002459': '光伏',       // 晶澳科技
    // Healthcare
    '600276': '创新药',     // 恒瑞医药
    '300760': '医疗器械',   // 迈瑞医疗
    '300015': '医疗服务',   // 爱尔眼科
    '603259': '医药研发外包', // 药明康德
    '300347': '医药研发外包', // 泰格医药
    '002821': '医药研发外包', // 凯莱英
    '600436': '中药',       // 片仔癀
    '000538': '中药',       // 云南白药
    '000423': '中药',       // 东阿阿胶
    // Technology & Internet
    '00700': '互联网',      // 腾讯控股
    '09988': '互联网',      // 阿里巴巴
    '03690': '互联网',      // 美团
    '09888': '互联网',      // 百度
    '09618': '互联网',      // 京东
    '01024': '互联网',      // 快手
    '09999': '互联网',      // 网易
    '002230': '人工智能',   // 科大讯飞
    '688111': '计算机/软件', // 金山办公
    '002410': '计算机/软件', // 广联达
    '600588': '计算机/软件', // 用友网络
    '600570': '计算机/软件', // 恒生电子
    // Telecom
    '600941': '通信',       // 中国移动
    '601728': '通信',       // 中国电信
    '600050': '通信',       // 中国联通
    '000063': '通信',       // 中兴通讯
    // Transportation
    '601919': '航运/港口',  // 中远海控
    '002352': '快递/物流',  // 顺丰控股
    '600029': '航空/机场',  // 南方航空
    '601111': '航空/机场',  // 中国国航
    '601816': '铁路',       // 京沪高铁
    // Military / Defense
    '600760': '军工/航天',  // 中航沈飞
    '000768': '军工/航天',  // 中航西飞
    '600893': '军工/航天',  // 航发动力
    '002179': '军工/航天',  // 中航光电
    // Agriculture
    '002714': '农牧/农化',  // 牧原股份
    '300498': '农牧/农化',  // 温氏股份
    '000876': '农牧/农化',  // 新希望
    '002311': '农牧/农化',  // 海大集团
    // Media
    '002027': '传媒/教育',  // 分众传媒
    // Real Estate
    '000002': '房地产',     // 万科
    '600048': '房地产',     // 保利发展
    '001979': '房地产',     // 招商蛇口
    // Steel
    '600019': '钢铁',       // 宝钢股份
    '000898': '钢铁',       // 鞍钢股份
    '600010': '钢铁',       // 包钢股份
    '000932': '钢铁',       // 华菱钢铁
    '600282': '钢铁',       // 南钢股份
    // Chemicals
    '600309': '化工',       // 万华化学
    '600346': '化工',       // 恒力石化
    '002493': '化工',       // 荣盛石化
    '000703': '化工',       // 恒逸石化
    '600426': '化工',       // 华鲁恒升
    '600989': '化工',       // 宝丰能源
    '002601': '化工',       // 龙佰集团
    '600160': '化工',       // 巨化股份
    '002064': '化工',       // 华峰化学
    // Textile & Apparel
    '02020': '纺织服装',    // 安踏体育
    '02331': '纺织服装',    // 李宁
    '03998': '纺织服装',    // 波司登
    '600398': '纺织服装',   // 海澜之家
    '300979': '纺织服装',   // 华利集团
    // Retail
    '601888': '商业零售',   // 中国中免
    '601933': '商业零售',   // 永辉超市
    '002024': '商业零售',   // 苏宁易购
    // Construction Machinery
    '600031': '工程机械',   // 三一重工
    '000157': '工程机械',   // 中联重科
    '000425': '工程机械',   // 徐工机械
    '601100': '工程机械',   // 恒立液压
    '603338': '工程机械',   // 浙江鼎力
    // Environmental Protection
    '603568': '环保',       // 伟明环保
    '600323': '环保',       // 瀚蓝环境
    '300070': '环保',       // 碧水源
    // Paper & Packaging
    '002078': '造纸/包装',  // 太阳纸业
    '000488': '造纸/包装',  // 晨鸣纸业
    '002831': '造纸/包装',  // 裕同科技
    // Tourism & Hotels
    '600754': '旅游酒店',   // 锦江酒店
    '600258': '旅游酒店',   // 首旅酒店
    '603099': '旅游酒店',   // 长白山
    // Testing & Inspection
    '300012': '检验检测',   // 华测检测
    '002967': '检验检测',   // 广电计量
    // New Materials
    '300699': '新材料',     // 光威复材
    '300777': '新材料',     // 中简科技
    '600143': '新材料',     // 金发科技
    '688005': '新材料',     // 容百科技（三元材料）
    '300073': '新材料',     // 当升科技（正极材料）
    // Glass
    '600660': '玻璃/建材',  // 福耀玻璃（已在汽车零部件分类过，此处保留作为玻璃龙头）
    '601636': '玻璃/建材',  // 旗滨集团
    '000012': '玻璃/建材',  // 南玻A
    // Non-bank Financial
    '600053': '非银金融',   // 九鼎投资
  };

  /// Industry classification via keyword matching on stock name, with a
  /// hardcoded precision-map lookup first, and a dual feature fallback for
  /// STAR-board / ChiNext stocks whose names suggest energy or electronics.
  /// Covers the major A-share + HK sectors.
  String _classifyIndustry(String n, {String code = ''}) {
    // 0. Hardcoded precision map — checked first
    if (code.isNotEmpty && _hardcodedIndustryMap.containsKey(code)) {
      return _hardcodedIndustryMap[code]!;
    }

    // Finance & Insurance
    if (_containsAny(n, ['银行', '招商银行', '工商', '建设', '农业', '中国银行', '交通', '兴业',
      '浦发', '民生', '中信银行', '光大银行', '平安银行', '华夏银行', '北京银行', '宁波银行', '南京银行',
      '江苏银行', '上海银行', '杭州银行', '成都银行', '长沙银行', '贵阳银行', '郑州银行', '西安银行',
      '青岛银行', '苏州银行', '厦门银行', '重庆银行', '齐鲁银行', '兰州银行', '沪农商'])) return '银行';
    if (_containsAny(n, ['保险', '中国平安', '中国太保', '中国人寿', '新华保险', '人保', '太平'])) return '保险';
    if (_containsAny(n, ['中信证券', '华泰证券', '海通证券', '国泰君安', '广发证券', '招商证券',
      '东方证券', '申万', '银河', '中金', '东方财富', '同花顺', '指南针', '证券'])) return '券商';

    // Real Estate & Construction
    if (_containsAny(n, ['万科', '保利发展', '保利地产', '招商蛇口', '金地', '绿城', '华润置地',
      '龙湖', '中海地产', '中海发展', '新城控股', '滨江', '建发', '华发', '华侨城', '首开', '地产'])) return '房地产';
    if (_containsAny(n, ['中国建筑', '中国中铁', '中国铁建', '中国交建', '中国电建', '中国中冶',
      '中国化学', '中国能建', '隧道', '路桥', '上海建工', '四川路桥', '建筑', '建材', '海螺水泥',
      '东方雨虹', '北新建材', '三棵树', '伟星新材', '坚朗五金'])) return '建筑建材';

    // Energy & Resources
    if (_containsAny(n, ['中国石油', '中国石化', '中海油', '中国海油', '石化', '石油', '能源',
      '广汇能源', '新潮能源'])) return '石油石化';
    if (_containsAny(n, ['中国神华', '陕西煤业', '中煤能源', '兖矿', '兖州煤业', '淮北矿业',
      '平煤', '晋控煤业', '潞安环能', '华阳', '山煤', '煤炭', '煤业'])) return '煤炭';
    if (_containsAny(n, ['紫金矿业', '洛阳钼业', '山东黄金', '中金黄金', '赤峰黄金', '银泰黄金',
      '西部矿业', '铜陵有色', '江西铜业', '云南铜业', '中国铝业', '南山铝业', '云铝', '神火',
      '天山铝业', '驰宏锌锗', '中金岭南', '锡业', '华友钴业', '赣锋锂业', '天齐锂业', '盐湖',
      '盛新锂能', '雅化', '永兴材料', '北方稀土', '中国稀土', '盛和资源', '厦门钨业', '中钨',
      '金力永磁', '有研新材', '矿业', '钴', '锂', '稀土', '钨', '钼'])) return '有色金属';

    // Power & Utilities
    if (_containsAny(n, ['长江电力', '华能水电', '国投电力', '川投能源', '中国核电', '中国广核',
      '三峡能源', '华能国际', '华电国际', '大唐发电', '国电电力', '浙能电力', '申能', '深圳能源',
      '湖北能源', '内蒙华电', '上海电力', '广州发展', '电力', '水电', '核电', '风电', '光伏',
      '电网', '特高压'])) return '电力/公用事业';

    // Electronics & Semiconductors
    if (_containsAny(n, ['中芯国际', '韦尔股份', '北方华创', '兆易创新', '紫光国微', '卓胜微',
      '圣邦', '思瑞浦', '纳芯微', '北京君正', '国科微', '景嘉微', '长电科技', '通富微电',
      '华天科技', '晶方科技', '士兰微', '华润微', '斯达半导', '时代电气', '扬杰科技', '捷捷微电',
      '三安光电', '海光信息', '寒武纪', '澜起科技', '安路科技', '复旦微电', '半导体', '芯片',
      '集成电路', '晶圆', '封测'])) return '电子/半导体';
    if (_containsAny(n, ['立讯精密', '歌尔股份', '蓝思科技', '领益智造', '信维通信', '环旭电子',
      '工业富联', '鹏鼎控股', '深南电路', '生益科技', '沪电股份', '景旺电子', '东山精密',
      '胜宏科技', '崇达技术', '兴森科技', '超声电子', '依顿电子', 'PCB', 'FPC'])) return '电子元器件';
    if (_containsAny(n, ['京东方', 'TCL科技', '深天马', '维信诺', '彩虹股份', '三利谱',
      '面板', '显示', '偏光'])) return '面板/显示';
    if (_containsAny(n, ['海康威视', '大华股份', '千方科技', '苏州科达', '安防', '监控'])) return '安防';

    // Consumer
    if (_containsAny(n, ['贵州茅台', '五粮液', '泸州老窖', '山西汾酒', '洋河股份', '古井贡酒',
      '今世缘', '迎驾贡酒', '舍得酒业', '酒鬼酒', '水井坊', '口子窖', '金徽酒', '老白干',
      '青岛啤酒', '重庆啤酒', '燕京啤酒', '珠江啤酒', '白酒', '啤酒', '黄酒', '葡萄酒'])) return '白酒';
    if (_containsAny(n, ['伊利股份', '蒙牛', '光明乳业', '新乳业', '妙可蓝多', '乳业', '奶',
      '乳品', '奶粉'])) return '乳制品';
    if (_containsAny(n, ['海天味业', '中炬高新', '千禾味业', '恒顺醋业', '天味食品', '安井食品',
      '涪陵榨菜', '恰恰食品', '三全食品', '绝味食品', '良品铺子', '来伊份', '盐津铺子', '甘源食品',
      '调味', '酱油', '醋', '食品', '零食', '坚果', '卤', '速冻', '预制'])) return '食品饮料';
    if (_containsAny(n, ['美的集团', '格力电器', '海尔智家', '海信家电', '老板电器', '苏泊尔',
      '九阳', '小熊电器', '新宝', '飞科', '科沃斯', '石头科技', '极米', '家电', '电器',
      '空调', '冰箱', '洗衣机', '厨卫', '扫地'])) return '家电';

    // Auto & New Energy
    if (_containsAny(n, ['比亚迪', '长城汽车', '长安汽车', '上汽集团', '广汽集团', '吉利汽车',
      '赛力斯', '江淮汽车', '北汽蓝谷', '小康', '理想', '蔚来', '小鹏', '零跑', '汽车',
      '整车', '乘用车'])) return '汽车';
    if (_containsAny(n, ['福耀玻璃', '华域汽车', '星宇股份', '拓普集团', '德赛西威', '均胜电子',
      '伯特利', '旭升', '文灿', '爱柯迪', '新泉', '继峰', '岱美', '宁波华翔',
      '汽车零部件', '汽配', '轮胎', '轮毂'])) return '汽车零部件';
    if (_containsAny(n, ['宁德时代', '亿纬锂能', '国轩高科', '欣旺达', '孚能科技', '德方纳米',
      '当升科技', '容百科技', '中伟股份', '恩捷股份', '天赐材料', '新宙邦', '多氟多',
      '石大胜华', '璞泰来', '科达利', '先导智能', '赢合科技', '杭可科技', '利元亨',
      '电池', '电解液', '隔膜', '正极', '负极', '锂电'])) return '锂电池';
    if (_containsAny(n, ['隆基绿能', '通威股份', '阳光电源', '晶澳科技', '天合光能', '晶科能源',
      'TCL中环', '福斯特', '福莱特', '爱旭', '东方日升', '锦浪科技', '固德威', '禾迈',
      '昱能', '德业', '上能电气', '光伏', '太阳能', '硅片', '逆变器', '组件'])) return '光伏';
    if (_containsAny(n, ['金风科技', '明阳智能', '运达股份', '东方电缆', '中天科技', '亨通光电',
      '大金重工', '天顺风能', '新强联', '日月股份', '风电', '风机', '海缆', '塔筒'])) return '风电';

    // Healthcare
    if (_containsAny(n, ['恒瑞医药', '百济神州', '信达生物', '君实生物', '荣昌生物', '贝达药业',
      '康方生物', '诺诚健华', '再鼎', '康宁', '创新药', '抗癌', '肿瘤', '生物制药',
      '生物医药'])) return '创新药';
    if (_containsAny(n, ['药明康德', '药明生物', '康龙化成', '泰格医药', '凯莱英', '昭衍新药',
      '博腾股份', '美迪西', '皓元医药', '药石科技', '诺泰生物', '维亚生物', '方达控股',
      'CXO', 'CRO', 'CDMO', '医药研发', '医药外包'])) return '医药研发外包';
    if (_containsAny(n, ['迈瑞医疗', '联影医疗', '鱼跃医疗', '乐普医疗', '微创医疗', '威高',
      '健帆生物', '欧普康视', '爱博医疗', '心脉医疗', '惠泰医疗', '南微医学', '开立医疗',
      '理邦仪器', '医疗器械', '医疗设备', '耗材', '心脉', '骨科', '支架'])) return '医疗器械';
    if (_containsAny(n, ['片仔癀', '云南白药', '同仁堂', '东阿阿胶', '华润三九', '白云山',
      '以岭药业', '天士力', '步长制药', '济川药业', '葵花药业', '马应龙', '九芝堂',
      '广誉远', '众生药业', '康恩贝', '江中药业', '千金药业', '中药', '中成药', '药材'])) return '中药';
    if (_containsAny(n, ['爱尔眼科', '通策医疗', '美年健康', '金域医学', '迪安诊断', '华大基因',
      '国际医学', '新里程', '三星医疗', '海吉亚', '固生堂', '锦欣生殖', '医疗服务',
      '眼科', '牙科', '口腔', '体检', '生殖'])) return '医疗服务';

    // Technology & Internet
    if (_containsAny(n, ['腾讯控股', '阿里巴巴', '美团', '百度', '网易', '京东', '拼多多',
      '快手', '哔哩哔哩', '携程', '同程', '微博', '知乎', '贝壳', '互联网', '网络',
      '电商', '在线', '游戏', '社交'])) return '互联网';
    if (_containsAny(n, ['科大讯飞', '商汤', '云从', '依图', '旷视', '虹软', '格灵深瞳',
      '人工智能', 'AI', '人脸', '语音'])) return '人工智能';
    if (_containsAny(n, ['用友网络', '金蝶', '广联达', '金山办公', '深信服', '奇安信', '启明星辰',
      '安恒信息', '绿盟科技', '中望软件', '致远互联', '泛微', '恒生电子', '宝信软件',
      '石基信息', '卫宁健康', '创业慧康', '东华软件', '中科创达', '诚迈科技', '润和软件',
      '中国软件', '浪潮信息', '中科曙光', '紫光股份', '锐捷网络', '中兴通讯', '软件',
      '信息技术', '信创', 'ERP', '云计算', '信息安全', '网络安全'])) return '计算机/软件';

    // Telecom
    if (_containsAny(n, ['中国移动', '中国电信', '中国联通', '通信', '电信', '5G', '光通信',
      '光纤', '基站', '天线', '射频'])) return '通信';

    // Transportation & Logistics
    if (_containsAny(n, ['中远海控', '中远海能', '招商轮船', '招商南油', '中谷物流', '航运',
      '海运', '港口', '宁波港', '上港集团', '青岛港', '唐山港', '天津港', '盐田港', '北部湾港'])) return '航运/港口';
    if (_containsAny(n, ['顺丰控股', '圆通速递', '韵达股份', '申通快递', '德邦', '京东物流',
      '中通', '极兔', '快递', '物流', '运输'])) return '快递/物流';
    if (_containsAny(n, ['中国国航', '南方航空', '中国东航', '春秋航空', '吉祥航空', '华夏航空',
      '上海机场', '白云机场', '深圳机场', '首都机场', '航空', '机场', '民航'])) return '航空/机场';
    if (_containsAny(n, ['京沪高铁', '大秦铁路', '广深铁路', '铁龙物流', '高铁', '铁路', '轨交'])) return '铁路';

    // Military / Defense
    if (_containsAny(n, ['中航沈飞', '中航西飞', '航发动力', '中直股份', '洪都航空', '中航光电',
      '中航重机', '航天电器', '航天彩虹', '中无人机', '航天电子', '中国卫星', '中国卫通',
      '军工', '航天', '航空工业', '兵器', '导弹', '雷达', '卫星'])) return '军工/航天';

    // Agriculture
    if (_containsAny(n, ['牧原股份', '温氏股份', '新希望', '海大集团', '大北农', '正邦科技',
      '天邦食品', '唐人神', '傲农生物', '巨星农牧', '禾丰', '天康生物', '养猪', '养殖',
      '饲料', '种业', '隆平高科', '登海种业', '荃银高科', '先正达', '北大荒', '农药',
      '化肥', '扬农化工', '利尔化学', '兴发集团', '云天化', '新安股份'])) return '农牧/农化';

    // Media & Entertainment
    if (_containsAny(n, ['分众传媒', '芒果超媒', '光线传媒', '中国电影', '万达电影', '华策影视',
      '慈文传媒', '横店影视', '幸福蓝海', '金逸影视', '广告', '传媒', '影视', '电影',
      '院线', '出版', '凤凰传媒', '中南传媒', '山东出版', '中国出版', '新华文轩', '中信出版',
      '教育'])) return '传媒/教育';

    // Steel
    if (_containsAny(n, ['宝钢股份', '鞍钢股份', '包钢股份', '华菱钢铁', '南钢股份', '马钢股份',
      '首钢股份', '河钢股份', '沙钢股份', '太钢不锈', '新钢股份', '杭钢股份', '方大特钢',
      '柳钢股份', '三钢闽光', '韶钢松山', '重庆钢铁', '中信特钢', '甬金股份', '久立特材',
      '常宝股份', '武进不锈', '钢铁', '特钢', '钢管', '锻钢'])) return '钢铁';

    // Chemicals
    if (_containsAny(n, ['万华化学', '恒力石化', '荣盛石化', '恒逸石化', '华鲁恒升', '宝丰能源',
      '龙佰集团', '巨化股份', '华峰化学', '桐昆股份', '东方盛虹', '鲁西化工', '三友化工',
      '中泰化学', '湖北宜化', '卫星化学', '合盛硅业', '新和成', '浙江龙盛', '闰土股份',
      '安迪苏', '沧州大化', '化学', '化工', '化纤', '聚酯', 'MDI', '钛白粉', '纯碱',
      '氯碱', '氨纶', '涤纶', '粘胶', '有机硅', '氟化工', '磷化工', '煤化工'])) return '化工';

    // Textile & Apparel
    if (_containsAny(n, ['安踏体育', '李宁', '波司登', '海澜之家', '华利集团', '申洲国际',
      '森马服饰', '雅戈尔', '太平鸟', '地素时尚', '比音勒芬', '特步国际', '361度',
      '罗莱生活', '富安娜', '水星家纺', '百隆东方', '鲁泰', '新澳股份', '台华新材',
      '纺织', '服装', '服饰', '家纺', '鞋业', '运动鞋', '制衣', '面料', '羽绒'])) return '纺织服装';

    // Retail
    if (_containsAny(n, ['中国中免', '永辉超市', '苏宁易购', '王府井', '家家悦', '红旗连锁',
      '百联股份', '重庆百货', '天虹股份', '小商品城', '居然之家', '美凯龙', '豫园股份',
      '老凤祥', '周大福', '周大生', '中国黄金', '菜百股份', '免税', '超市', '百货',
      '零售', '商业连锁', '便利店', '珠宝', '黄金首饰'])) return '商业零售';

    // Construction Machinery
    if (_containsAny(n, ['三一重工', '中联重科', '徐工机械', '恒立液压', '浙江鼎力', '柳工',
      '安徽合力', '杭叉集团', '艾迪精密', '建设机械', '山河智能', '厦工', '山推',
      '中铁工业', '铁建重工', '工程机械', '重工', '叉车', '挖掘机', '起重机', '推土机',
      '液压', '桩工'])) return '工程机械';

    // Environmental Protection
    if (_containsAny(n, ['伟明环保', '瀚蓝环境', '碧水源', '清新环境', '启迪环境', '上海环境',
      '绿色动力', '中再资环', '浙富控股', '高能环境', '盈峰环境', '玉禾田', '侨银股份',
      '龙马环卫', '维尔利', '中环环保', '首创环保', '节能环境', '环保', '污水', '垃圾',
      '环卫', '固废', '危废', '水务', '脱硫', '脱硝', '除尘'])) return '环保';

    // Paper & Packaging
    if (_containsAny(n, ['太阳纸业', '晨鸣纸业', '博汇纸业', '山鹰国际', '玖龙纸业', '理文造纸',
      '裕同科技', '合兴包装', '劲嘉股份', '美盈森', '吉宏股份', '环球印务', '造纸',
      '纸业', '包装', '印刷', '纸板', '瓦楞'])) return '造纸/包装';

    // Tourism & Hotels
    if (_containsAny(n, ['锦江酒店', '首旅酒店', '长白山', '中青旅', '宋城演艺', '黄山旅游',
      '峨眉山', '丽江股份', '桂林旅游', '九华旅游', '天目湖', '华住集团', '复星旅游文化',
      '携程集团', '同程旅行', '酒店', '旅游', '景区', '旅行社', '度假村', '索道'])) return '旅游酒店';

    // New Materials
    if (_containsAny(n, ['光威复材', '中简科技', '中复神鹰', '金发科技', '沃特股份', '道恩股份',
      '国瓷材料', '天奈科技', '德方纳米', '当升科技', '容百科技', '中伟股份', '恩捷股份',
      '星源材质', '天赐材料', '新宙邦', '多氟多', '石大胜华', '璞泰来', '碳纤维',
      '新材料', '复合材料', '高温合金', '钛合金', '磁性材料', '稀土永磁', '纳米材料',
      '半导体材料', '电子化学品', '膜材料'])) return '新材料';

    // Glass & Building Materials (non-cement)
    if (_containsAny(n, ['旗滨集团', '南玻', '金晶科技', '信义光能', '信义玻璃', '福莱特',
      '亚玛顿', '洛阳玻璃', '凯盛新能', '玻璃', 'low-e', '镀膜', '光伏玻璃',
      '陶瓷', '瓷砖', '蒙娜丽莎', '东鹏控股', '帝欧家居', '防水材料', '科顺'])) return '玻璃/建材';

    // Non-bank Financial
    if (_containsAny(n, ['九鼎投资', '鲁信创投', '中国信达', '中国华融', '东方资产', '长城资产',
      '蚂蚁集团', '陆金所', '京东数科', '度小满', '马上消费', '金融科技', '互联网金融',
      '小额贷款', '融资租赁', '消费金融', '征信', '支付', 'AMC', '不良资产', '信托',
      '期货', '典当'])) return '非银金融';

    // Dual feature recognition fallback for STAR / ChiNext stocks.
    // If keyword matching fell through to "其他", use exchange + name hints
    // to classify common categories (e.g. energy, electronics) instead of
    // lumping everything into "其他".
    if (code.startsWith('688') || code.startsWith('300') || code.startsWith('301')) {
      // Energy / New-energy keywords in name → 光伏/新能源
      if (_containsAny(n, ['源', '电', '光', '能', '伏', '风', '锂', '电池', '储能',
        '新能源', '光伏', '电力', '太阳能', '逆变'])) {
        return '光伏/新能源';
      }
      // Electronics / Semi keywords → 电子/半导体
      if (_containsAny(n, ['微', '芯', '半导', '集成', '电子', '光电', '传感',
        '晶', '硅', '纳米', '通信', '射频', '模拟'])) {
        return '电子/半导体';
      }
      // Biotech / Pharma keywords → 医药
      if (_containsAny(n, ['药', '医', '生物', '基因', '细胞', '蛋白', '诊断',
        '疗', '制剂', '疫苗'])) {
        return '医药';
      }
      // Software / IT keywords → 计算机/软件
      if (_containsAny(n, ['软件', '信息', '数据', '智能', '网络', '互联',
        '计算', '云', '数字', '科技'])) {
        return '计算机/软件';
      }
      // Advanced manufacturing → 高端制造
      if (_containsAny(n, ['精密', '智能', '自动', '机器', '装备', '制造',
        '激光', '检测', '仪器', '测控'])) {
        return '高端制造';
      }
    }

    return '其他';
  }

  bool _containsAny(String target, List<String> keywords) {
    for (final kw in keywords) {
      if (target.contains(kw)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Color helpers
  // ---------------------------------------------------------------------------

  Color _getProfitColor(double value) {
    if (value > 0) return CupertinoColors.systemRed;
    if (value < 0) return CupertinoColors.systemGreen;
    return CupertinoColors.systemGrey;
  }

  Color _chartColor(int index) => _chartColors[index % _chartColors.length];

  // ---------------------------------------------------------------------------
  // Smart summary
  // ---------------------------------------------------------------------------

  String _generateSmartSummary() {
    final dist = _calculateStyleDistribution();
    if (dist.isEmpty || _weightedHoldings.isEmpty) return '暂无足够数据进行分析。';

    final large = (dist['大盘占比']! * 100).round();
    final mid = (dist['中盘占比']! * 100).round();
    final small = (dist['小盘占比']! * 100).round();
    final valuePct = (dist['价值占比']! * 100).round();
    final growthPct = (dist['成长占比']! * 100).round();

    final topIndustries = _getTopIndustries(count: 3);
    String conclusion = '';

    if (large >= 40) {
      conclusion += '组合偏向大盘风格（大盘股占比$large%），';
    } else if (mid >= 40) {
      conclusion += '组合以中盘股为主（占比$mid%），';
    } else {
      conclusion += '组合偏小盘风格（小盘股占比$small%），';
    }

    if (growthPct >= 40) {
      conclusion += '成长型股票占主导（$growthPct%），进攻性强；';
    } else if (valuePct >= 40) {
      conclusion += '价值型股票占主导（$valuePct%），防御性较好；';
    } else {
      conclusion += '成长与价值风格均衡；';
    }

    if (topIndustries.isNotEmpty) {
      final top = topIndustries.first;
      if (top.key != '其他') {
        conclusion += '重点行业为${top.key}（占比${top.value.toStringAsFixed(1)}%）';
      }
      if (topIndustries.length > 1 && topIndustries[1].key != '其他') {
        conclusion += '、${topIndustries[1].key}（占比${topIndustries[1].value.toStringAsFixed(1)}%）';
      }
      if (topIndustries.length > 2 && topIndustries[2].key != '其他') {
        conclusion += '、${topIndustries[2].key}（占比${topIndustries[2].value.toStringAsFixed(1)}%）';
      }
      conclusion += '。';
    } else {
      conclusion += '行业分布较为分散。';
    }

    final overlapCount = _getOverlapStockCount();
    if (overlapCount > 3) {
      conclusion += '注意：有$overlapCount只股票被多只基金重仓，存在集中风险。';
    }

    return conclusion;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    final subTextColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.6)
        : CupertinoColors.systemGrey;

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 600;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.clientName, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: bgColor,
      ),
      child: SafeArea(
        child: Container(
          color: bgColor,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Module 1+2: Investment pie + Profit/Loss diverging bar ----
              _buildSectionCard(
                title: '持仓分析',
                icon: CupertinoIcons.chart_pie,
                isDark: isDark, cardColor: cardColor,
                textColor: textColor, subTextColor: subTextColor,
                children: [
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildInvestmentPie(isDark, textColor, subTextColor)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildProfitBarChart(isDark, textColor, subTextColor)),
                      ],
                    )
                  else
                    Column(children: [
                      _buildInvestmentPie(isDark, textColor, subTextColor),
                      const SizedBox(height: 24),
                      _buildProfitBarChart(isDark, textColor, subTextColor),
                    ]),
                ],
              ),
              const SizedBox(height: 16),

              // ---- Module 3: Weighted top 10 ----
              _buildSectionCard(
                title: '十大重仓股（按购买权重再统计）',
                icon: CupertinoIcons.star_circle,
                isDark: isDark, cardColor: cardColor,
                textColor: textColor, subTextColor: subTextColor,
                children: [
                  if (_loadingTopHoldings)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else if (_weightedHoldings.isEmpty)
                    Text('暂无重仓股数据', style: TextStyle(fontSize: 13, color: subTextColor))
                  else
                    _buildWeightedHoldingsTable(isDark, textColor, subTextColor),
                ],
              ),
              const SizedBox(height: 16),

              // ---- Module 4: Investment direction analysis ----
              _buildSectionCard(
                title: '投资方向分析',
                icon: CupertinoIcons.scope,
                isDark: isDark, cardColor: cardColor,
                textColor: textColor, subTextColor: subTextColor,
                children: [
                  if (_loadingTopHoldings || _loadingQuotes)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else
                    _buildInvestmentDirectionAnalysis(isDark, textColor, subTextColor),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Module 1: Investment pie chart + legend
  // ---------------------------------------------------------------------------

  Widget _buildInvestmentPie(bool isDark, Color textColor, Color subTextColor) {
    final funds = widget.holdings;
    final total = _totalInvestment;
    if (total <= 0) {
      return _emptySub(title: '投资金额分布', textColor: textColor, subTextColor: subTextColor);
    }

    final sections = <PieChartSectionData>[];
    final legendItems = <Widget>[];

    for (int i = 0; i < funds.length; i++) {
      final h = funds[i];
      final pct = h.totalCost / total * 100;
      if (pct < 0.01) continue;
      final color = _chartColor(i);
      final isTouched = _touchedPieIndex == i;

      sections.add(PieChartSectionData(
        value: h.totalCost, color: color,
        radius: isTouched ? 36 : 28,
        title: '', titleStyle: const TextStyle(fontSize: 0),
        borderSide: isTouched ? const BorderSide(color: CupertinoColors.white, width: 2) : BorderSide.none,
      ));

      legendItems.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isTouched ? 4 : 0, vertical: isTouched ? 2 : 0),
          decoration: BoxDecoration(
            color: isTouched ? color.withValues(alpha: 0.12) : const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Container(width: isTouched ? 10 : 8, height: isTouched ? 10 : 8,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Expanded(child: Text('${h.fundName} (${h.fundCode})',
              style: TextStyle(fontSize: 11, fontWeight: isTouched ? FontWeight.w700 : FontWeight.w400, color: textColor),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            Text('¥${h.totalCost.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 11, fontWeight: isTouched ? FontWeight.w700 : FontWeight.w600, color: textColor)),
            const SizedBox(width: 4),
            Text('${pct.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 11, fontWeight: isTouched ? FontWeight.w600 : FontWeight.w400, color: subTextColor)),
          ]),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('投资金额分布', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        Text('合计 ¥${total.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 100, height: 100,
          child: PieChart(PieChartData(
            sections: sections, centerSpaceRadius: 24, sectionsSpace: 2,
            borderData: FlBorderData(show: false),
            pieTouchData: PieTouchData(
              touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                setState(() {
                  if (!event.isInterestedForInteractions || response == null || response.touchedSection == null) {
                    _touchedPieIndex = -1;
                    return;
                  }
                  _touchedPieIndex = response.touchedSection!.touchedSectionIndex;
                });
              },
            ),
          )),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(children: legendItems)),
      ]),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Module 2: Profit/Loss diverging horizontal bar chart
  // ---------------------------------------------------------------------------

  /// Maximum number of individual fund bars before collapsing the rest into
  /// an "其他基金合计" row.  Prevents the chart from becoming too tall.
  static const int _maxProfitBarRows = 6;

  /// Minimum visible bar fraction so that small holdings don't collapse to a
  /// pixel-wide sliver when a single extreme-value fund dominates the scale.
  static const double _minBarFraction = 0.05;

  Widget _buildProfitBarChart(bool isDark, Color textColor, Color subTextColor) {
    final funds = widget.holdings;
    final maxAbs = _maxAbsProfit;
    final totalProfit = _totalProfit;
    final totalAbs = _totalAbsProfit;

    if (totalAbs < 0.01) {
      return _emptySub(title: '盈亏分布', textColor: textColor, subTextColor: subTextColor);
    }

    // Sort by absolute profit descending so the most impactful funds are shown.
    final sorted = List<FundHolding>.from(funds)
      ..sort((a, b) => b.profit.abs().compareTo(a.profit.abs()));

    final hasOverflow = sorted.length > _maxProfitBarRows;
    final visible = _profitBarExpanded ? sorted : sorted.take(_maxProfitBarRows).toList();
    final overflowFunds = hasOverflow ? sorted.skip(_maxProfitBarRows).toList() : <FundHolding>[];

    // Aggregate overflow funds when collapsed.
    double overflowProfit = 0;
    double overflowAbs = 0;
    if (hasOverflow && !_profitBarExpanded) {
      for (final f in overflowFunds) {
        overflowProfit += f.profit;
        overflowAbs += f.profit.abs();
      }
    }

    Widget buildBarRow(FundHolding h, {double? overrideAbs}) {
      final absProfit = overrideAbs ?? h.profit.abs();
      final profit = overrideAbs != null ? overflowProfit : h.profit;
      final pct = totalAbs > 0 ? absProfit / totalAbs * 100 : 0.0;
      final barFraction = maxAbs > 0 ? (absProfit / maxAbs).clamp(_minBarFraction, 1.0) : _minBarFraction;
      final isProfit = profit > 0;
      final isLoss = profit < 0;
      final barColor = isProfit ? CupertinoColors.systemRed : (isLoss ? CupertinoColors.systemGreen : CupertinoColors.systemGrey);
      final displayName = overrideAbs != null ? '其他基金合计' : h.fundName;

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
            width: 72,
            child: Text(displayName, style: TextStyle(fontSize: 11, color: textColor),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: Text('${profit >= 0 ? '+' : ''}¥${profit.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _getProfitColor(profit)),
              textAlign: TextAlign.right),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(builder: (context, constraints) {
                final barWidth = constraints.maxWidth * barFraction;
                final displayWidth = barWidth.clamp(0.0, constraints.maxWidth);
                return Row(children: [
                  if (isLoss) ...[
                    Expanded(child: Align(alignment: Alignment.centerRight,
                      child: Container(height: 12, width: displayWidth,
                        decoration: BoxDecoration(color: barColor.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3))),
                    )),
                  ] else if (isProfit) ...[
                    Align(alignment: Alignment.centerLeft,
                      child: Container(height: 12, width: displayWidth,
                        decoration: BoxDecoration(color: barColor.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3))),
                    ),
                  ],
                  if (isLoss) Container(width: 1, color: subTextColor.withValues(alpha: 0.4))
                  else Expanded(child: const SizedBox()),
                  if (isProfit) Container(width: 1, color: subTextColor.withValues(alpha: 0.4)),
                ]);
              }),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(width: 38,
            child: Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: subTextColor), textAlign: TextAlign.right)),
        ]),
      );
    }

    final totalColor = _getProfitColor(totalProfit);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('盈亏分布', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        Text('${totalProfit >= 0 ? '+' : ''}¥${totalProfit.toStringAsFixed(0)}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: totalColor)),
      ]),
      const SizedBox(height: 12),
      ...visible.map((h) => buildBarRow(h)),
      // Collapsed "其他" row
      if (hasOverflow && !_profitBarExpanded && overflowAbs > 0)
        buildBarRow(sorted.first, overrideAbs: overflowAbs),
      // Expand / collapse toggle
      if (hasOverflow) ...[
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _profitBarExpanded = !_profitBarExpanded),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_profitBarExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
              size: 14, color: CupertinoColors.systemBlue),
            const SizedBox(width: 4),
            Text(_profitBarExpanded ? '收起' : '展开更多（共${sorted.length}支基金）',
              style: TextStyle(fontSize: 12, color: CupertinoColors.systemBlue)),
          ]),
        ),
      ],
    ]);
  }

  Widget _emptySub({required String title, required Color textColor, required Color subTextColor}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
      const SizedBox(height: 12),
      Text('暂无数据', style: TextStyle(fontSize: 13, color: subTextColor)),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Module 3: Weighted holdings table (top 10, compact)
  // ---------------------------------------------------------------------------

  Widget _buildWeightedHoldingsTable(bool isDark, Color textColor, Color subTextColor) {
    final top = _weightedHoldings.take(10).toList();
    final left = top.take(5).toList();
    final right = top.skip(5).take(5).toList();

    Widget buildItem(int idx, _WeightedHolding wh) {
      final fullCode = _quoteService.toFullCode(wh.stockCode);
      final q = _stockQuotes[fullCode];
      final marketLabel = q?.marketLabel ?? _marketLabelFromCode(wh.stockCode);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 18, child: Text('${idx + 1}', style: TextStyle(fontSize: 10, color: subTextColor))),
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text('${wh.stockName}', style: TextStyle(fontSize: 10, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text('${wh.stockCode}', style: TextStyle(fontSize: 9, color: subTextColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (marketLabel.isNotEmpty) ...[
                const SizedBox(width: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                  decoration: BoxDecoration(
                    color: marketLabel == 'HK' ? CupertinoColors.systemOrange.withValues(alpha: 0.15) : CupertinoColors.systemBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(marketLabel, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600,
                    color: marketLabel == 'HK' ? CupertinoColors.systemOrange : CupertinoColors.systemBlue)),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 4),
          SizedBox(width: 40, child: Text('${wh.weightedRatio.toStringAsFixed(2)}%',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _ratioColor(wh.weightedRatio)),
            textAlign: TextAlign.right)),
          const SizedBox(width: 2),
          SizedBox(width: 24, child: Text('${wh.fundCodes.length}支',
            style: TextStyle(fontSize: 9, color: subTextColor), textAlign: TextAlign.right)),
        ]),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 18, child: Text('#', style: TextStyle(fontSize: 9, color: subTextColor))),
              const Expanded(child: Text('股票', style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey))),
              SizedBox(width: 44, child: Text('权重/基金', style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey), textAlign: TextAlign.right)),
            ]),
          ),
          Container(height: 1, color: CupertinoColors.systemGrey.withValues(alpha: 0.15)),
          ...left.asMap().entries.map((e) => buildItem(e.key, e.value)),
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 18, child: Text('#', style: TextStyle(fontSize: 9, color: subTextColor))),
              const Expanded(child: Text('股票', style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey))),
              SizedBox(width: 44, child: Text('权重/基金', style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey), textAlign: TextAlign.right)),
            ]),
          ),
          Container(height: 1, color: CupertinoColors.systemGrey.withValues(alpha: 0.15)),
          ...right.asMap().entries.map((e) => buildItem(e.key + 5, e.value)),
        ]),
      ),
    ]);
  }

  String _marketLabelFromCode(String code) {
    if (code.length == 5 && RegExp(r'^\d{5}$').hasMatch(code)) return 'HK';
    if (code.startsWith('6')) return '沪A';
    if (code.startsWith('0') || code.startsWith('3') || code.startsWith('5')) return '深A';
    return '';
  }

  Color _ratioColor(double r) {
    if (r >= 5) return CupertinoColors.systemRed;
    if (r >= 2) return const Color(0xFFFF9500);
    return CupertinoColors.systemBlue;
  }

  // ---------------------------------------------------------------------------
  // Module 4: Investment direction analysis
  // ---------------------------------------------------------------------------

  Widget _buildInvestmentDirectionAnalysis(bool isDark, Color textColor, Color subTextColor) {
    final dist = _calculateStyleDistribution();
    final smartSummary = _generateSmartSummary();
    final overlapCount = _getOverlapStockCount();

    if (_weightedHoldings.isEmpty) {
      return Text('暂无重仓股数据可供分析', style: TextStyle(fontSize: 13, color: subTextColor));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Style distribution bars
      if (dist.isNotEmpty) ...[
        Text('风格分布', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        _buildStyleBar('大盘', dist['大盘占比'] ?? 0, CupertinoColors.systemBlue, textColor, subTextColor),
        _buildStyleBar('中盘', dist['中盘占比'] ?? 0, CupertinoColors.systemOrange, textColor, subTextColor),
        _buildStyleBar('小盘', dist['小盘占比'] ?? 0, CupertinoColors.systemGreen, textColor, subTextColor),
        const SizedBox(height: 6),
        _buildStyleBar('价值', dist['价值占比'] ?? 0, const Color(0xFF50C878), textColor, subTextColor),
        _buildStyleBar('成长', dist['成长占比'] ?? 0, CupertinoColors.systemRed, textColor, subTextColor),
        _buildStyleBar('均衡', dist['均衡占比'] ?? 0, const Color(0xFFFFB347), textColor, subTextColor),
        const SizedBox(height: 16),
      ],

      // Industry distribution
      if (_weightedHoldings.isNotEmpty) ...[
        Text('行业分布', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        _buildIndustryDistributionTable(isDark, textColor, subTextColor),
        const SizedBox(height: 16),
      ],

      // Overlapping stocks
      if (overlapCount > 0) ...[
        Text('重叠重仓股（被多支基金持有）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        ..._weightedHoldings.where((w) => w.fundCodes.length > 1).take(6).map((w) => _buildOverlapItem(w, isDark, textColor, subTextColor)),
        const SizedBox(height: 16),
      ],

      // Smart summary
      Text('投资方向总结', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
        child: Text(smartSummary, style: TextStyle(fontSize: 13, color: textColor, height: 1.6)),
      ),
    ]);
  }

  Widget _buildIndustryDistributionTable(bool isDark, Color textColor, Color subTextColor) {
    final industries = _getTopIndustries(count: 8);
    if (industries.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 4, children: industries.map((e) {
      final pct = e.value;
      final totalWeight = _weightedHoldings.fold(0.0, (sum, w) => sum + w.weightedRatio);
      final displayPct = totalWeight > 0 ? (pct / totalWeight * 100) : 0.0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(e.key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(width: 4),
          Text('${displayPct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: subTextColor)),
        ]),
      );
    }).toList());
  }

  Widget _buildStyleBar(String label, double ratio, Color color, Color textColor, Color subTextColor) {
    final pct = (ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 32, child: Text(label, style: TextStyle(fontSize: 12, color: subTextColor))),
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(height: 10, color: CupertinoColors.systemGrey.withValues(alpha: 0.15),
            child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: ratio.clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: color.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3))),
            ),
          ),
        )),
        const SizedBox(width: 8),
        SizedBox(width: 36, child: Text('$pct%', style: TextStyle(fontSize: 12, color: textColor), textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _buildOverlapItem(_WeightedHolding item, bool isDark, Color textColor, Color subTextColor) {
    final fullCode = _quoteService.toFullCode(item.stockCode);
    final q = _stockQuotes[fullCode];
    final marketLabel = q?.marketLabel ?? _marketLabelFromCode(item.stockCode);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Row(children: [
            Flexible(child: Text('${item.stockName} (${item.stockCode})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (marketLabel.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: marketLabel == 'HK' ? CupertinoColors.systemOrange.withValues(alpha: 0.2) : CupertinoColors.systemBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3)),
                child: Text(marketLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                  color: marketLabel == 'HK' ? CupertinoColors.systemOrange : CupertinoColors.systemBlue)),
              ),
            ],
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: CupertinoColors.systemOrange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text('${item.fundCodes.length}支基金持有', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: CupertinoColors.systemOrange)),
          ),
        ]),
        const SizedBox(height: 3),
        Text('覆盖基金: ${item.fundNames.join('、')}', style: TextStyle(fontSize: 11, color: subTextColor), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (q != null) ...[
          const SizedBox(height: 3),
          Text('最新价: ¥${q.price.toStringAsFixed(2)}  PE: ${q.pe?.toStringAsFixed(2) ?? '-'}  PB: ${q.pb?.toStringAsFixed(2) ?? '-'}  市值: ${q.totalMv?.toStringAsFixed(0) ?? '-'}亿',
            style: TextStyle(fontSize: 10, color: subTextColor)),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared section card
  // ---------------------------------------------------------------------------

  Widget _buildSectionCard({
    required String title, required IconData icon,
    required bool isDark, required Color cardColor,
    required Color textColor, required Color subTextColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: CupertinoColors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: CupertinoColors.systemBlue),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
        ]),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }
}

// =============================================================================
// Weighted holding helper
// =============================================================================

class _WeightedHolding {
  final String stockCode;
  final String stockName;
  final double weightedRatio;
  final double totalRatio;
  final Set<String> fundCodes;
  final Set<String> fundNames;

  _WeightedHolding({
    required this.stockCode, required this.stockName,
    required this.weightedRatio, required this.totalRatio,
    required this.fundCodes, required this.fundNames,
  });

  _WeightedHolding add(double wr, double rawRatio, String fundCode, String fundName) {
    final newCodes = Set<String>.from(fundCodes)..add(fundCode);
    final newNames = Set<String>.from(fundNames)..add(fundName);
    return _WeightedHolding(stockCode: stockCode, stockName: stockName,
      weightedRatio: weightedRatio + wr, totalRatio: totalRatio + rawRatio,
      fundCodes: newCodes, fundNames: newNames);
  }
}

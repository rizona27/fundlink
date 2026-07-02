import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../mixins/scroll_to_top_mixin.dart';
import '../utils/animation_config.dart';
import '../widgets/adaptive_top_bar.dart';

/// 操作说明页面
///
/// 采用产品化的设计语言，以功能模块分组展示。
/// 编辑说明：直接修改下方各方法中 GuideSection / GuideItem 的文本即可更新内容。
class GuideView extends StatefulWidget {
  const GuideView({super.key});

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> with ScrollToTopMixin {
  /// Scroll controller for the back-to-top button.
  final ScrollController _scrollController = ScrollController();

  @override
  ScrollController get scrollController => _scrollController;

  /// Which sections are currently expanded.
  /// Uses a Set to allow only one section open at a time for a cleaner UX.
  String? _activeSection;

  /// Which sub-items are currently expanded (keyed by "sectionKey_itemIndex").
  final Set<String> _expandedItems = {};

  /// Current search keyword for filtering guide items.
  String _searchKeyword = '';

  /// GlobalKeys for section and item widgets, used to scroll-into-view on expand.
  final Map<String, GlobalKey> _sectionKeys = {};
  final Map<String, GlobalKey> _itemKeys = {};

  GlobalKey _getSectionKey(String key) {
    return _sectionKeys.putIfAbsent(key, () => GlobalKey());
  }

  GlobalKey _getItemKey(String itemKey) {
    return _itemKeys.putIfAbsent(itemKey, () => GlobalKey());
  }

  void _scrollToKey(GlobalKey key) {
    // Wait for the AnimatedCrossFade size animation to complete (300ms),
    // then scroll the expanded content into view. Using addPostFrameCallback
    // alone fires on the first frame when the widget is still near-zero height.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(AnimationConfig.durationMedium + const Duration(milliseconds: 50), () {
        final ctx = key.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: AnimationConfig.durationMedium,
            curve: AnimationConfig.curveEaseInOutCubic,
            alignment: 0.0,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    });
  }

  void _toggleSection(String key) {
    setState(() {
      if (_activeSection == key) {
        _activeSection = null;
      } else {
        _activeSection = key;
        // Scroll the section header + expanded content into view
        _scrollToKey(_getSectionKey(key));
      }
    });
  }

  void _toggleItem(String itemKey) {
    setState(() {
      if (_expandedItems.contains(itemKey)) {
        _expandedItems.remove(itemKey);
      } else {
        _expandedItems.add(itemKey);
        // Scroll the expanded item into view
        _scrollToKey(_getItemKey(itemKey));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppConstants.isDark(context);
    final bg = isDark ? AppConstants.darkBackground : AppConstants.lightBackground;

    final sections = _buildSections(isDark);
    final hasResults = sections.isNotEmpty;

    return buildWithScrollToTop(
      CupertinoPageScaffold(
        backgroundColor: bg,
        child: SafeArea(
          child: Column(
            children: [
              AdaptiveTopBar(
                scrollOffset: 0,
                showBack: true,
                onBack: () => Navigator.of(context).pop(),
                showRefresh: false,
                showExpandCollapse: false,
                showSearch: true,
                showReset: false,
                showFilter: false,
                showSort: false,
                hasData: true,
                searchText: _searchKeyword,
                searchPlaceholder: '搜索操作说明',
                onSearchChanged: (value) {
                  setState(() {
                    _searchKeyword = value;
                    _applySearchAutoExpand();
                  });
                },
                backgroundColor: Colors.transparent,
                iconColor: CupertinoTheme.of(context).primaryColor,
                iconSize: 24,
                buttonSpacing: 12,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              Expanded(
                child: hasResults
                    ? ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: sections,
                      )
                    : _buildEmptySearchResult(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Builds the empty search result placeholder.
  Widget _buildEmptySearchResult(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 48,
              color: isDark
                  ? CupertinoColors.white.withOpacity(0.2)
                  : CupertinoColors.systemGrey.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '没有找到相关操作说明',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? CupertinoColors.white.withOpacity(0.4)
                    : CupertinoColors.systemGrey.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '尝试使用其他关键词搜索',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? CupertinoColors.white.withOpacity(0.25)
                    : CupertinoColors.systemGrey.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  📝 编辑区域
  //  直接修改下方各 GuideSection 中的 GuideItem 文本即可。
  // ═══════════════════════════════════════════════════════════════════════════

  List<Widget> _buildSections(bool isDark) {
    // Build section data with filtering
    final sectionDefs = [
      _SectionDef(
        key: 'fund',
        icon: CupertinoIcons.chart_bar_fill,
        title: '基金',
        subtitle: '基金列表、排序与估值',
        gradientColors: const [Color(0xFF667EEA), Color(0xFF764BA2)],
        items: _fundItems(),
      ),
      _SectionDef(
        key: 'position',
        icon: CupertinoIcons.person_2_fill,
        title: '持仓',
        subtitle: '客户持仓、交易与盈亏',
        gradientColors: const [Color(0xFFF093FB), Color(0xFFF5576C)],
        items: _positionItems(),
      ),
      _SectionDef(
        key: 'ranking',
        icon: CupertinoIcons.star_fill,
        title: '排名',
        subtitle: '业绩排名与筛选',
        gradientColors: const [Color(0xFF4FACFE), Color(0xFF00F2FE)],
        items: _rankingItems(),
      ),
      _SectionDef(
        key: 'more',
        icon: CupertinoIcons.ellipsis_circle,
        title: '更多',
        subtitle: '数据管理与系统信息',
        gradientColors: const [Color(0xFF43E97B), Color(0xFF38F9D7)],
        items: _moreItems(),
      ),
      _SectionDef(
        key: 'holdings_mgmt',
        icon: CupertinoIcons.square_stack_3d_up,
        title: '持仓管理',
        subtitle: '新增、编辑与维护持仓数据',
        gradientColors: const [Color(0xFF10B981), Color(0xFF34D399)],
        items: _holdingsMgmtItems(),
      ),
      _SectionDef(
        key: 'data_sync',
        icon: CupertinoIcons.wrench,
        title: '数据同步',
        subtitle: '导入、导出与映射索引管理',
        gradientColors: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        items: _dataSyncItems(),
      ),
      _SectionDef(
        key: 'preferences',
        icon: CupertinoIcons.slider_horizontal_3,
        title: '偏好设置',
        subtitle: '主题、隐私与显示偏好',
        gradientColors: const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
        items: _preferencesItems(),
      ),
      _SectionDef(
        key: 'about',
        icon: CupertinoIcons.info,
        title: '关于程序',
        subtitle: '版本信息、日志说明与许可',
        gradientColors: const [Color(0xFFEC4899), Color(0xFFF472B6)],
        items: _aboutItems(),
      ),
      _SectionDef(
        key: 'general',
        icon: CupertinoIcons.gear,
        title: '通用',
        subtitle: '其他组件说明',
        gradientColors: const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
        items: _generalItems(),
      ),
    ];

    final List<Widget> result = [];
    for (final def in sectionDefs) {
      final filteredItems = _filterItems(def.items);
      if (_searchKeyword.isNotEmpty && filteredItems.isEmpty) continue;
      if (result.isNotEmpty) {
        result.add(const SizedBox(height: 12));
      }
      result.add(_buildSection(
        key: def.key,
        icon: def.icon,
        title: def.title,
        subtitle: def.subtitle,
        gradientColors: def.gradientColors,
        items: filteredItems,
        isDark: isDark,
      ));
    }

    return result;
  }

  /// Filters items by search keyword. Returns null for sections with no matches
  /// when searching (so the section is hidden).
  List<_GuideItem> _filterItems(List<_GuideItem> items) {
    if (_searchKeyword.isEmpty) return items;
    final keyword = _searchKeyword.toLowerCase();
    return items.where((item) {
      return item.title.toLowerCase().contains(keyword) ||
          item.description.toLowerCase().contains(keyword);
    }).toList();
  }

  /// When searching, auto-expand matching sections and sub-items.
  void _applySearchAutoExpand() {
    if (_searchKeyword.isEmpty) return;

    // Find which sections have matching items
    final allSections = <String, List<_GuideItem>>{
      'fund': _filterItems(_fundItems()),
      'position': _filterItems(_positionItems()),
      'ranking': _filterItems(_rankingItems()),
      'more': _filterItems(_moreItems()),
      'holdings_mgmt': _filterItems(_holdingsMgmtItems()),
      'data_sync': _filterItems(_dataSyncItems()),
      'preferences': _filterItems(_preferencesItems()),
      'about': _filterItems(_aboutItems()),
      'general': _filterItems(_generalItems()),
    };

    // Auto-expand the first section that has matches
    for (final entry in allSections.entries) {
      if (entry.value.isNotEmpty) {
        _activeSection = entry.key;
        // Auto-expand all matching sub-items in this section
        for (int i = 0; i < entry.value.length; i++) {
          _expandedItems.add('${entry.key}_$i');
        }
        break;
      }
    }
  }

  // ── 基金 ─────────────────────────────────────────────────────────────────

  List<_GuideItem> _fundItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.arrow_up_arrow_down,
        title: '排序分类',
        description: '左上角的排序分类可切换排序方式：无排序、查估值（实时估算涨跌）、近1月/近3月/近6月/近1年收益率。点击排序按钮在不同指标间循环切换，点击右侧箭头切换升序/降序。',
      ),
      _GuideItem(
        icon: CupertinoIcons.arrow_clockwise_circle,
        title: '估值刷新与冷却倒计时按钮',
        description: '在查估值模式下，顶部出现圆形倒计时按钮。数字表示距离下次自动刷新剩余秒数（默认180秒，长按可切换间隔为60秒或300秒）。交易时间内自动刷新，也可点击按钮手动刷新，圆形进度条逐步填满。在非交易时间倒计时暂停，但仍支持手动更新。',
      ),
      _GuideItem(
        icon: CupertinoIcons.tag,
        title: '估值与净值标签说明',
        description: '估（灰色）：实时估值涨跌百分比，交易时间或盘后净值未公布时显示。净（绿色）：盘后净值已公布。净（蓝色）：无估值接口的基金。排序优先级：灰估 > 绿净 > 蓝净。',
      ),
      _GuideItem(
        icon: CupertinoIcons.chevron_down_square,
        title: '基金名称条与展开',
        description: '每只基金名称条按照基金名称和代码组合显示，右侧显示涨跌百分比与标签。点击可展开查看持有该基金近期收益率，分为近1月/近3月/近6月/近1年收益率，也可展示持有客户及收益率排序，用户姓名显示受隐私模式开关规则限制，点击基金名称条展开后右方出现「···」按钮，可进入基金详情页。',
      ),
      _GuideItem(
        icon: CupertinoIcons.chart_bar_alt_fill,
        title: '基金阶段业绩详情页',
        description: '点击基金名称条下方近期业绩卡片，弹出该基金业绩详情，包含近1周/近2周/近3周等不同时间维度阶段收益情况、基金成立日及数据截止日。标注*号的阶段数据为计算所得，未标注的阶段数据为接口获取。',
      ),
    ];
  }

  // ── 持仓 ─────────────────────────────────────────────────────────────────

  List<_GuideItem> _positionItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.person_3,
        title: '总览',
        description: '总览由持有客户的姓名条组成。',
      ),
      _GuideItem(
        icon: CupertinoIcons.person_crop_circle,
        title: '单用户视图',
        description: '点击姓名条会展开该客户下持有基金卡片，点击右侧「···」按钮，进入该用户所有持有的基金金额、投资方向等统计分析。',
      ),
      _GuideItem(
        icon: CupertinoIcons.creditcard,
        title: '基金卡片视图',
        description: '以基金维度展示持有盈亏情况。含总市值、总成本、总盈亏及盈亏百分比等数据。默认按照客户名称拼音排序，可点击基金详情展开查看单只基金，也可以点击交易记录查看该基金加减仓情况。右下角提供了复制客户号和报告按钮，点击复制客户号，或者报告进行快速文字粘贴。',
      ),
      _GuideItem(
        icon: CupertinoIcons.pin_fill,
        title: '置顶与排序',
        description: '在主界面持仓页，右滑持仓基金可置顶/取消置顶。置顶区单独统计置顶后的基金情况，并且在被置顶的基金卡片上增加置顶标记。'
      ),
    ];
  }

  // ── 排名 ─────────────────────────────────────────────────────────────────

  List<_GuideItem> _rankingItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.star,
        title: '排名分类',
        description: '展示不同维度的排序方式，可以按照客户持有金额、天数、收益率、收益进行排序，同时也支持升序或者降序。列表红色表示正收益，绿色表示负收益。',
      ),
      _GuideItem(
        icon: CupertinoIcons.slider_horizontal_3,
        title: '筛选',
        description: '顶部右侧筛选按钮点击后展开筛选模组。支持按持有基金金额、收益、收益率和天数进行筛选或快速定位，可结合排序方式缩小范围。点击筛选按钮左侧重置按钮清除筛选条件。',
      ),
    ];
  }

  // ── 更多 ─────────────────────────────────────────────────────────────────

  List<_GuideItem> _moreItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.ellipsis_circle,
        title: '菜单分类',
        description: '包含持仓管理、数据同步、偏好设置及关于程序四大类菜单及其他综合性功能。具体使用方式查询相应模块。',
      ),
    ];
  }

  // ── 持仓管理 ─────────────────────────────────────────────────────────────

  List<_GuideItem> _holdingsMgmtItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.plus_circle_fill,
        title: '新增持仓',
        description: '点击「新增持仓」进入表单页面，填写客户姓名/客户号、基金代码、购买金额/份额、购买日期和成交净值。系统自动获取基金名称和当前净值。支持当日交易标记，可区分15:00前后交易净值。初始无数据时也可点击主页的「GO」按钮快速新增。',
      ),
      _GuideItem(
        icon: CupertinoIcons.pencil,
        title: '编辑持仓',
        description: '在「编辑持仓」中可查看所有持仓条目，点击进入编辑页面可修改各项数据（客户名、基金代码、金额、日期等），也可针对当前基金执行加仓或减仓操作。系统自动计算平均成本、累计份额并更新盈亏。减仓支持先进先出（FIFO）成本核算。支持左滑删除持仓及关联交易记录。',
      ),
      _GuideItem(
        icon: CupertinoIcons.clock_fill,
        title: '待确认交易',
        description: '当天提交的买入/卖出交易先进入待确认队列，等待净值公布后系统可自动确认（T+1或T+2），也可手动确认。确认前不参与盈亏计算。右上角角标显示待确认交易数量。在交易列表中可查看每条待确认交易的详情、提交时间和预计确认时间。',
      ),
      _GuideItem(
        icon: CupertinoIcons.trash,
        title: '清空持仓数据',
        description: '清空所有持仓记录及关联的交易流水，此操作不可恢复。执行前会弹出两次确认对话框，需分别输入确认文字后才可执行，避免误操作。建议清空前先导出数据备份。',
      ),
    ];
  }

  // ── 数据同步 ─────────────────────────────────────────────────────────────

  List<_GuideItem> _dataSyncItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.book,
        title: '映射索引',
        description: '管理客户号与客户姓名的映射关系。导入持仓数据时系统根据客户号自动匹配姓名。支持页面内手动新增/编辑映射条目，也支持 CSV/Excel 批量导入。映射关系自动同步到已有持仓记录中。导入模板需包含客户号与客户姓名两列。',
      ),
      _GuideItem(
        icon: CupertinoIcons.cloud_download,
        title: '导入数据',
        description: '支持 CSV/Excel 文件导入持仓数据。系统自动识别文件类型（持仓数据/映射索引/完整备份），智能检测编码（UTF-8含BOM/GBK/Latin1）。导入三步流程：选择文件→字段映射（模糊匹配列名，可手动调整）→确认导入。支持桌面端拖拽文件直接导入。提供下载模板功能，一键获取标准导入模板。',
      ),
      _GuideItem(
        icon: CupertinoIcons.cloud_upload,
        title: '导出数据',
        description: '支持导出为 CSV 或 Excel 格式。两种模式：完整备份（导出全部持仓+交易流水，含版本元数据）和自定义导出（20+字段自由组合，支持按基金代码、金额、收益率等条件筛选）。导出后可通过系统分享面板发送到其他应用。',
      ),
      _GuideItem(
        icon: CupertinoIcons.trash,
        title: '清空映射索引',
        description: '清空所有客户号与客户姓名的映射关系，此操作不可恢复。执行前需二次确认。清空后不会影响已有持仓记录，但新导入时将无法自动匹配客户名。',
      ),
    ];
  }

  // ── 偏好设置 ─────────────────────────────────────────────────────────────

  List<_GuideItem> _preferencesItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.lock_fill,
        title: '隐私模式',
        description: '开启后持仓卡片上的客户姓名将按规则脱敏显示，金额和份额数字也被隐藏。适用于截屏转发或公开展示场景，保护客户隐私。关闭后恢复正常显示。切换开关即时生效。',
      ),
      _GuideItem(
        icon: CupertinoIcons.rectangle_stack_person_crop,
        title: '一览卡片',
        description: '控制基金一览页面的基金卡片展开后是否显示持有该基金的客户列表及对应收益。开启后可直观看到每只基金被哪些客户持有，关闭后仅显示基金本身的涨跌信息。切换开关即时生效。',
      ),
      _GuideItem(
        icon: CupertinoIcons.paintbrush_fill,
        title: '主题模式',
        description: '支持三种主题模式：浅色模式、深色模式和跟随系统。点击主题切换按钮循环切换，包括图表配色。选择跟随系统时自动同步系统级别的深色/浅色设置。',
      ),
    ];
  }

  // ── 关于程序 ─────────────────────────────────────────────────────────────

  List<_GuideItem> _aboutItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.info_circle_fill,
        title: '版本信息',
        description: '显示当前版本号、更新历史、简略功能简介和反馈入口。点击版本按钮可检查是否有新版本可用，也可访问作者主页和项目开源地址。点击反馈可以实时推送意见建议给作者，推荐留下联系方式以便回复。',
      ),
      _GuideItem(
        icon: CupertinoIcons.doc_text_search,
        title: '查看日志',
        description: '记录系统各项操作日志，按类型分类（成功/错误/警告/信息/网络/缓存）。支持按类型筛选和关键词搜索，日志按时间倒序排列。点击单条日志可复制到剪贴板。支持分页加载，滚动到底部自动加载更多。',
      ),
      _GuideItem(
        icon: CupertinoIcons.question_circle,
        title: '操作说明',
        description: '即当前页面。以功能模块分组展示各功能的使用说明，支持搜索、折叠/展开分类和子项目。向下滚动后出现返回顶部按钮。内容较长时可使用顶部搜索栏快速定位到相关说明。',
      ),
      _GuideItem(
        icon: CupertinoIcons.lock_shield_fill,
        title: '权限许可',
        description: '查看和管理应用已获取的系统权限，包括存储读写、文件访问、相册保存等。每个权限后面显示其当前授权状态（已授权/未授权/部分授权），点击可跳转系统设置进行修改。',
      ),
      _GuideItem(
        icon: CupertinoIcons.doc_text,
        title: '开源许可',
        description: '本项目采用 GNU Affero General Public License v3.0 (AGPL-3.0) 协议开源。页面展示完整许可文本，明确使用者的权利与义务。项目仅供个人学习与技术交流使用，不构成任何投资建议。',
      ),
    ];
  }

  // ── 通用 ─────────────────────────────────────────────────────────────────

  List<_GuideItem> _generalItems() {
    return [
      _GuideItem(
        icon: CupertinoIcons.play_rectangle,
        title: '初始视图',
        description: '初始状态下点击栏目中间「GO」新增持仓，或者后期可以通过更多-持仓管理-新增持仓添加客户持仓。',
      ),
      _GuideItem(
        icon: CupertinoIcons.ellipsis_circle,
        title: '右上角「···」菜单',
        description: '该按钮为通用按钮，在基金页、持仓页、编辑持仓页存在，点击后展开菜单为刷新/搜索/展开与折叠（在编辑持仓页无刷新功能）。刷新按钮分为点击和长按，点击更新基金净值，优先使用缓存数据；长按为强制刷新，忽略缓存，直接向接口获取网络最新数据。点击搜索在顶部出现搜索栏（失焦后5秒自动隐藏），可根据客户名、客户号、基金名称、基金代码等搜索。展开和折叠按钮，点击展开所有基金卡片，当有一个或一个以上卡片展开时，变为折叠按钮，点击折叠所有基金卡片。',
      ),
      _GuideItem(
        icon: CupertinoIcons.arrow_up_to_line,
        title: '返回顶部按钮',
        description: '向下滚动列表后，右下角出现蓝色圆形返回顶部按钮，点击快速回到列表顶部。',
      ),
      _GuideItem(
        icon: CupertinoIcons.waveform_path_ecg,
        title: '持仓详情与历史净值',
        description: '点击持仓基金详情进入基金详情页。包含估值数据、近期收益率、历史净值走势图、重仓股票等。支持与沪深300/中证500等指数或自定义基金进行对比。历史净值向上滚动则自动加载更早日期的历史净值。',
      ),
      _GuideItem(
        icon: CupertinoIcons.device_phone_portrait,
        title: '跨平台适配',
        description: '应用支持 iOS、Android、Windows、macOS等平台。桌面端支持拖拽文件导入、Tab 键焦点导航、窗口大小自适应。手机端采用底部导航栏，桌面端采用侧边栏布局。所有平台共享同一套代码和数据库格式。',
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  UI 组件 — 产品化设计风格
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSection({
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required List<_GuideItem> items,
    required bool isDark,
  }) {
    final isExpanded = _activeSection == key;

    return Container(
      key: _getSectionKey(key),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.systemGrey6.withOpacity(0.25)
            : CupertinoColors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? gradientColors.first.withOpacity(0.4)
              : (isDark
                  ? CupertinoColors.white.withOpacity(0.06)
                  : CupertinoColors.systemGrey.withOpacity(0.12)),
          width: isExpanded ? 1.2 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? gradientColors.first.withOpacity(isDark ? 0.15 : 0.08)
                : Colors.black.withOpacity(isDark ? 0.08 : 0.02),
            blurRadius: isExpanded ? 12 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Section header ──
          GestureDetector(
            onTap: () => _toggleSection(key),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  // Animated gradient icon badge
                  AnimatedContainer(
                    duration: AnimationConfig.durationMedium,
                    curve: AnimationConfig.curveEaseInOutCubic,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isExpanded
                            ? gradientColors
                            : (isDark
                                ? [
                                    CupertinoColors.systemGrey2.withOpacity(0.5),
                                    CupertinoColors.systemGrey.withOpacity(0.4),
                                  ]
                                : [
                                    CupertinoColors.systemGrey2.withOpacity(0.6),
                                    CupertinoColors.systemGrey.withOpacity(0.5),
                                  ]),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: isExpanded
                          ? [
                              BoxShadow(
                                color: gradientColors.first.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(icon, size: 20, color: CupertinoColors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? CupertinoColors.white.withOpacity(0.45)
                                : CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Expand indicator with item count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? CupertinoColors.white.withOpacity(0.08)
                          : CupertinoColors.systemGrey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${items.length}项',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.45)
                            : CupertinoColors.systemGrey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: AnimationConfig.durationMedium,
                    curve: AnimationConfig.curveEaseInOutCubic,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 17,
                      color: isExpanded
                          ? gradientColors.first
                          : (isDark
                              ? CupertinoColors.white.withOpacity(0.35)
                              : CupertinoColors.systemGrey.withOpacity(0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable body using AnimatedCrossFade for reliable rendering ──
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _buildExpandedContent(key, items, gradientColors, isDark),
            crossFadeState:
                isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: AnimationConfig.durationMedium,
            firstCurve: Curves.easeInOut,
            secondCurve: Curves.easeInOut,
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(
    String sectionKey,
    List<_GuideItem> items,
    List<Color> gradientColors,
    bool isDark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gradient-accented divider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gradientColors.first.withOpacity(0.0),
                  gradientColors.first.withOpacity(0.5),
                  gradientColors.last.withOpacity(0.5),
                  gradientColors.last.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Guide items
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(items.length, (index) {
              final itemKey = '${sectionKey}_$index';
              return _buildGuideCard(
                itemKey: itemKey,
                item: items[index],
                gradientColors: gradientColors,
                isDark: isDark,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildGuideCard({
    required String itemKey,
    required _GuideItem item,
    required List<Color> gradientColors,
    required bool isDark,
  }) {
    final bool isItemExpanded = _expandedItems.contains(itemKey);

    return Container(
      key: _getItemKey(itemKey),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.systemGrey6.withOpacity(0.35)
            : CupertinoColors.systemGrey6.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: gradientColors.first.withOpacity(0.5),
            width: 3,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row — always visible, tappable
          GestureDetector(
            onTap: () => _toggleItem(itemKey),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isDark
                          ? gradientColors.first.withOpacity(0.18)
                          : gradientColors.first.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      item.icon,
                      size: 17,
                      color: isDark ? gradientColors.last : gradientColors.first,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: isDark ? CupertinoColors.white : CupertinoColors.label,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isItemExpanded ? 0.5 : 0,
                    duration: AnimationConfig.durationMedium,
                    curve: AnimationConfig.curveEaseInOutCubic,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 16,
                      color: isItemExpanded
                          ? gradientColors.first
                          : (isDark
                              ? CupertinoColors.white.withOpacity(0.3)
                              : CupertinoColors.systemGrey.withOpacity(0.4)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Description — animated expand/collapse
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 34 + 12), // spacer to align with title text
                  Expanded(
                    child: Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.55)
                            : CupertinoColors.systemGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState:
                isItemExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: AnimationConfig.durationMedium,
            firstCurve: Curves.easeInOut,
            secondCurve: Curves.easeInOut,
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}

// ── Data classes ───────────────────────────────────────────────────────────

class _SectionDef {
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final List<_GuideItem> items;
  const _SectionDef({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.items,
  });
}

class _GuideItem {
  final IconData icon;
  final String title;
  final String description;
  const _GuideItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}

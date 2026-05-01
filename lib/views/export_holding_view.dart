import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../services/data_manager.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../services/file_export_service.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

class ExportHoldingView extends StatefulWidget {
  const ExportHoldingView({super.key});

  @override
  State<ExportHoldingView> createState() => _ExportHoldingViewState();
}

class _ExportHoldingViewState extends State<ExportHoldingView> {
  late DataManager _dataManager;
  
  int _currentStep = 0;

  String _format = 'csv';
  String _scope = 'all';
  final Map<String, String> _filters = {
    'fundCode': '',
    'minAmount': '',
    'maxAmount': '',
    'profitMin': '',
    'profitMax': '',
  };

  String _amountError = '';
  String _profitError = '';

  final List<ExportField> _fields = [
    ExportField(id: 'clientName', label: '客户姓名', required: true, selected: true),
    ExportField(id: 'clientId', label: '客户号', required: true, selected: true),
    ExportField(id: 'fundCode', label: '基金代码', required: true, selected: true),
    ExportField(id: 'purchaseDate', label: '购买日期', required: true, selected: true),
    ExportField(id: 'purchaseAmount', label: '购买金额', required: true, selected: true),
    ExportField(id: 'purchaseShares', label: '购买份额', required: true, selected: true),
    ExportField(id: 'fundName', label: '基金名称', required: false, selected: false),
    ExportField(id: 'currentNav', label: '当前净值', required: false, selected: false),
    ExportField(id: 'navDate', label: '净值日期', required: false, selected: false),
    ExportField(id: 'profit', label: '绝对收益', required: false, selected: false),
    ExportField(id: 'profitRate', label: '绝对收益率(%)', required: false, selected: false),
    ExportField(id: 'annualizedProfitRate', label: '年化收益率(%)', required: false, selected: false),
    ExportField(id: 'holdingDays', label: '持有天数', required: false, selected: false),
    ExportField(id: 'totalValue', label: '持仓市值', required: false, selected: false),
    ExportField(id: 'navReturn1m', label: '近1月收益(%)', required: false, selected: false),
    ExportField(id: 'navReturn3m', label: '近3月收益(%)', required: false, selected: false),
    ExportField(id: 'navReturn6m', label: '近6月收益(%)', required: false, selected: false),
    ExportField(id: 'navReturn1y', label: '近1年收益(%)', required: false, selected: false),
    ExportField(id: 'remarks', label: '备注', required: false, selected: false),
  ];

  List<FundHolding> _filteredHoldings = [];
  int _previewCount = 0;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String? _exportError;
  bool _exportSuccess = false;
  String _exportedFileName = '';

  List<ExportHistoryItem> _exportHistory = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dataManager = DataManagerProvider.of(context);
      _updatePreview();
      FileExportService.setDataManager(_dataManager);
    });
  }

  bool _validateAmountRange() {
    final minStr = _filters['minAmount']!.trim();
    final maxStr = _filters['maxAmount']!.trim();

    if (minStr.isEmpty && maxStr.isEmpty) {
      _amountError = '';
      return true;
    }

    if (minStr.isNotEmpty && maxStr.isEmpty) {
      final min = double.tryParse(minStr);
      if (min == null) {
        _amountError = '最小金额必须为数字';
        return false;
      }
      if (min < 0) {
        _amountError = '最小金额不能小于0';
        return false;
      }
      if (_decimalPlaces(minStr) > 2) {
        _amountError = '金额最多保留2位小数';
        return false;
      }
      _amountError = '';
      return true;
    }

    if (minStr.isEmpty && maxStr.isNotEmpty) {
      final max = double.tryParse(maxStr);
      if (max == null) {
        _amountError = '最大金额必须为数字';
        return false;
      }
      if (_decimalPlaces(maxStr) > 2) {
        _amountError = '金额最多保留2位小数';
        return false;
      }
      _amountError = '';
      return true;
    }

    final min = double.tryParse(minStr);
    final max = double.tryParse(maxStr);
    if (min == null) {
      _amountError = '最小金额必须为数字';
      return false;
    }
    if (max == null) {
      _amountError = '最大金额必须为数字';
      return false;
    }
    if (min < 0) {
      _amountError = '最小金额不能小于0';
      return false;
    }
    if (max <= min) {
      _amountError = '最大金额必须大于最小金额';
      return false;
    }
    if (_decimalPlaces(minStr) > 2 || _decimalPlaces(maxStr) > 2) {
      _amountError = '金额最多保留2位小数';
      return false;
    }
    _amountError = '';
    return true;
  }

  bool _validateProfitRange() {
    final minStr = _filters['profitMin']!.trim();
    final maxStr = _filters['profitMax']!.trim();

    if (minStr.isEmpty && maxStr.isEmpty) {
      _profitError = '';
      return true;
    }

    bool isValidPercent(String s) {
      final val = double.tryParse(s);
      if (val == null) return false;
      if (_decimalPlaces(s) > 2) return false;
      return true;
    }

    if (minStr.isNotEmpty && maxStr.isEmpty) {
      if (!isValidPercent(minStr)) {
        _profitError = '最小收益率必须为数字，最多2位小数';
        return false;
      }
      _profitError = '';
      return true;
    }

    if (minStr.isEmpty && maxStr.isNotEmpty) {
      if (!isValidPercent(maxStr)) {
        _profitError = '最大收益率必须为数字，最多2位小数';
        return false;
      }
      _profitError = '';
      return true;
    }

    final min = double.tryParse(minStr);
    final max = double.tryParse(maxStr);
    if (min == null) {
      _profitError = '最小收益率必须为数字';
      return false;
    }
    if (max == null) {
      _profitError = '最大收益率必须为数字';
      return false;
    }
    if (max <= min) {
      _profitError = '最大收益率必须大于最小收益率';
      return false;
    }
    if (_decimalPlaces(minStr) > 2 || _decimalPlaces(maxStr) > 2) {
      _profitError = '收益率最多保留2位小数';
      return false;
    }
    _profitError = '';
    return true;
  }

  int _decimalPlaces(String s) {
    final dotIndex = s.indexOf('.');
    if (dotIndex == -1) return 0;
    return s.length - dotIndex - 1;
  }

  void _updatePreview() {
    final dataManager = DataManagerProvider.of(context);
    var holdings = List<FundHolding>.from(dataManager.holdings);
    if (_scope == 'filtered') {
      if (_filters['fundCode']!.isNotEmpty) {
        holdings = holdings.where((h) => h.fundCode.contains(_filters['fundCode']!)).toList();
      }
      if (_filters['minAmount']!.isNotEmpty) {
        final min = double.tryParse(_filters['minAmount']!);
        if (min != null) holdings = holdings.where((h) => h.totalCost >= min).toList();
      }
      if (_filters['maxAmount']!.isNotEmpty) {
        final max = double.tryParse(_filters['maxAmount']!);
        if (max != null) holdings = holdings.where((h) => h.totalCost <= max).toList();
      }
      if (_filters['profitMin']!.isNotEmpty) {
        final minProfitPercent = double.tryParse(_filters['profitMin']!);
        if (minProfitPercent != null) {
          holdings = holdings.where((h) => h.profitRate >= minProfitPercent).toList();
        }
      }
      if (_filters['profitMax']!.isNotEmpty) {
        final maxProfitPercent = double.tryParse(_filters['profitMax']!);
        if (maxProfitPercent != null) {
          holdings = holdings.where((h) => h.profitRate <= maxProfitPercent).toList();
        }
      }
    }
    _filteredHoldings = holdings;
    _previewCount = holdings.length;
    setState(() {});
  }

  Future<void> _startExport() async {
    if (_filteredHoldings.isEmpty) {
      context.showToast('没有符合条件的记录');
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportError = null;
      _exportSuccess = false;
      _currentStep = 2;
    });

    try {
      final selectedFieldIds = _fields.where((f) => f.selected).map((f) => f.id).toList();

      _dataManager.addLog('开始导出数据: 格式=$_format, 范围=$_scope, 数量=${_filteredHoldings.length}', type: LogType.info);

      await FileExportService.exportAndDownload(
        holdings: _filteredHoldings,
        format: _format,
        selectedFields: selectedFieldIds,
        context: context,
        shareAfterSave: false,
      );

      final dateStr = DateTime.now().toIso8601String().split('T')[0];
      final fileName = 'fundlink_$dateStr.${_format == 'csv' ? 'csv' : 'xlsx'}';

      _exportSuccess = true;
      _exportedFileName = fileName;
      _saveToHistory(fileName, _filteredHoldings.length);
      // Toast已在FileExportService中显示，此处不再重复提示
      _dataManager.addLog('导出成功: $fileName (${_filteredHoldings.length}条)', type: LogType.success);
    } catch (e) {
      _exportError = e.toString();
      _exportSuccess = false;
      context.showToast('导出失败: $e');
      _dataManager.addLog('导出失败: $e', type: LogType.error);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  void _saveToHistory(String filename, int records) {
    final item = ExportHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch,
      filename: filename,
      date: DateTime.now(),
      format: _format,
      records: records,
    );
    _exportHistory.insert(0, item);
    if (_exportHistory.length > 20) _exportHistory.removeLast();
  }

  Widget _buildStepIndicator() {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepCircle(0, '格式与范围', isDarkMode),
          _stepLine(0, isDarkMode),
          _stepCircle(1, '选择字段', isDarkMode),
          _stepLine(1, isDarkMode),
          _stepCircle(2, '导出结果', isDarkMode),
        ],
      ),
    );
  }

  Widget _stepCircle(int step, String label, bool isDarkMode) {
    final isActive = _currentStep == step;
    final isDone = _currentStep > step;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? const Color(0xFF8B9DC3)
                : (isDone ? const Color(0xFF9BABB8) : (isDarkMode ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey4)),
          ),
          child: Center(
            child: isDone
                ? const Icon(CupertinoIcons.checkmark, size: 16, color: CupertinoColors.white)
                : Text('${step + 1}', style: const TextStyle(color: CupertinoColors.white)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive
                ? const Color(0xFF8B9DC3)
                : (isDarkMode ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey),
          ),
        ),
      ],
    );
  }

  Widget _stepLine(int step, bool isDarkMode) {
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: _currentStep > step
          ? const Color(0xFF9BABB8)
          : (isDarkMode ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey4),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildConfigStep();
      case 1:
        return _buildFieldsStep();
      case 2:
        return _buildResultStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildConfigStep() {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bool isNextEnabled = _previewCount > 0 && _amountError.isEmpty && _profitError.isEmpty;
    return Column(
      children: [
        _buildCard(
          title: '导出格式',
          icon: CupertinoIcons.doc_on_doc,
          isDarkMode: isDarkMode,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: _buildFormatOption('csv', 'CSV', isDarkMode, _format == 'csv')),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFormatOption('excel', 'Excel', isDarkMode, _format == 'excel')),
                ],
              ),
            ),
          ],
        ),
        _buildCard(
          title: '导出范围',
          icon: CupertinoIcons.slider_horizontal_3,
          isDarkMode: isDarkMode,
          children: [
            _buildRadioItem(
              icon: CupertinoIcons.globe,
              title: '全部持仓',
              subtitle: '导出所有持仓数据',
              isDarkMode: isDarkMode,
              selected: _scope == 'all',
              onTap: () {
                setState(() => _scope = 'all');
                _updatePreview();
              },
            ),
            _buildRadioItem(
              icon: CupertinoIcons.slider_horizontal_3,
              title: '筛选结果',
              subtitle: '仅导出符合筛选条件的数据',
              isDarkMode: isDarkMode,
              selected: _scope == 'filtered',
              onTap: () {
                setState(() => _scope = 'filtered');
                _updatePreview();
              },
            ),
          ],
        ),
        if (_scope == 'filtered')
          _buildCard(
            title: '筛选条件',
            icon: CupertinoIcons.search,
            isDarkMode: isDarkMode,
            children: [
              _buildFilterTextField('基金代码', 'fundCode'),
              Row(
                children: [
                  Expanded(child: _buildFilterTextField('最小金额(元)', 'minAmount', isNumber: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildFilterTextField('最大金额(元)', 'maxAmount', isNumber: true)),
                ],
              ),
              if (_amountError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 12, color: Color(0xFFD46B6B)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _amountError,
                          style: const TextStyle(fontSize: 11, color: Color(0xFFD46B6B)),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(child: _buildFilterTextField('最小收益率(%)', 'profitMin', isNumber: true, allowNegative: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildFilterTextField('最大收益率(%)', 'profitMax', isNumber: true, allowNegative: true)),
                ],
              ),
              if (_profitError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 12, color: Color(0xFFD46B6B)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _profitError,
                          style: const TextStyle(fontSize: 11, color: Color(0xFFD46B6B)),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 16),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.4) : CupertinoColors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.eye, size: 16, color: Color(0xFF8B9DC3)),
              const SizedBox(width: 8),
              Text(
                '符合条件的数据：$_previewCount 条',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: '返回',
                onPressed: () => Navigator.of(context).pop(),
                isPrimary: false,
                height: 44,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassButton(
                label: '下一步',
                onPressed: isNextEnabled ? () => setState(() => _currentStep = 1) : null,
                isPrimary: true,
                height: 44,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFieldsStep() {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Column(
      children: [
        _buildCard(
          title: '导出字段',
          icon: CupertinoIcons.checkmark_square,
          isDarkMode: isDarkMode,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _fields.map((field) => _buildFieldChip(field, isDarkMode)).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: '上一步',
                onPressed: () => setState(() => _currentStep = 0),
                isPrimary: false,
                height: 44,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassButton(
                label: '开始导出',
                onPressed: () => _startExport(),
                isPrimary: true,
                height: 44,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultStep() {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Column(
      children: [
        _buildCard(
          title: '导出结果',
          icon: _exportSuccess ? CupertinoIcons.checkmark_circle : CupertinoIcons.exclamationmark_circle,
          isDarkMode: isDarkMode,
          children: [
            if (_isExporting) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const CupertinoActivityIndicator(),
                      const SizedBox(height: 12),
                      const Text('正在生成文件，请稍候...'),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 200,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDarkMode ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: _exportProgress,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B9DC3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_exportSuccess) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(CupertinoIcons.checkmark_alt_circle, size: 48, color: Color(0xFF8B9DC3)),
                      const SizedBox(height: 12),
                      const Text('导出成功！', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('文件名：$_exportedFileName', style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                      const SizedBox(height: 16),
                      GlassButton(
                        label: '完成',
                        onPressed: () => Navigator.of(context).pop(),
                        isPrimary: true,
                        width: 120,
                        height: 40,
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_exportError != null) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 48, color: Color(0xFFD46B6B)),
                      const SizedBox(height: 12),
                      const Text('导出失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_exportError!, style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlassButton(
                            label: '重试',
                            onPressed: () => _startExport(),
                            isPrimary: true,
                            width: 100,
                            height: 40,
                          ),
                          const SizedBox(width: 12),
                          GlassButton(
                            label: '返回',
                            onPressed: () => setState(() => _currentStep = 1),
                            isPrimary: false,
                            width: 100,
                            height: 40,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }


  Widget _buildCard({required String title, required IconData icon, required bool isDarkMode, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.4) : CupertinoColors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDarkMode ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDarkMode ? CupertinoColors.systemGrey5.withOpacity(0.3) : CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: const Color(0xFF8B9DC3)),
                ),
                const SizedBox(width: 12),
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: isDarkMode ? CupertinoColors.white : CupertinoColors.label)),
              ],
            ),
          ),
          if (children.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: isDarkMode ? CupertinoColors.white.withOpacity(0.08) : CupertinoColors.systemGrey4.withOpacity(0.5))),
              ),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }

  Widget _buildRadioItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDarkMode,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      borderRadius: BorderRadius.zero,
      onPressed: onTap,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF8B9DC3).withOpacity(0.15) : (isDarkMode ? CupertinoColors.systemGrey5.withOpacity(0.3) : CupertinoColors.systemGrey6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: selected ? const Color(0xFF8B9DC3) : const Color(0xFF9BABB8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: isDarkMode ? CupertinoColors.white : CupertinoColors.label)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: isDarkMode ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey)),
                ],
              ],
            ),
          ),
          if (selected) const Icon(CupertinoIcons.checkmark_alt, size: 18, color: Color(0xFF8B9DC3)),
        ],
      ),
    );
  }

  Widget _buildFormatOption(String value, String label, bool isDarkMode, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() => _format = value);
        _updatePreview();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B9DC3).withOpacity(0.15) : (isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFF8B9DC3) : (isDarkMode ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey4.withOpacity(0.5))),
        ),
        child: Center(
          child: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? const Color(0xFF8B9DC3) : (isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.label))),
        ),
      ),
    );
  }

  Widget _buildFilterTextField(String label, String key, {bool isNumber = false, bool allowNegative = false}) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: CupertinoTextField(
        placeholder: label,
        placeholderStyle: TextStyle(color: isDarkMode ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey),
        keyboardType: isNumber
            ? TextInputType.numberWithOptions(decimal: true, signed: allowNegative)
            : TextInputType.text,
        onChanged: (v) {
          setState(() {
            _filters[key] = v;
            if (key == 'minAmount' || key == 'maxAmount') {
              _validateAmountRange();
            } else if (key == 'profitMin' || key == 'profitMax') {
              _validateProfitRange();
            }
            _updatePreview();
          });
        },
        decoration: BoxDecoration(
          color: isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildFieldChip(ExportField field, bool isDarkMode) {
    return GestureDetector(
      onTap: field.required ? null : () => setState(() => field.selected = !field.selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: field.selected ? const Color(0xFF8B9DC3).withOpacity(0.15) : (isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.systemGrey6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: field.selected ? const Color(0xFF8B9DC3) : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (field.required)
              const Padding(padding: EdgeInsets.only(right: 4), child: Icon(CupertinoIcons.lock_fill, size: 10, color: Color(0xFF9BABB8))),
            Text(field.label, style: TextStyle(fontSize: 13, color: field.selected ? const Color(0xFF8B9DC3) : (isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.label), fontWeight: field.selected ? FontWeight.w500 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildStepContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExportField {
  final String id;
  final String label;
  final bool required;
  bool selected;
  ExportField({required this.id, required this.label, required this.required, required this.selected});
}

class ExportHistoryItem {
  final int id;
  final String filename;
  final DateTime date;
  final String format;
  final int records;
  ExportHistoryItem({required this.id, required this.filename, required this.date, required this.format, required this.records});
}
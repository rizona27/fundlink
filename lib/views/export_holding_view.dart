import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import '../services/data_manager.dart';
import '../models/fund_holding.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

class ExportHoldingView extends StatefulWidget {
  const ExportHoldingView({super.key});

  @override
  State<ExportHoldingView> createState() => _ExportHoldingViewState();
}

class _ExportHoldingViewState extends State<ExportHoldingView> {
  String _format = 'csv';
  String _scope = 'all';
  final Map<String, String> _filters = {
    'clientName': '',
    'clientId': '',
    'fundCode': '',
    'fundName': '',
    'startDate': '',
    'endDate': '',
    'minAmount': '',
    'maxAmount': '',
  };
  final List<ExportField> _fields = [
    ExportField(id: 'clientName', label: '客户姓名', required: true, selected: true),
    ExportField(id: 'clientId', label: '客户号', required: true, selected: true),
    ExportField(id: 'fundCode', label: '基金代码', required: true, selected: true),
    ExportField(id: 'fundName', label: '基金名称', required: false, selected: true),
    ExportField(id: 'purchaseDate', label: '购买日期', required: true, selected: true),
    ExportField(id: 'purchaseAmount', label: '购买金额', required: true, selected: true),
    ExportField(id: 'purchaseShares', label: '购买份额', required: true, selected: true),
    ExportField(id: 'currentNav', label: '当前净值', required: false, selected: true),
    ExportField(id: 'navDate', label: '净值日期', required: false, selected: true),
    ExportField(id: 'remarks', label: '备注', required: false, selected: false),
  ];

  bool _isExporting = false;
  List<ExportHistoryItem> _exportHistory = [];

  List<FundHolding> _getFilteredHoldings(DataManager dataManager) {
    var holdings = List<FundHolding>.from(dataManager.holdings);
    if (_scope == 'filtered') {
      if (_filters['clientName']!.isNotEmpty) {
        holdings = holdings.where((h) => h.clientName.toLowerCase().contains(_filters['clientName']!.toLowerCase())).toList();
      }
      if (_filters['clientId']!.isNotEmpty) {
        holdings = holdings.where((h) => h.clientId.contains(_filters['clientId']!)).toList();
      }
      if (_filters['fundCode']!.isNotEmpty) {
        holdings = holdings.where((h) => h.fundCode.contains(_filters['fundCode']!)).toList();
      }
      if (_filters['fundName']!.isNotEmpty) {
        holdings = holdings.where((h) => h.fundName.toLowerCase().contains(_filters['fundName']!.toLowerCase())).toList();
      }
      if (_filters['startDate']!.isNotEmpty) {
        final start = DateTime.tryParse(_filters['startDate']!);
        if (start != null) holdings = holdings.where((h) => h.purchaseDate.isAfter(start.subtract(const Duration(days: 1)))).toList();
      }
      if (_filters['endDate']!.isNotEmpty) {
        final end = DateTime.tryParse(_filters['endDate']!);
        if (end != null) holdings = holdings.where((h) => h.purchaseDate.isBefore(end.add(const Duration(days: 1)))).toList();
      }
      if (_filters['minAmount']!.isNotEmpty) {
        final min = double.tryParse(_filters['minAmount']!);
        if (min != null) holdings = holdings.where((h) => h.purchaseAmount >= min).toList();
      }
      if (_filters['maxAmount']!.isNotEmpty) {
        final max = double.tryParse(_filters['maxAmount']!);
        if (max != null) holdings = holdings.where((h) => h.purchaseAmount <= max).toList();
      }
    }
    return holdings;
  }

  Future<void> _export() async {
    final dataManager = DataManagerProvider.of(context);
    final holdings = _getFilteredHoldings(dataManager);
    if (holdings.isEmpty) {
      context.showToast('没有符合条件的记录');
      return;
    }

    setState(() => _isExporting = true);

    try {
      final selectedFields = _fields.where((f) => f.selected).toList();
      final headers = selectedFields.map((f) => f.label).toList();
      final rows = holdings.map((h) {
        return selectedFields.map((f) => _getFieldValue(h, f.id)).toList();
      }).toList();

      final timestamp = DateTime.now();
      final dateStr = '${timestamp.year}${timestamp.month}${timestamp.day}_${timestamp.hour}${timestamp.minute}${timestamp.second}';
      final directory = await getTemporaryDirectory();
      String filePath;
      String fileName;

      if (_format == 'csv') {
        final csv = const ListToCsvConverter().convert([headers, ...rows]);
        fileName = 'fundlink_export_$dateStr.csv';
        filePath = '${directory.path}/$fileName';
        await File(filePath).writeAsString(csv);
      } else {
        final excelFile = excel.Excel.createExcel();
        final sheet = excelFile.sheets['Sheet1'] ?? excelFile['Sheet1'];
        for (int i = 0; i < headers.length; i++) {
          final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0);
          sheet?.cell(cellIndex).value = excel.TextCellValue(headers[i]);
        }
        for (int r = 0; r < rows.length; r++) {
          for (int c = 0; c < rows[r].length; c++) {
            final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1);
            sheet?.cell(cellIndex).value = excel.TextCellValue(rows[r][c].toString());
          }
        }
        fileName = 'fundlink_export_$dateStr.xlsx';
        filePath = '${directory.path}/$fileName';
        final fileBytes = excelFile.encode();
        if (fileBytes != null) await File(filePath).writeAsBytes(fileBytes);
      }

      await Share.shareXFiles([XFile(filePath)], text: '导出持仓数据');
      _saveExportHistory(ExportHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch,
        filename: fileName,
        date: timestamp,
        format: _format,
        records: holdings.length,
      ));
      context.showToast('导出成功，共${holdings.length}条记录');
    } catch (e) {
      context.showToast('导出失败: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  String _getFieldValue(FundHolding holding, String fieldId) {
    switch (fieldId) {
      case 'clientName': return holding.clientName;
      case 'clientId': return holding.clientId;
      case 'fundCode': return holding.fundCode;
      case 'fundName': return holding.fundName;
      case 'purchaseDate': return holding.purchaseDate.toIso8601String().split('T')[0];
      case 'purchaseAmount': return holding.purchaseAmount.toStringAsFixed(2);
      case 'purchaseShares': return holding.purchaseShares.toStringAsFixed(4);
      case 'currentNav': return holding.currentNav.toStringAsFixed(4);
      case 'navDate': return holding.navDate.toIso8601String().split('T')[0];
      case 'remarks': return holding.remarks;
      default: return '';
    }
  }

  void _saveExportHistory(ExportHistoryItem item) {
    _exportHistory.insert(0, item);
    if (_exportHistory.length > 20) _exportHistory.removeLast();
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required bool isDarkMode,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? CupertinoColors.systemGrey6.withOpacity(0.4)
            : CupertinoColors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.04),
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
                    color: isDarkMode
                        ? CupertinoColors.systemGrey5.withOpacity(0.3)
                        : CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: const Color(0xFF8B9DC3)),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
              ],
            ),
          ),
          if (children.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.08)
                        : CupertinoColors.systemGrey4.withOpacity(0.5),
                  ),
                ),
              ),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDarkMode,
    VoidCallback? onTap,
    bool isSelected = false,
    Widget? trailing,
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
              color: isSelected
                  ? const Color(0xFF8B9DC3).withOpacity(0.15)
                  : (isDarkMode
                  ? CupertinoColors.systemGrey5.withOpacity(0.3)
                  : CupertinoColors.systemGrey6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF8B9DC3) : const Color(0xFF9BABB8),
            ),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? CupertinoColors.white.withOpacity(0.6)
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else if (onTap != null)
            Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.4)
                  : CupertinoColors.systemGrey.withOpacity(0.6),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterTextField(String label, String key, {bool isDate = false, bool isNumber = false}) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: CupertinoTextField(
        placeholder: label,
        placeholderStyle: TextStyle(
          color: isDarkMode
              ? CupertinoColors.white.withOpacity(0.5)
              : CupertinoColors.systemGrey,
        ),
        keyboardType: isDate ? TextInputType.datetime : (isNumber ? TextInputType.number : TextInputType.text),
        onChanged: (v) => setState(() => _filters[key] = v),
        decoration: BoxDecoration(
          color: isDarkMode
              ? CupertinoColors.systemGrey6.withOpacity(0.3)
              : CupertinoColors.white,
          borderRadius: BorderRadius.circular(10),
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
      navigationBar: CupertinoNavigationBar(
        middle: const Text('导出持仓数据'),
        previousPageTitle: '设置',
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 导出格式
              _buildSection(
                title: '导出格式',
                icon: CupertinoIcons.doc_on_doc,
                isDarkMode: isDarkMode,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildFormatOption('csv', 'CSV', isDarkMode, _format == 'csv'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFormatOption('excel', 'Excel', isDarkMode, _format == 'excel'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),

              // 导出范围
              _buildSection(
                title: '导出范围',
                icon: CupertinoIcons.slider_horizontal_3,
                isDarkMode: isDarkMode,
                children: [
                  _buildMenuItem(
                    icon: CupertinoIcons.globe,
                    title: '全部持仓',
                    subtitle: '导出所有持仓数据',
                    isDarkMode: isDarkMode,
                    onTap: () => setState(() => _scope = 'all'),
                    isSelected: _scope == 'all',
                  ),
                  _buildMenuItem(
                    icon: CupertinoIcons.slider_horizontal_3,
                    title: '筛选结果',
                    subtitle: '仅导出符合筛选条件的数据',
                    isDarkMode: isDarkMode,
                    onTap: () => setState(() => _scope = 'filtered'),
                    isSelected: _scope == 'filtered',
                  ),
                ],
              ),

              // 筛选条件（条件显示）
              if (_scope == 'filtered')
                _buildSection(
                  title: '筛选条件',
                  icon: CupertinoIcons.search,
                  isDarkMode: isDarkMode,
                  children: [
                    _buildFilterTextField('客户姓名', 'clientName'),
                    _buildFilterTextField('客户号', 'clientId'),
                    _buildFilterTextField('基金代码', 'fundCode'),
                    _buildFilterTextField('基金名称', 'fundName'),
                    Row(
                      children: [
                        Expanded(child: _buildFilterTextField('开始日期', 'startDate', isDate: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildFilterTextField('结束日期', 'endDate', isDate: true)),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: _buildFilterTextField('最小金额', 'minAmount', isNumber: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildFilterTextField('最大金额', 'maxAmount', isNumber: true)),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),

              // 导出字段
              _buildSection(
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

              // 导出按钮
              const SizedBox(height: 8),
              Center(
                child: GlassButton(
                  label: _isExporting ? '导出中...' : '开始导出',
                  onPressed: _isExporting ? null : _export,
                  isPrimary: true,
                  width: 200,
                  height: 48,
                ),
              ),

              // 导出历史
              if (_exportHistory.isNotEmpty)
                const SizedBox(height: 16),
              if (_exportHistory.isNotEmpty)
                _buildSection(
                  title: '导出历史',
                  icon: CupertinoIcons.time,
                  isDarkMode: isDarkMode,
                  children: _exportHistory.map((item) => _buildHistoryItem(item, isDarkMode)).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormatOption(String value, String label, bool isDarkMode, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _format = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF8B9DC3).withOpacity(0.15)
              : (isDarkMode
              ? CupertinoColors.systemGrey6.withOpacity(0.3)
              : CupertinoColors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF8B9DC3)
                : (isDarkMode
                ? CupertinoColors.white.withOpacity(0.1)
                : CupertinoColors.systemGrey4.withOpacity(0.5)),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? const Color(0xFF8B9DC3)
                  : (isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.label),
            ),
          ),
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
          color: field.selected
              ? const Color(0xFF8B9DC3).withOpacity(0.15)
              : (isDarkMode
              ? CupertinoColors.systemGrey6.withOpacity(0.3)
              : CupertinoColors.systemGrey6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: field.selected
                ? const Color(0xFF8B9DC3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (field.required)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(CupertinoIcons.lock_fill, size: 10, color: const Color(0xFF9BABB8)),
              ),
            Text(
              field.label,
              style: TextStyle(
                fontSize: 13,
                color: field.selected
                    ? const Color(0xFF8B9DC3)
                    : (isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.label),
                fontWeight: field.selected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(ExportHistoryItem item, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? CupertinoColors.systemGrey5.withOpacity(0.3)
                  : CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              item.format == 'csv' ? CupertinoIcons.doc_text : CupertinoIcons.table,
              size: 18,
              color: const Color(0xFF9BABB8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.filename,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.records}条记录 · ${_formatDate(item.date)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.5)
                        : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => context.showToast('重新分享功能暂未实现'),
            child: Icon(
              CupertinoIcons.share,
              size: 18,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.6)
                  : CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
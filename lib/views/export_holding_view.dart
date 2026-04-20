import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import '../services/data_manager.dart';
import '../models/fund_holding.dart';
import '../widgets/toast.dart';

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
  double _exportProgress = 0;
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

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
    });

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
      setState(() {
        _isExporting = false;
        _exportProgress = 0;
      });
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

  Widget _buildCard({required List<Color> gradientColors, required bool isDark, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: gradientColors[0].withOpacity(0.25), blurRadius: 6, offset: const Offset(3, 3)),
          BoxShadow(color: isDark ? Colors.black.withOpacity(0.15) : Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(1, 1)),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('导出持仓数据'),
        previousPageTitle: '设置',
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildCard(
                gradientColors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('导出格式', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _formatOption('csv', 'CSV', '标准CSV格式'),
                        const SizedBox(width: 16),
                        _formatOption('excel', 'Excel', 'Excel格式'),
                      ],
                    ),
                  ],
                ),
              ),
              _buildCard(
                gradientColors: [const Color(0xFF10B981), const Color(0xFF34D399)],
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('导出范围', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _scopeOption('all', '全部持仓'),
                    const SizedBox(height: 8),
                    _scopeOption('filtered', '筛选结果'),
                  ],
                ),
              ),
              if (_scope == 'filtered')
                _buildCard(
                  gradientColors: [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('筛选条件', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _filterTextField('客户姓名', 'clientName'),
                      _filterTextField('客户号', 'clientId'),
                      _filterTextField('基金代码', 'fundCode'),
                      _filterTextField('基金名称', 'fundName'),
                      Row(
                        children: [
                          Expanded(child: _filterTextField('开始日期', 'startDate', isDate: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _filterTextField('结束日期', 'endDate', isDate: true)),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: _filterTextField('最小金额', 'minAmount', isNumber: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _filterTextField('最大金额', 'maxAmount', isNumber: true)),
                        ],
                      ),
                    ],
                  ),
                ),
              _buildCard(
                gradientColors: [const Color(0xFFEC4899), const Color(0xFFF472B6)],
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('选择导出字段', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _fields.map((field) {
                        return Material(
                          color: Colors.transparent,
                          child: FilterChip(
                            label: Text(field.label),
                            selected: field.selected,
                            onSelected: field.required ? null : (v) => setState(() => field.selected = v),
                            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                            selectedColor: CupertinoColors.activeBlue.withOpacity(0.3),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton(
                onPressed: _isExporting ? null : _export,
                color: CupertinoColors.activeBlue,
                child: _isExporting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('开始导出'),
              ),
              if (_exportHistory.isNotEmpty)
                _buildCard(
                  gradientColors: [const Color(0xFF6B7280), const Color(0xFF9CA3AF)],
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('导出历史', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ..._exportHistory.map((item) => ListTile(
                        title: Text(item.filename),
                        subtitle: Text('${item.records}条记录 · ${item.date.toLocal().toString().substring(0, 16)}'),
                        trailing: IconButton(
                          icon: const Icon(CupertinoIcons.share),
                          onPressed: () => context.showToast('重新分享功能暂未实现'),
                        ),
                      )),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formatOption(String value, String name, String desc) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _format = value),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: _format == value ? CupertinoColors.activeBlue : CupertinoColors.systemGrey4),
            borderRadius: BorderRadius.circular(8),
            color: _format == value ? CupertinoColors.activeBlue.withOpacity(0.1) : null,
          ),
          child: Column(
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(desc, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeOption(String value, String label) {
    return Row(
      children: [
        CupertinoRadio(
          value: value,
          groupValue: _scope,
          onChanged: (v) => setState(() => _scope = v!),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }

  Widget _filterTextField(String label, String key, {bool isDate = false, bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CupertinoTextField(
        placeholder: label,
        keyboardType: isDate ? TextInputType.datetime : (isNumber ? TextInputType.number : TextInputType.text),
        onChanged: (v) => setState(() => _filters[key] = v),
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
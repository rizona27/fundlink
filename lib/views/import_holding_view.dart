import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import '../services/data_manager.dart';
import '../models/fund_holding.dart';
import '../widgets/toast.dart';

class ImportHoldingView extends StatefulWidget {
  const ImportHoldingView({super.key});

  @override
  State<ImportHoldingView> createState() => _ImportHoldingViewState();
}

class _ImportHoldingViewState extends State<ImportHoldingView> {
  int _currentStep = 1;
  FilePickerResult? _fileResult;
  String? _fileName;
  List<String> _headers = [];
  List<List<dynamic>> _rawData = [];
  bool _isProcessing = false;

  final List<FieldConfig> _fieldConfigs = [
    FieldConfig(id: 'clientName', label: '客户姓名', required: true, mappedIndex: -1),
    FieldConfig(id: 'clientId', label: '客户号', required: true, mappedIndex: -1),
    FieldConfig(id: 'fundCode', label: '基金代码', required: true, mappedIndex: -1),
    FieldConfig(id: 'fundName', label: '基金名称', required: false, mappedIndex: -1),
    FieldConfig(id: 'purchaseDate', label: '购买日期', required: true, mappedIndex: -1),
    FieldConfig(id: 'purchaseAmount', label: '购买金额', required: true, mappedIndex: -1),
    FieldConfig(id: 'purchaseShares', label: '购买份额', required: true, mappedIndex: -1),
    FieldConfig(id: 'currentNav', label: '当前净值', required: false, mappedIndex: -1),
    FieldConfig(id: 'navDate', label: '净值日期', required: false, mappedIndex: -1),
    FieldConfig(id: 'remarks', label: '备注', required: false, mappedIndex: -1),
  ];

  List<Map<String, dynamic>> _previewData = [];
  bool _isImporting = false;
  double _importProgress = 0;
  ImportResult? _importResult;

  bool get _allRequiredMapped => _fieldConfigs.where((f) => f.required).every((f) => f.mappedIndex != -1);
  int get _validRowsCount => _previewData.length;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('导入持仓数据'),
        previousPageTitle: '设置',
        trailing: _currentStep < 3
            ? CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _currentStep == 1 && _fileResult != null ? _processFile : null,
          child: Text(_currentStep == 1 ? '下一步' : '下一步'),
        )
            : null,
      ),
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

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepCircle(1, '上传文件'),
          _stepLine(1),
          _stepCircle(2, '字段映射'),
          _stepLine(2),
          _stepCircle(3, '预览导入'),
        ],
      ),
    );
  }

  Widget _stepCircle(int step, String label) {
    final isActive = _currentStep == step;
    final isDone = _currentStep > step;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? CupertinoColors.activeBlue : (isDone ? CupertinoColors.systemGreen : CupertinoColors.systemGrey4),
          ),
          child: Center(
            child: isDone
                ? const Icon(CupertinoIcons.checkmark, size: 16, color: CupertinoColors.white)
                : Text('$step', style: const TextStyle(color: CupertinoColors.white)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _stepLine(int step) {
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: _currentStep > step ? CupertinoColors.systemGreen : CupertinoColors.systemGrey4,
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildUploadStep();
      case 2:
        return _buildMappingStep();
      case 3:
        return _buildPreviewStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildUploadStep() {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return _buildCard(
      gradientColors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
      isDark: isDark,
      child: Column(
        children: [
          CupertinoButton(
            onPressed: _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(CupertinoIcons.cloud_upload, size: 48, color: CupertinoTheme.of(context).primaryColor),
                  const SizedBox(height: 12),
                  Text(_fileName ?? '点击选择CSV或Excel文件', style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (result != null) {
      setState(() {
        _fileResult = result;
        _fileName = result.files.single.name;
      });
      _processFile();
    }
  }

  // 辅助函数：从 Excel 单元格提取纯文本（适配 excel 4.x）
  String _getCellValue(dynamic cell) {
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    if (val is excel.TextCellValue) {
      // TextCellValue.value 是 TextSpan，取 text 属性，可能为 null，提供空字符串兜底
      return val.value.text ?? '';
    }
    if (val is excel.IntCellValue) return val.value.toString();
    if (val is excel.DoubleCellValue) return val.value.toString();
    if (val is excel.DateTimeCellValue) {
      return '${val.year}-${val.month}-${val.day}';
    }
    return val.toString();
  }

  Future<void> _processFile() async {
    if (_fileResult == null) return;
    setState(() => _isProcessing = true);
    try {
      final file = _fileResult!.files.single;
      final bytes = file.bytes!;
      final extension = file.extension?.toLowerCase();

      if (extension == 'csv') {
        final csvString = utf8.decode(bytes);
        final rows = const CsvToListConverter().convert(csvString);
        if (rows.isNotEmpty) {
          _headers = rows.first.map((e) => e.toString()).toList();
          _rawData = rows.skip(1).toList();
        }
      } else if (extension == 'xlsx' || extension == 'xls') {
        final excelFile = excel.Excel.decodeBytes(bytes);
        final sheet = excelFile.tables[excelFile.tables.keys.first];
        if (sheet != null) {
          _headers = sheet.rows.first.map((cell) => _getCellValue(cell)).toList();
          _rawData = sheet.rows.skip(1).map((row) => row.map((cell) => _getCellValue(cell)).toList()).toList();
        }
      }

      _autoSuggestMapping();
      setState(() => _currentStep = 2);
    } catch (e) {
      context.showToast('解析文件失败: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _autoSuggestMapping() {
    for (var config in _fieldConfigs) {
      config.mappedIndex = -1;
      for (int i = 0; i < _headers.length; i++) {
        final header = _headers[i].toLowerCase();
        if (header.contains(config.label.toLowerCase()) || header.contains(config.id.toLowerCase())) {
          config.mappedIndex = i;
          break;
        }
      }
    }
  }

  Widget _buildMappingStep() {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return _buildCard(
      gradientColors: [const Color(0xFF10B981), const Color(0xFF34D399)],
      isDark: isDark,
      child: Column(
        children: [
          for (var config in _fieldConfigs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      config.label,
                      style: TextStyle(
                        fontWeight: config.required ? FontWeight.bold : FontWeight.normal,
                        color: config.required ? CupertinoColors.systemRed : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => _showMappingPicker(config),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: CupertinoColors.systemGrey4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(config.mappedIndex != -1 ? _headers[config.mappedIndex] : '未映射'),
                            const Icon(CupertinoIcons.chevron_down, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          CupertinoButton(
            onPressed: _allRequiredMapped ? () => _buildPreview() : null,
            color: CupertinoColors.activeBlue,
            child: const Text('下一步'),
          ),
        ],
      ),
    );
  }

  void _showMappingPicker(FieldConfig config) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 300,
        color: CupertinoTheme.of(context).scaffoldBackgroundColor,
        child: CupertinoPicker(
          itemExtent: 44,
          onSelectedItemChanged: (index) {
            setState(() {
              if (index == 0) {
                config.mappedIndex = -1;
              } else {
                config.mappedIndex = index - 1;
              }
            });
          },
          children: [
            const Text('不映射'),
            ..._headers.map((h) => Text(h)),
          ],
        ),
      ),
    );
  }

  void _buildPreview() {
    _previewData = [];
    for (var row in _rawData) {
      final map = <String, dynamic>{};
      for (var config in _fieldConfigs) {
        if (config.mappedIndex != -1 && config.mappedIndex < row.length) {
          map[config.id] = row[config.mappedIndex];
        }
      }
      if (map['clientName'] != null && map['clientId'] != null && map['fundCode'] != null &&
          map['purchaseDate'] != null && map['purchaseAmount'] != null && map['purchaseShares'] != null) {
        _previewData.add(map);
      }
    }
    setState(() => _currentStep = 3);
  }

  Widget _buildPreviewStep() {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Column(
      children: [
        _buildCard(
          gradientColors: [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('数据预览 (${_previewData.length}条有效记录)', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (_previewData.isNotEmpty)
                Container(
                  height: 200,
                  child: ListView.builder(
                    itemCount: _previewData.length > 5 ? 5 : _previewData.length,
                    itemBuilder: (context, index) {
                      final item = _previewData[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${item['clientName']} - ${item['fundCode']} - ${item['purchaseAmount']}'),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              if (_isImporting)
                Column(
                  children: [
                    LinearProgressIndicator(value: _importProgress),
                    const SizedBox(height: 8),
                    Text('导入中... ${(_importProgress * 100).toInt()}%'),
                  ],
                ),
              if (_importResult != null)
                Column(
                  children: [
                    Icon(
                      _importResult!.successCount > 0 ? CupertinoIcons.checkmark_alt_circle_fill : CupertinoIcons.exclamationmark_triangle_fill,
                      color: _importResult!.successCount > 0 ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
                    ),
                    const SizedBox(height: 8),
                    Text('成功: ${_importResult!.successCount}, 失败: ${_importResult!.failCount}'),
                    if (_importResult!.errors.isNotEmpty)
                      Text('错误: ${_importResult!.errors.first}', style: const TextStyle(color: CupertinoColors.systemRed)),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CupertinoButton(
                    onPressed: _isImporting ? null : () => setState(() => _currentStep = 2),
                    child: const Text('上一步'),
                  ),
                  CupertinoButton(
                    onPressed: _isImporting ? null : _startImport,
                    color: CupertinoColors.activeBlue,
                    child: const Text('开始导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _startImport() async {
    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importResult = null;
    });

    final dataManager = DataManagerProvider.of(context);
    int success = 0;
    int fail = 0;
    List<String> errors = [];

    for (int i = 0; i < _previewData.length; i++) {
      final row = _previewData[i];
      try {
        final clientName = row['clientName'].toString();
        final clientId = row['clientId'].toString();
        final fundCode = row['fundCode'].toString();
        final fundName = row['fundName']?.toString() ?? '';
        final purchaseDate = _parseDate(row['purchaseDate'].toString());
        final purchaseAmount = double.parse(row['purchaseAmount'].toString());
        final purchaseShares = double.parse(row['purchaseShares'].toString());

        final currentNav = row['currentNav'] != null ? double.tryParse(row['currentNav'].toString()) ?? 0.0 : 0.0;
        final navDate = row['navDate'] != null ? _parseDate(row['navDate'].toString()) : DateTime.now();
        final remarks = row['remarks']?.toString() ?? '';
        final isValid = currentNav > 0;

        final holding = FundHolding(
          clientName: clientName,
          clientId: clientId,
          fundCode: fundCode,
          fundName: fundName,
          purchaseAmount: purchaseAmount,
          purchaseShares: purchaseShares,
          purchaseDate: purchaseDate,
          navDate: navDate,
          currentNav: currentNav,
          isValid: isValid,
          remarks: remarks,
          isPinned: false,
          pinnedTimestamp: null,
          navReturn1m: null,
          navReturn3m: null,
          navReturn6m: null,
          navReturn1y: null,
        );
        await dataManager.addHolding(holding);
        success++;
      } catch (e) {
        fail++;
        errors.add('第${i+1}行: $e');
      }
      setState(() => _importProgress = (i+1) / _previewData.length);
    }

    setState(() {
      _isImporting = false;
      _importResult = ImportResult(successCount: success, failCount: fail, errors: errors);
    });
    context.showToast('导入完成，成功$success条，失败$fail条');
  }

  DateTime _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    }
    return DateTime.now();
  }
}

class FieldConfig {
  final String id;
  final String label;
  final bool required;
  int mappedIndex;
  FieldConfig({required this.id, required this.label, required this.required, required this.mappedIndex});
}

class ImportResult {
  final int successCount;
  final int failCount;
  final List<String> errors;
  ImportResult({required this.successCount, required this.failCount, required this.errors});
}
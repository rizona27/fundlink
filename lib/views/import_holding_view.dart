import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:universal_html/html.dart' as html;
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

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
    FieldConfig(id: 'clientName', label: '客户姓名', required: true, mappedIndex: -1, hint: '客户姓名/客户名/姓名'),
    FieldConfig(id: 'clientId', label: '客户号', required: true, mappedIndex: -1, hint: '客户号/客户编号/核心客户号'),
    FieldConfig(id: 'fundCode', label: '基金代码', required: true, mappedIndex: -1, hint: '基金代码/产品代码'),
    FieldConfig(id: 'purchaseAmount', label: '购买金额', required: true, mappedIndex: -1, hint: '购买金额/金额/申购金额/成本'),
    FieldConfig(id: 'purchaseShares', label: '购买份额', required: true, mappedIndex: -1, hint: '份额/当前份额/持仓份额'),
    FieldConfig(id: 'purchaseDate', label: '购买日期', required: true, mappedIndex: -1, hint: '购买日期/申购日期/成交日期'),
    FieldConfig(id: 'transactionType', label: '交易类型', required: false, mappedIndex: -1, hint: '加仓/减仓(选填)'),
    FieldConfig(id: 'transactionAmount', label: '交易金额', required: false, mappedIndex: -1, hint: '加仓/减仓金额(选填)'),
    FieldConfig(id: 'transactionShares', label: '交易份额', required: false, mappedIndex: -1, hint: '加仓/减仓份额(选填)'),
    FieldConfig(id: 'transactionDate', label: '交易日期', required: false, mappedIndex: -1, hint: '加仓/减仓日期(选填)'),
  ];

  List<Map<String, dynamic>> _previewData = [];
  List<Map<String, dynamic>> _validData = [];
  List<Map<String, dynamic>> _invalidData = [];
  List<String> _invalidReasons = [];
  bool _isImporting = false;
  double _importProgress = 0;
  ImportResult? _importResult;
  bool _importCompleted = false;

  bool get _allRequiredMapped => _fieldConfigs.where((f) => f.required).every((f) => f.mappedIndex != -1);
  int get _validRowsCount => _validData.length;
  int get _invalidRowsCount => _invalidData.length;

  int? _tempMappedIndex;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            _buildStepIndicator(isDarkMode),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildStepContent(isDarkMode),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepCircle(1, '选择文件', isDarkMode),
          _stepLine(1, isDarkMode),
          _stepCircle(2, '字段映射', isDarkMode),
          _stepLine(2, isDarkMode),
          _stepCircle(3, '导入确认', isDarkMode),
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
                : (isDone
                ? const Color(0xFF9BABB8)
                : (isDarkMode ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey4)),
          ),
          child: Center(
            child: isDone
                ? const Icon(CupertinoIcons.checkmark, size: 16, color: CupertinoColors.white)
                : Text('$step', style: const TextStyle(color: CupertinoColors.white)),
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

  Widget _buildStepContent(bool isDarkMode) {
    switch (_currentStep) {
      case 1:
        return _buildUploadStep(isDarkMode);
      case 2:
        return _buildMappingStep(isDarkMode);
      case 3:
        return _buildConfirmStep(isDarkMode);
      default:
        return const SizedBox();
    }
  }

  Widget _buildUploadStep(bool isDarkMode) {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.cloud_upload,
                  size: 48,
                  color: const Color(0xFF8B9DC3),
                ),
                const SizedBox(height: 16),
                Text(
                  _fileName ?? '点击选择CSV或Excel文件',
                  style: TextStyle(
                    fontSize: 15,
                    color: _fileName != null
                        ? const Color(0xFF8B9DC3)
                        : (isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey),
                  ),
                ),
                if (_fileName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '已选择文件，点击"下一步"继续',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? CupertinoColors.white.withOpacity(0.5)
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassButton(
              label: '下载模板',
              onPressed: _downloadTemplate,
              isPrimary: false,
              width: null,
              minWidth: 120,
              height: 44,
            ),
            const SizedBox(width: 12),
            GlassButton(
              label: '返回',
              onPressed: () => Navigator.of(context).pop(),
              isPrimary: false,
              width: null,
              minWidth: 120,
              height: 44,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMappingStep(bool isDarkMode) {
    return Column(
      children: [
        Container(
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
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.arrow_2_squarepath, size: 16, color: Color(0xFF8B9DC3)),
                    SizedBox(width: 8),
                    Text(
                      '请将左侧字段映射到文件中的对应列',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Divider(height: 0),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _fieldConfigs.length,
                itemBuilder: (context, index) {
                  final config = _fieldConfigs[index];
                  return _buildMappingItem(config, isDarkMode, index == _fieldConfigs.length - 1);
                },
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: '上一步',
                        onPressed: () => setState(() => _currentStep = 1),
                        isPrimary: false,
                        height: 44,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassButton(
                        label: '下一步',
                        onPressed: _allRequiredMapped ? () => _buildPreviewAndValidate() : null,
                        isPrimary: true,
                        height: 44,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMappingItem(FieldConfig config, bool isDarkMode, bool isLast) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Row(
                  children: [
                    if (config.required)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFD46B6B),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: config.required ? FontWeight.w600 : FontWeight.normal,
                              color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            config.hint,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDarkMode
                                  ? CupertinoColors.white.withOpacity(0.5)
                                  : CupertinoColors.systemGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showMappingPicker(config),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? CupertinoColors.systemGrey6.withOpacity(0.3)
                          : CupertinoColors.systemGrey6,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: config.mappedIndex != -1
                            ? const Color(0xFF8B9DC3).withOpacity(0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          config.mappedIndex != -1 ? _headers[config.mappedIndex] : '选择列',
                          style: TextStyle(
                            fontSize: 13,
                            color: config.mappedIndex != -1
                                ? const Color(0xFF8B9DC3)
                                : (isDarkMode
                                ? CupertinoColors.white.withOpacity(0.5)
                                : CupertinoColors.systemGrey),
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 14,
                          color: isDarkMode
                              ? CupertinoColors.white.withOpacity(0.4)
                              : CupertinoColors.systemGrey,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 0,
            indent: 16,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.08)
                : CupertinoColors.systemGrey4.withOpacity(0.5),
          ),
      ],
    );
  }

  void _showMappingPicker(FieldConfig config) {
    _tempMappedIndex = config.mappedIndex;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 350,
        color: CupertinoTheme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            Expanded(
              child: CupertinoPicker(
                itemExtent: 44,
                scrollController: FixedExtentScrollController(
                  initialItem: _tempMappedIndex != -1 ? _tempMappedIndex! + 1 : 0,
                ),
                onSelectedItemChanged: (index) {
                  if (index == 0) {
                    _tempMappedIndex = -1;
                  } else {
                    _tempMappedIndex = index - 1;
                  }
                },
                children: [
                  const Center(child: Text('不映射')),
                  ..._headers.map((h) => Center(child: Text(h))),
                ],
              ),
            ),
            Container(
              height: 0.5,
              color: CupertinoColors.separator,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: '取消',
                      onPressed: () => Navigator.pop(context),
                      isPrimary: false,
                      height: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: '确定',
                      onPressed: () {
                        setState(() {
                          config.mappedIndex = _tempMappedIndex ?? -1;
                        });
                        Navigator.pop(context);
                      },
                      isPrimary: true,
                      height: 44,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _autoSuggestMapping() {
    for (var config in _fieldConfigs) {
      config.mappedIndex = -1;
      for (int i = 0; i < _headers.length; i++) {
        final header = _headers[i].toLowerCase();

        if (config.id == 'clientName') {
          if (header.contains('客户姓名') || header.contains('客户名') || header == '姓名') {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'clientId') {
          if (header.contains('客户号') || header.contains('客户编号') || header.contains('核心客户号')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'fundCode') {
          if (header.contains('基金代码') || header.contains('产品代码')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'purchaseAmount') {
          if (header.contains('购买金额') ||
              header == '金额' ||
              header.contains('申购金额') ||
              header.contains('成交金额') ||
              header.contains('购买成本') ||
              header.contains('持仓成本') ||
              (header.contains('成本') && !header.contains('成本价'))) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'purchaseShares') {
          if (header.contains('份额') ||
              header.contains('当前份额') ||
              header.contains('持仓份额') ||
              header == '份数') {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'purchaseDate') {
          if (header.contains('购买日期') || header.contains('申购日期') || header.contains('成交日期')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionType') {
          if (header.contains('交易类型') || header.contains('加减仓')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionAmount') {
          if (header.contains('交易金额') || 
              (header.contains('加仓') && header.contains('金额')) ||
              (header.contains('减仓') && header.contains('金额'))) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionShares') {
          if (header.contains('交易份额') ||
              (header.contains('加仓') && header.contains('份额')) ||
              (header.contains('减仓') && header.contains('份额'))) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionDate') {
          if (header.contains('交易日期') ||
              (header.contains('加仓') && header.contains('日期')) ||
              (header.contains('减仓') && header.contains('日期'))) {
            config.mappedIndex = i;
            break;
          }
        }
      }
    }

    final clientNameConfig = _fieldConfigs.firstWhere((c) => c.id == 'clientName');
    final clientIdConfig = _fieldConfigs.firstWhere((c) => c.id == 'clientId');
    if (clientNameConfig.mappedIndex == -1 && clientIdConfig.mappedIndex != -1) {
      clientNameConfig.mappedIndex = clientIdConfig.mappedIndex;
    }
  }

  String _normalizeFundCode(String? code) {
    if (code == null) return '';
    String trimmed = code.trim();
    final numericOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.isEmpty) return trimmed;
    if (numericOnly.length < 6) {
      return numericOnly.padLeft(6, '0');
    }
    return numericOnly;
  }

  void _buildPreviewAndValidate() {
    _previewData = [];
    _validData = [];
    _invalidData = [];
    _invalidReasons = [];

    for (var row in _rawData) {
      final map = <String, dynamic>{};
      for (var config in _fieldConfigs) {
        if (config.mappedIndex != -1 && config.mappedIndex < row.length) {
          map[config.id] = row[config.mappedIndex];
        }
      }
      _previewData.add(map);
    }

    for (int i = 0; i < _previewData.length; i++) {
      final row = _previewData[i];
      final errors = <String>[];

      final clientName = row['clientName']?.toString().trim();
      if (clientName == null || clientName.isEmpty) {
        errors.add('客户姓名为空');
      }

      final clientId = row['clientId']?.toString().trim();
      if (clientId == null || clientId.isEmpty) {
        errors.add('客户号为空');
      }

      String? rawFundCode = row['fundCode']?.toString().trim();
      String? fundCode;
      if (rawFundCode == null || rawFundCode.isEmpty) {
        errors.add('基金代码为空');
      } else {
        fundCode = _normalizeFundCode(rawFundCode);
        if (!RegExp(r'^\d{6}$').hasMatch(fundCode)) {
          errors.add('基金代码格式错误(需6位数字)');
        }
      }

      String? amountStr = row['purchaseAmount']?.toString().trim();
      double? purchaseAmount;
      if (amountStr == null || amountStr.isEmpty) {
        errors.add('购买金额为空');
      } else {
        purchaseAmount = double.tryParse(amountStr);
        if (purchaseAmount == null || purchaseAmount <= 0) {
          errors.add('购买金额无效');
        }
      }

      String? sharesStr = row['purchaseShares']?.toString().trim();
      double? purchaseShares;
      if (sharesStr == null || sharesStr.isEmpty) {
        errors.add('购买份额为空');
      } else {
        purchaseShares = double.tryParse(sharesStr);
        if (purchaseShares == null || purchaseShares <= 0) {
          errors.add('购买份额无效');
        }
      }

      DateTime? purchaseDate;
      final dateStr = row['purchaseDate']?.toString().trim();
      if (dateStr == null || dateStr.isEmpty) {
        errors.add('购买日期为空');
      } else {
        purchaseDate = _parseDate(dateStr);
        if (purchaseDate == null) {
          errors.add('购买日期格式错误');
        }
      }

      if (errors.isEmpty) {
        _validData.add({
          ...row,
          'clientName': clientName,
          'clientId': clientId,
          'fundCode': fundCode?.toUpperCase(),
          'purchaseAmount': purchaseAmount,
          'purchaseShares': purchaseShares,
          'purchaseDate': purchaseDate,
        });
      } else {
        _invalidData.add(row);
        _invalidReasons.add('第${i+1}行: ${errors.join(', ')}');
      }
    }

    setState(() => _currentStep = 3);
  }

  Widget _buildConfirmStep(bool isDarkMode) {
    return Column(
      children: [
        Container(
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
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _importResult == null
                              ? CupertinoIcons.checkmark_alt_circle
                              : (_importResult!.successCount > 0
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.exclamationmark_triangle_fill),
                          size: 24,
                          color: _importResult == null
                              ? const Color(0xFF8B9DC3)
                              : (_importResult!.successCount > 0
                              ? const Color(0xFF9BABB8)
                              : const Color(0xFFD46B6B)),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _importResult == null ? '数据验证结果' : '数据导入结果',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B9DC3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: _importResult == null
                            ? [
                          Column(
                            children: [
                              Text(
                                '$_validRowsCount',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF8B9DC3),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '有效数据',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.7)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDarkMode
                                ? CupertinoColors.white.withOpacity(0.2)
                                : CupertinoColors.systemGrey4,
                          ),
                          Column(
                            children: [
                              Text(
                                '$_invalidRowsCount',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _invalidRowsCount > 0 ? const Color(0xFFD46B6B) : const Color(0xFF9BABB8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '异常数据',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.7)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ]
                            : [
                          Column(
                            children: [
                              Text(
                                '${_importResult!.successCount}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF8B9DC3),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '成功',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.7)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDarkMode
                                ? CupertinoColors.white.withOpacity(0.2)
                                : CupertinoColors.systemGrey4,
                          ),
                          Column(
                            children: [
                              Text(
                                '${_importResult!.skipCount}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9BABB8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '跳过',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.7)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDarkMode
                                ? CupertinoColors.white.withOpacity(0.2)
                                : CupertinoColors.systemGrey4,
                          ),
                          Column(
                            children: [
                              Text(
                                '${_importResult!.failCount}',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _importResult!.failCount > 0 ? const Color(0xFFD46B6B) : const Color(0xFF9BABB8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '失败',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.7)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_importResult == null && _invalidReasons.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD46B6B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.exclamationmark_triangle,
                                  size: 16,
                                  color: const Color(0xFFD46B6B),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '异常信息',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFD46B6B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._invalidReasons.take(3).map((reason) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFFD46B6B),
                                ),
                              ),
                            )),
                            if (_invalidReasons.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '等${_invalidReasons.length}条异常',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: const Color(0xFFD46B6B).withOpacity(0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (_importResult != null && _importResult!.skipReasons.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9BABB8).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.info_circle,
                                  size: 16,
                                  color: const Color(0xFF9BABB8),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '跳过信息',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF9BABB8),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._importResult!.skipReasons.take(3).map((reason) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFF9BABB8),
                                ),
                              ),
                            )),
                            if (_importResult!.skipReasons.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '等${_importResult!.skipReasons.length}条跳过',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: const Color(0xFF9BABB8).withOpacity(0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (_importResult != null && _importResult!.errors.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD46B6B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.exclamationmark_triangle,
                                  size: 16,
                                  color: const Color(0xFFD46B6B),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '失败信息',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFD46B6B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._importResult!.errors.take(3).map((error) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                error,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFFD46B6B),
                                ),
                              ),
                            )),
                            if (_importResult!.errors.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '等${_importResult!.errors.length}条失败',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: const Color(0xFFD46B6B).withOpacity(0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 0),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_isImporting) ...[
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? CupertinoColors.systemGrey5
                              : CupertinoColors.systemGrey4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: _importProgress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B9DC3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '导入中... ${(_importProgress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode
                              ? CupertinoColors.white.withOpacity(0.7)
                              : CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                    if (_importResult == null && !_isImporting)
                      Row(
                        children: [
                          Expanded(
                            child: GlassButton(
                              label: '上一步',
                              onPressed: () => setState(() => _currentStep = 2),
                              isPrimary: false,
                              height: 44,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GlassButton(
                              label: '开始导入',
                              onPressed: _validData.isEmpty ? null : _startImport,
                              isPrimary: true,
                              height: 44,
                            ),
                          ),
                        ],
                      ),
                    if (_importResult != null && !_isImporting)
                      Center(
                        child: GlassButton(
                          label: '完成',
                          onPressed: () => Navigator.of(context).pop(),
                          isPrimary: true,
                          width: 200,
                          height: 44,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _downloadTemplate() async {
    try {
      // 创建示例数据 - 包含基础持仓和加减仓流水
      final headers = [
        '客户姓名', '客户号', '基金代码', '购买金额', '购买份额', '购买日期',
        '交易类型(选填)', '交易金额(选填)', '交易份额(选填)', '交易日期(选填)'
      ];
      final sampleData = [
        // 基础持仓（无加减仓）
        ['张三', 'C001', '000001', '10000.00', '8000.00', '2024-01-15', '', '', '', ''],
        // 有加仓记录
        ['李四', 'C002', '110022', '20000.00', '15000.00', '2024-02-20', '加仓', '5000.00', '3500.00', '2024-03-15'],
        // 有减仓记录
        ['王五', 'C003', '519674', '5000.00', '4500.00', '2024-03-10', '减仓', '2000.00', '1800.00', '2024-04-10'],
      ];

      // 生成CSV内容
      final csvData = [headers, ...sampleData];
      final csvString = const ListToCsvConverter().convert(csvData);
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      // 保存文件
      if (kIsWeb) {
        // Web端直接下载
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", "FundLink-Template.csv")
          ..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) context.showToast('模板已下载');
      } else {
        // 移动端/桌面端使用file_saver
        final savedPath = await FileSaver.instance.saveAs(
          name: 'FundLink-Template',
          bytes: bytes,
          fileExtension: 'csv',
          mimeType: MimeType.other,
        );
        
        if (savedPath != null && savedPath.isNotEmpty) {
          if (mounted) context.showToast('模板已保存');
        } else {
          if (mounted) context.showToast('已取消保存');
        }
      }
    } catch (e) {
      if (mounted) context.showToast('生成模板失败: $e');
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result != null) {
      setState(() {
        _fileResult = result;
        _fileName = result.files.single.name;
      });
      _processFile();
    }
  }

  String _getCellValue(dynamic cell) {
    if (cell == null) return '';

    try {
      final val = cell.value;
      if (val == null) return '';

      if (val is excel.TextCellValue) {
        return val.value?.text ?? '';
      }
      if (val is excel.IntCellValue) {
        return val.value.toString();
      }
      if (val is excel.DoubleCellValue) {
        final doubleValue = val.value;
        if (doubleValue == doubleValue.toInt()) {
          return doubleValue.toInt().toString();
        }
        return doubleValue.toString();
      }
      if (val is excel.DateTimeCellValue) {
        return '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
      }
      if (val is excel.BoolCellValue) {
        return val.value ? '是' : '否';
      }
      if (cell is String) return cell.trim();
      if (val is String) return val.trim();
      return val.toString().trim();
    } catch (e) {
      return cell.toString().trim();
    }
  }

  String _decodeCsvBytes(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      throw Exception('文件编码不是 UTF-8，请将 CSV 另存为 UTF-8 编码');
    }
  }

  Future<void> _processFile() async {
    if (_fileResult == null) return;
    setState(() => _isProcessing = true);
    try {
      final file = _fileResult!.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('无法读取文件内容');
      }
      final extension = file.extension?.toLowerCase();
      debugPrint('开始处理导入文件: ${file.name}, 大小: ${bytes.length}字节, 扩展名: $extension');

      final isZipFile = bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
      final isExcelFile = extension == 'xlsx' || extension == 'xls' || isZipFile;
      final isCsvFile = extension == 'csv' && !isZipFile;

      if (isExcelFile) {
        try {
          final excelFile = excel.Excel.decodeBytes(bytes);
          if (excelFile.tables.isEmpty) {
            throw Exception('Excel 文件没有工作表');
          }
          final sheet = excelFile.tables[excelFile.tables.keys.first];
          if (sheet == null || sheet.rows.isEmpty) {
            throw Exception('Excel 工作表为空');
          }
          _headers = sheet.rows.first.map((cell) => _getCellValue(cell).trim()).toList();
          _rawData = sheet.rows.skip(1).map((row) => row.map((cell) => _getCellValue(cell)).toList()).toList();
        } catch (e) {
          debugPrint('Excel 解析失败，尝试 CSV: $e');
          try {
            final csvString = _decodeCsvBytes(bytes);
            final rows = const CsvToListConverter().convert(csvString);
            if (rows.isEmpty) throw Exception('CSV 文件为空');
            _headers = rows.first.map((e) => e?.toString().trim() ?? '').toList();
            _rawData = rows.skip(1).toList();
          } catch (csvError) {
            throw Exception('文件格式错误：既不是有效的 Excel 文件，也不是有效的 CSV 文件\n原始错误: $e');
          }
        }
      } else if (isCsvFile) {
        try {
          final csvString = _decodeCsvBytes(bytes);
          final rows = const CsvToListConverter().convert(csvString);
          if (rows.isEmpty) {
            throw Exception('CSV 文件为空');
          }
          _headers = rows.first.map((e) => e?.toString().trim() ?? '').toList();
          _rawData = rows.skip(1).toList();
        } catch (e) {
          throw Exception('CSV 文件解析失败: $e');
        }
      } else {
        throw Exception('不支持的文件格式: ${extension ?? "未知"}，请上传 CSV 或 Excel 文件');
      }

      if (_headers.isEmpty) {
        throw Exception('文件没有表头');
      }

      if (_rawData.isEmpty) {
        throw Exception('文件没有数据行');
      }

      debugPrint('文件解析成功 - 表头: ${_headers.length}列, 数据行数: ${_rawData.length}');

      _autoSuggestMapping();
      setState(() => _currentStep = 2);
    } catch (e, stack) {
      debugPrint('解析文件失败: $e\n$stack');
      final dataManager = DataManagerProvider.of(context);
      dataManager.addLog('导入文件解析失败: $_fileName - $e', type: LogType.error);
      if (context.mounted) {
        context.showToast('解析文件失败: $e');
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('导入失败'),
            content: Text('$e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  DateTime? _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      debugPrint('日期解析失败(ISO格式): $dateStr');
    }
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      try {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } catch (_) {
        debugPrint('日期解析失败(yyyy-MM-dd): $dateStr');
      }
    }
    final slashParts = dateStr.split('/');
    if (slashParts.length == 3) {
      try {
        return DateTime(int.parse(slashParts[0]), int.parse(slashParts[1]), int.parse(slashParts[2]));
      } catch (_) {
        debugPrint('日期解析失败(yyyy/MM/dd): $dateStr');
      }
    }
    return null;
  }

  Future<void> _startImport() async {
    setState(() {
      _isImporting = true;
      _importProgress = 0;
    });

    final dataManager = DataManagerProvider.of(context);
    final fundService = FundService(dataManager);

    int success = 0;
    int fail = 0;
    int skip = 0;
    List<String> errors = [];
    List<String> skipReasons = [];

    final existingHoldings = dataManager.holdings;

    for (int i = 0; i < _validData.length; i++) {
      final row = _validData[i];
      try {
        final clientName = row['clientName']?.toString() ?? '';
        if (clientName.isEmpty) throw Exception('客户姓名为空');

        final clientId = row['clientId']?.toString() ?? '';
        if (clientId.isEmpty) throw Exception('客户号为空');

        final rawFundCode = row['fundCode']?.toString() ?? '';
        if (rawFundCode.isEmpty) throw Exception('基金代码为空');
        final fundCode = _normalizeFundCode(rawFundCode).toUpperCase();

        final amountNum = row['purchaseAmount'];
        if (amountNum == null) throw Exception('购买金额为空');
        final purchaseAmount = amountNum is double ? amountNum : double.tryParse(amountNum.toString());
        if (purchaseAmount == null || purchaseAmount <= 0) throw Exception('购买金额无效');

        final sharesNum = row['purchaseShares'];
        if (sharesNum == null) throw Exception('购买份额为空');
        final purchaseShares = sharesNum is double ? sharesNum : double.tryParse(sharesNum.toString());
        if (purchaseShares == null || purchaseShares <= 0) throw Exception('购买份额无效');

        final purchaseDate = row['purchaseDate'];
        if (purchaseDate == null) throw Exception('购买日期为空');
        final date = purchaseDate is DateTime ? purchaseDate : _parseDate(purchaseDate.toString());
        if (date == null) throw Exception('购买日期格式错误');

        final isDuplicate = existingHoldings.any((h) =>
        h.clientId == clientId &&
            h.fundCode == fundCode);

        if (isDuplicate) {
          skip++;
          skipReasons.add('$clientName / $fundCode');
          continue;
        }

        Map<String, dynamic> fundInfo;
        try {
          fundInfo = await fundService.fetchFundInfo(fundCode);
        } catch (e) {
          debugPrint('导入时获取基金$fundCode信息失败: $e');
          dataManager.addLog('导入时获取基金$fundCode信息失败: $e', type: LogType.error);
          fundInfo = {
            'fundName': '',
            'currentNav': 0.0,
            'navDate': DateTime.now(),
            'isValid': false,
            'navReturn1m': null,
            'navReturn3m': null,
            'navReturn6m': null,
            'navReturn1y': null,
          };
        }

        final fundName = fundInfo['fundName'] as String? ?? '';
        final currentNav = fundInfo['currentNav'] as double? ?? 0.0;
        final navDate = fundInfo['navDate'] as DateTime? ?? DateTime.now();
        final isValid = fundInfo['isValid'] as bool? ?? (currentNav > 0);

        // 创建交易记录而不是直接创建持仓
        final transaction = TransactionRecord(
          clientId: clientId,
          clientName: clientName,
          fundCode: fundCode,
          fundName: fundName,
          type: TransactionType.buy,
          amount: purchaseAmount,
          shares: purchaseShares,
          tradeDate: date,
          nav: currentNav > 0 ? currentNav : null,
          remarks: '',
        );
        
        await dataManager.addTransaction(transaction);
        success++;
      } catch (e) {
        fail++;
        errors.add('第${i+1}行: $e');
        dataManager.addLog('导入第${i+1}行失败: $e', type: LogType.error);
      }
      setState(() => _importProgress = (i+1) / _validData.length);
    }

    setState(() {
      _isImporting = false;
      _importResult = ImportResult(
        successCount: success,
        failCount: fail,
        skipCount: skip,
        errors: errors,
        skipReasons: skipReasons,
      );
    });

    String message = '导入完成';
    if (success > 0) message += '，成功$success条';
    if (skip > 0) message += '，跳过$skip条';
    if (fail > 0) message += '，失败$fail条';
    context.showToast(message);
    
    if (fail > 0) {
      dataManager.addLog('批量导入完成: 成功$success, 跳过$skip, 失败$fail', type: LogType.warning);
    } else {
      dataManager.addLog('批量导入完成: 成功$success, 跳过$skip', type: LogType.success);
    }
  }
}

class FieldConfig {
  final String id;
  final String label;
  final bool required;
  final String hint;
  int mappedIndex;
  FieldConfig({
    required this.id,
    required this.label,
    required this.required,
    required this.mappedIndex,
    this.hint = '',
  });
}

class ImportResult {
  final int successCount;
  final int failCount;
  final int skipCount;
  final List<String> errors;
  final List<String> skipReasons;
  ImportResult({
    required this.successCount,
    required this.failCount,
    required this.skipCount,
    required this.errors,
    required this.skipReasons,
  });
}
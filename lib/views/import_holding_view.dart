import 'dart:convert';
import 'dart:typed_data';
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
import '../services/file_import_service.dart';
import '../services/client_mapping_service.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';
import '../utils/security_utils.dart';

class ImportHoldingView extends StatefulWidget {
  const ImportHoldingView({super.key});

  @override
  State<ImportHoldingView> createState() => _ImportHoldingViewState();
}

// ✅ 文件类型标识枚举（必须在类外部）
enum ImportFileType {
  unknown,
  holding,      // 持仓数据
  mapping,      // 映射索引
  fullBackup,   // 完整备份
}

class _ImportHoldingViewState extends State<ImportHoldingView> with TickerProviderStateMixin {
  int _currentStep = 1;
  FilePickerResult? _fileResult;
  String? _fileName;
  List<String> _headers = [];
  List<List<dynamic>> _rawData = [];
  bool _isProcessing = false;
  final ClientMappingService _mappingService = ClientMappingService();
  
  // ✅ 文件类型检测结果
  ImportFileType _detectedFileType = ImportFileType.unknown;

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
  late AnimationController _animationController;
  double _targetProgress = 0;
  ImportResult? _importResult;
  bool _importCompleted = false;
  
  // ✅ 导入中断控制
  bool _shouldAbortImport = false;  // 是否应该中止导入
  bool _isBackgroundImport = false;  // 是否正在后台导入
  bool _isPaused = false;  // 是否暂停导入

  bool get _allRequiredMapped => _fieldConfigs.where((f) => f.required).every((f) => f.mappedIndex != -1);
  int get _validRowsCount => _validData.length;
  int get _invalidRowsCount => _invalidData.length;

  int? _tempMappedIndex;

  @override
  void initState() {
    super.initState();
    // ✅ 初始化动画控制器，用于平滑进度条
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.addListener(() {
      if (mounted) {
        setState(() => _importProgress = _animationController.value);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ✅ 显示导入中止确认对话框
  Future<bool?> _showAbortImportDialog() async {
    return await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('导入进行中'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前正在导入数据，进度：${(_importProgress * 100).toInt()}%',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              '选择操作：',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '• 继续:继续进行导入操作并返回查看结果\n'
              '• 中止导入:停止导入(保留已导入数据)',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('中止导入'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, false),  // false = 中止
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('继续'),
            onPressed: () => Navigator.pop(context, true),  // true = 后台继续
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return PopScope(
      canPop: !_isImporting || _isPaused,  // ✅ 导入中且未暂停时不允许直接返回
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;  // 已经返回了
        
        if (_isImporting && !_isPaused) {
          // ✅ 先暂停导入
          setState(() {
            _isPaused = true;
          });
          
          // ✅ 显示确认对话框
          final shouldContinue = await _showAbortImportDialog();
          if (shouldContinue == true) {
            // 用户选择继续，恢复导入
            setState(() {
              _isPaused = false;
              _isBackgroundImport = true;
            });
          } else if (shouldContinue == false) {
            // 用户选择中止，设置中止标志
            setState(() {
              _shouldAbortImport = true;
              _isPaused = false;
            });
          }
        } else if (_isImporting && _isPaused) {
          // 已暂停状态，不应该到达这里，但为了安全
          setState(() {
            _isPaused = false;
          });
        } else {
          // 没有导入，直接返回
          Navigator.pop(context);
        }
      },
      child: CupertinoPageScaffold(
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
    ),  // CupertinoPageScaffold
    );  // PopScope
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
                      style: TextStyle(fontSize: 13, color: CupertinoColors.label),
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
                                ? (isDarkMode
                                    ? CupertinoColors.white
                                    : const Color(0xFF8B9DC3))
                                : (isDarkMode
                                ? CupertinoColors.white.withOpacity(0.8)
                                : CupertinoColors.systemGrey),
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 14,
                          color: isDarkMode
                              ? CupertinoColors.white.withOpacity(0.7)
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
      builder: (context) {
        final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
        final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.black;
        
        return Container(
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
                    Center(child: Text('不映射', style: TextStyle(color: textColor))),
                    ..._headers.map((h) => Center(child: Text(h, style: TextStyle(color: textColor)))),
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
        );
      },
    );
  }

  void _autoSuggestMapping() {
    for (var config in _fieldConfigs) {
      config.mappedIndex = -1;
      for (int i = 0; i < _headers.length; i++) {
        final header = _headers[i].toLowerCase();

        if (config.id == 'clientName') {
          if (header.contains('客户姓名') || header.contains('客户名') || header == '姓名' ||
              header == 'clientname' || header == 'client_name' ||
              header.contains('clientname')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'clientId') {
          if (header.contains('客户号') || header.contains('客户编号') || header.contains('核心客户号') ||
              header == 'clientid' || header == 'client_id' ||
              header.contains('clientid')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'fundCode') {
          if (header.contains('基金代码') || header.contains('产品代码') ||
              header == 'fundcode' || header == 'fund_code' ||
              header.contains('fundcode')) {
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
              (header.contains('成本') && !header.contains('成本价')) ||
              header == 'purchaseamount' || header == 'purchase_amount' ||
              header.contains('purchaseamount')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'purchaseShares') {
          if (header.contains('份额') ||
              header.contains('当前份额') ||
              header.contains('持仓份额') ||
              header == '份数' ||
              header == 'purchaseshares' || header == 'purchase_shares' ||
              header.contains('purchaseshares')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'purchaseDate') {
          if (header.contains('购买日期') || header.contains('申购日期') || header.contains('成交日期') ||
              header == 'purchasedate' || header == 'purchase_date' ||
              header.contains('purchasedate')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionType') {
          if (header.contains('交易类型') || header.contains('加减仓') ||
              header == 'transactiontype' || header == 'transaction_type' ||
              header.contains('transactiontype')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionAmount') {
          if (header.contains('交易金额') || 
              (header.contains('加仓') && header.contains('金额')) ||
              (header.contains('减仓') && header.contains('金额')) ||
              header == 'transactionamount' || header == 'transaction_amount' ||
              header.contains('transactionamount')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionShares') {
          if (header.contains('交易份额') ||
              (header.contains('加仓') && header.contains('份额')) ||
              (header.contains('减仓') && header.contains('份额')) ||
              header == 'transactionshares' || header == 'transaction_shares' ||
              header.contains('transactionshares')) {
            config.mappedIndex = i;
            break;
          }
        }
        else if (config.id == 'transactionDate') {
          if (header.contains('交易日期') ||
              (header.contains('加仓') && header.contains('日期')) ||
              (header.contains('减仓') && header.contains('日期')) ||
              header == 'transactiondate' || header == 'transaction_date' ||
              header.contains('transactiondate')) {
            config.mappedIndex = i;
            break;
          }
        }
      }
    }

    final clientNameConfig = _fieldConfigs.firstWhere(
      (c) => c.id == 'clientName',
      orElse: () => throw Exception('未找到客户姓名字段配置'),
    );
    final clientIdConfig = _fieldConfigs.firstWhere(
      (c) => c.id == 'clientId',
      orElse: () => throw Exception('未找到客户号字段配置'),
    );
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
                      Stack(
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? CupertinoColors.systemGrey5
                                  : CupertinoColors.systemGrey4,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _importProgress,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B9DC3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '导入中... ${(_importProgress * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? CupertinoColors.white.withOpacity(0.7)
                                  : CupertinoColors.systemGrey,
                            ),
                          ),
                          // ✅ 导入过程中显示返回按钮
                          if (_importProgress < 1.0)
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minSize: 0,
                              onPressed: () async {
                                final shouldContinue = await _showAbortImportDialog();
                                if (shouldContinue == true) {
                                  _isBackgroundImport = true;
                                } else if (shouldContinue == false) {
                                  _shouldAbortImport = true;
                                }
                              },
                              child: Text(
                                '返回',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.activeBlue,
                                ),
                              ),
                            ),
                        ],
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
    // ✅ 显示选择对话框，让用户选择下载哪种模板
    await showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
        
        return CupertinoActionSheet(
          title: const Text('选择模板类型'),
          message: const Text('请选择要下载的模板类型'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _downloadHoldingTemplate();
              },
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.chart_bar_fill,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '持仓数据模板',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '包含基金代码、金额、份额等字段',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode
                              ? CupertinoColors.white.withOpacity(0.6)
                              : CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _downloadMappingTemplate();
              },
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.person_2_fill,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '映射索引模板',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '仅包含客户号和客户名',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode
                              ? CupertinoColors.white.withOpacity(0.6)
                              : CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            isDefaultAction: true,
            child: const Text('取消'),
          ),
        );
      },
    );
  }
  
  /// ✅ 新增：下载持仓数据模板
  Future<void> _downloadHoldingTemplate() async {
    try {
      final headers = [
        '客户姓名', '客户号', '基金代码', '购买金额', '购买份额', '购买日期',
        '交易类型(选填)', '交易金额(选填)', '交易份额(选填)', '交易日期(选填)'
      ];
      final sampleData = [
        ['张三', 'C001', '000001', '10000.00', '8000.00', '2024-01-15', '', '', '', ''],
        ['李四', 'C002', '110022', '20000.00', '15000.00', '2024-02-20', '加仓', '5000.00', '3500.00', '2024-03-15'],
        ['王五', 'C003', '519674', '5000.00', '4500.00', '2024-03-10', '减仓', '2000.00', '1800.00', '2024-04-10'],
      ];

      final csvData = [headers, ...sampleData];
      final csvString = const ListToCsvConverter().convert(csvData);
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", "FundLink-持仓模板.csv")
          ..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) context.showToast('持仓模板已下载');
      } else {
        final savedPath = await FileSaver.instance.saveAs(
          name: 'FundLink-持仓模板',
          bytes: bytes,
          fileExtension: 'csv',
          mimeType: MimeType.other,
        );
        
        if (savedPath != null && savedPath.isNotEmpty) {
          if (mounted) context.showToast('持仓模板已保存');
        } else {
          if (mounted) context.showToast('已取消保存');
        }
      }
    } catch (e) {
      if (mounted) context.showToast('生成模板失败: $e');
    }
  }
  
  /// ✅ 新增：下载映射索引模板
  Future<void> _downloadMappingTemplate() async {
    try {
      final headers = ['客户号', '客户姓名'];
      final sampleData = [
        ['C001', '张三'],
        ['C002', '李四'],
        ['C003', '王五'],
        ['10001', '赵六'],
        ['10002', '孙七'],
      ];

      final csvData = [headers, ...sampleData];
      final csvString = const ListToCsvConverter().convert(csvData);
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", "FundLink-映射索引模板.csv")
          ..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) context.showToast('映射模板已下载');
      } else {
        final savedPath = await FileSaver.instance.saveAs(
          name: 'FundLink-映射索引模板',
          bytes: bytes,
          fileExtension: 'csv',
          mimeType: MimeType.other,
        );
        
        if (savedPath != null && savedPath.isNotEmpty) {
          if (mounted) context.showToast('映射模板已保存');
        } else {
          if (mounted) context.showToast('已取消保存');
        }
      }
    } catch (e) {
      if (mounted) context.showToast('生成模板失败: $e');
    }
  }

  Future<void> _pickFile() async {
    // ✅ 修复：file_picker 11.x API变更，直接使用 FilePicker.pickFiles
    final result = await FilePicker.pickFiles(  // 移除 .platform
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result != null) {
      // 检查文件大小(限制5MB)
      final fileSize = result.files.single.size;
      const int maxFileSize = 5 * 1024 * 1024; // 5MB
      
      if (fileSize > maxFileSize) {
        if (mounted) {
          context.showToast('文件大小超过限制(最大5MB)');
        }
        return;
      }
      
      if (mounted) {  // ✅ 添加 mounted 检查
        setState(() {
          _fileResult = result;
          _fileName = result.files.single.name;
        });
      }
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
    if (mounted) setState(() => _isProcessing = true);  // ✅ 添加 mounted 检查
    try {
      final file = _fileResult!.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('无法读取文件内容');
      }
      final extension = file.extension?.toLowerCase();

      // ✅ 新增：检测是否为完整备份文件
      final isFullBackup = await _detectFullBackup(bytes, extension);
      
      if (isFullBackup) {
        // 处理完整备份文件
        await _processFullBackup(bytes, extension);
        return;
      }

      // 处理普通CSV/Excel文件
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

      // ✅ 新增：智能检测文件类型
      _detectedFileType = _detectFileType(_headers);
      debugPrint('[Import] 检测到文件类型: $_detectedFileType');
      
      // 如果是映射索引文件，直接导入
      if (_detectedFileType == ImportFileType.mapping) {
        await _processMappingFile();
        return;
      }

      _autoSuggestMapping();
      setState(() => _currentStep = 2);
    } catch (e, stack) {
      final dataManager = DataManagerProvider.of(context);
      // 详细错误记录到日志(不显示给用户)
      dataManager.addLog('导入文件解析失败: $_fileName - $e', type: LogType.error);
      if (context.mounted) {
        // 显示友好的错误消息(不泄露技术细节)
        final friendlyMessage = SecurityUtils.getFriendlyErrorMessage(e);
        context.showToast(friendlyMessage);
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('导入失败'),
            content: Text(friendlyMessage),
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
  
  /// 检测是否为完整备份文件
  Future<bool> _detectFullBackup(Uint8List bytes, String? extension) async {
    try {
      extension = extension?.toLowerCase();
      
      // 如果是 xlsx 或 xls，尝试作为 Excel 解析
      if (extension == 'xlsx' || extension == 'xls') {
        final excelFile = excel.Excel.decodeBytes(bytes);
        // 检查是否有 Holdings 和 Transactions 工作表
        return excelFile.tables.containsKey('Holdings') && 
               excelFile.tables.containsKey('Transactions');
      }
      
      // 如果是 csv，检查是否包含备份标记
      if (extension == 'csv') {
        final csvString = utf8.decode(bytes, allowMalformed: true);
        return csvString.contains('# FundLink Full Backup') ||
               csvString.contains('=== HOLDINGS DATA ===');
      }
      
      // 其他情况，尝试两种方式
      try {
        final csvString = utf8.decode(bytes, allowMalformed: true);
        if (csvString.contains('# FundLink Full Backup') ||
            csvString.contains('=== HOLDINGS DATA ===')) {
          return true;
        }
      } catch (_) {}
      
      try {
        final excelFile = excel.Excel.decodeBytes(bytes);
        return excelFile.tables.containsKey('Holdings') && 
               excelFile.tables.containsKey('Transactions');
      } catch (_) {}
      
      return false;
    } catch (e) {
      debugPrint('检测备份文件失败: $e');
      return false;
    }
  }
  
  /// ✅ 新增：智能检测文件类型（持仓 or 映射索引）
  ImportFileType _detectFileType(List<String> headers) {
    final lowerHeaders = headers.map((h) => h.toLowerCase()).toList();
    
    // 1. 先检测是否为持仓数据文件（优先级更高）
    // 特征：包含基金代码、购买金额等字段
    bool hasFundCode = false;
    bool hasAmountOrShares = false;
    
    for (final header in lowerHeaders) {
      if (header.contains('基金代码') || 
          header.contains('产品代码') ||
          header.contains('fundcode') ||
          header.contains('fund_code') ||
          header.contains('fund code')) {
        hasFundCode = true;
      }
      
      if (header.contains('购买金额') || 
          header.contains('申购金额') ||
          header.contains('成本') ||
          header.contains('份额') ||
          header.contains('amount') ||
          header.contains('shares') ||
          header.contains('purchase')) {
        hasAmountOrShares = true;
      }
    }
    
    // 如果有基金代码和金额/份额，一定是持仓数据
    if (hasFundCode && hasAmountOrShares) {
      return ImportFileType.holding;
    }
    
    // 2. 再检测是否为映射索引文件
    // 特征：只有客户号和客户名相关的列，且没有持仓相关字段
    bool hasClientIdColumn = false;
    bool hasClientNameColumn = false;
    int totalColumns = headers.length;
    
    for (final header in lowerHeaders) {
      // 检测客户号相关列
      if (header.contains('客户号') || 
          header.contains('核心客户号') || 
          header.contains('用户号') || 
          header.contains('核心用户号') || 
          header.contains('客户代码') ||
          header.contains('clientid') ||
          header.contains('client_id') ||
          header.contains('user_id') ||
          header.contains('userid')) {
        hasClientIdColumn = true;
      }
      
      // 检测客户名相关列
      if (header.contains('客户姓名') || 
          header.contains('客户名') || 
          header.contains('姓名') || 
          header.contains('名字') || 
          header.contains('核心用户名') ||
          header.contains('clientname') ||
          header.contains('client_name') ||
          header.contains('username') ||
          header.contains('user_name') ||
          header == '姓名' ||
          header == '名字') {
        hasClientNameColumn = true;
      }
    }
    
    // 如果同时有客户号和客户名，且总列数较少（<= 5），很可能是映射索引
    if (hasClientIdColumn && hasClientNameColumn && totalColumns <= 5) {
      return ImportFileType.mapping;
    }
    
    // 3. 默认认为是持仓数据（保持原有行为）
    return ImportFileType.holding;
  }
  
  /// ✅ 新增：处理映射索引文件
  Future<void> _processMappingFile() async {
    final dataManager = DataManagerProvider.of(context);
    
    try {
      debugPrint('[Import] 开始处理映射索引文件，共${_rawData.length}条记录');
      
      int success = 0;
      int fail = 0;
      int skip = 0;
      
      // 自动识别客户号和客户名列
      int clientIdIndex = -1;
      int clientNameIndex = -1;
      
      for (int i = 0; i < _headers.length; i++) {
        final header = _headers[i].toLowerCase();
        
        // 识别客户号
        if (clientIdIndex == -1 && 
            (header.contains('客户号') || 
             header.contains('核心客户号') || 
             header.contains('用户号') || 
             header.contains('核心用户号') || 
             header.contains('客户代码') ||
             header.contains('clientid') ||
             header.contains('client_id') ||
             header.contains('user_id') ||
             header.contains('userid'))) {
          clientIdIndex = i;
        }
        
        // 识别客户名
        if (clientNameIndex == -1 && 
            (header.contains('客户姓名') || 
             header.contains('客户名') || 
             header.contains('姓名') || 
             header.contains('名字') || 
             header.contains('核心用户名') ||
             header.contains('clientname') ||
             header.contains('client_name') ||
             header.contains('username') ||
             header.contains('user_name') ||
             header == '姓名' ||
             header == '名字')) {
          clientNameIndex = i;
        }
      }
      
      if (clientIdIndex == -1 || clientNameIndex == -1) {
        throw Exception('无法识别客户号或客户名列');
      }
      
      debugPrint('[Import] 客户号列: $_headers[$clientIdIndex], 客户名列: $_headers[$clientNameIndex]');
      
      // 逐行导入
      for (final row in _rawData) {
        try {
          if (row.length <= clientIdIndex || row.length <= clientNameIndex) {
            fail++;
            continue;
          }
          
          final clientId = row[clientIdIndex]?.toString().trim();
          final clientName = row[clientNameIndex]?.toString().trim();
          
          if (clientId == null || clientId.isEmpty || clientName == null || clientName.isEmpty) {
            skip++;
            continue;
          }
          
          // 检查是否已存在
          final existing = await _mappingService.getAllMappings();
          final existingMapping = existing.where((m) => m.clientId == clientId).firstOrNull;
          
          if (existingMapping != null) {
            // 如果已存在，更新客户名
            await _mappingService.updateMapping(
              existingMapping.id,
              clientId,
              clientName,
            );
            success++;
            debugPrint('[Import] 更新映射: $clientId -> $clientName');
          } else {
            // 新增映射
            await _mappingService.addMapping(clientId, clientName);
            success++;
            debugPrint('[Import] 新增映射: $clientId -> $clientName');
          }
        } catch (e) {
          fail++;
          debugPrint('[Import] 导入映射失败: $e');
        }
      }
      
      debugPrint('[Import] 映射导入结果: 成功$success, 跳过$skip, 失败$fail');
      
      if (mounted) {
        context.showToast('映射索引导入完成\n成功: $success, 跳过: $skip, 失败: $fail');
        Navigator.pop(context); // 返回上一页
      }
    } catch (e) {
      debugPrint('[Import] 处理映射文件失败: $e');
      if (mounted) {
        context.showToast('映射导入失败: $e');
      }
    }
  }
  
  /// 处理完整备份文件
  Future<void> _processFullBackup(Uint8List bytes, String? extension) async {
    final dataManager = DataManagerProvider.of(context);
    
    try {
      debugPrint('[Import] 检测到完整备份文件，开始解析...');
      
      final result = await FileImportService.parseFullBackup(
        bytes: bytes,
        extension: extension ?? 'csv',
      );
      
      debugPrint('[Import] 解析完成: 持仓${result.holdings.length}条, 交易${result.transactions.length}条');
      
      if (result.holdings.isEmpty && result.transactions.isEmpty) {
        throw Exception('备份文件中没有数据');
      }
      
      // 直接导入所有交易记录（会自动重建持仓）
      int success = 0;
      int fail = 0;
      int skip = 0;
      
      for (final transaction in result.transactions) {
        try {
          // 检查是否已存在
          final exists = dataManager.transactions.any(
            (tx) => tx.id == transaction.id || 
                    (tx.clientId == transaction.clientId && 
                     tx.fundCode == transaction.fundCode &&
                     tx.tradeDate == transaction.tradeDate &&
                     tx.amount == transaction.amount)
          );
          
          if (exists) {
            skip++;
            continue;
          }
          
          await dataManager.addTransaction(transaction);
          success++;
        } catch (e) {
          fail++;
          debugPrint('[Import] 导入交易失败: $e');
        }
      }
      
      debugPrint('[Import] 导入结果: 成功$success, 跳过$skip, 失败$fail');
      
      // 强制保存数据
      if (!kIsWeb && success > 0) {
        await dataManager.saveData();
        debugPrint('[Import] 数据已保存到数据库');
      }
      
      // 显示结果
      if (mounted) {
        String message = '备份恢复完成';
        if (success > 0) message += '\n成功恢复 $success 条交易';
        if (skip > 0) message += '\n跳过 $skip 条重复记录';
        if (fail > 0) message += '\n失败 $fail 条';
        
        context.showToast(message);
        
        // 返回上一页
        Navigator.pop(context);
      }
      
    } catch (e) {
      debugPrint('[Import] 完整备份导入失败: $e');
      if (mounted) {
        context.showToast('备份恢复失败: $e');
      }
      rethrow;
    }
  }

  DateTime? _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      // 尝试其他格式
    }
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      try {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } catch (_) {
        // 继续尝试其他格式
      }
    }
    final slashParts = dateStr.split('/');
    if (slashParts.length == 3) {
      try {
        return DateTime(int.parse(slashParts[0]), int.parse(slashParts[1]), int.parse(slashParts[2]));
      } catch (_) {
        // 所有格式都失败，返回 null
      }
    }
    return null;
  }

  Future<void> _startImport() async {
    if (mounted) {  // ✅ 添加 mounted 检查
      setState(() {
        _isImporting = true;
        _importProgress = 0;
        _shouldAbortImport = false;  // ✅ 重置中止标志
        _isBackgroundImport = false;  // ✅ 重置后台导入标志
        _isPaused = false;  // ✅ 重置暂停标志
      });
    }

    final dataManager = DataManagerProvider.of(context);
    final fundService = FundService(dataManager);

    int success = 0;
    int fail = 0;
    int skip = 0;
    List<String> errors = [];
    List<String> skipReasons = [];

    // ✅ 添加统一的暂停检查函数
    Future<bool> _checkPauseOrAbort() async {
      if (_shouldAbortImport) return true; // 需要中止
      if (_isPaused) {
        debugPrint('[Import] 导入已暂停，等待用户选择...');
        while (_isPaused && mounted) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        // 用户恢复后，检查是否要中止
        if (_shouldAbortImport) return true;
      }
      return false; // 继续执行
    }

    final existingHoldings = dataManager.holdings;

    for (int i = 0; i < _validData.length; i++) {
      // ✅ 每次循环开始检查
      if (await _checkPauseOrAbort()) break;
      
      final row = _validData[i];
      try {
        String clientName = row['clientName']?.toString() ?? '';
        if (clientName.isEmpty) throw Exception('客户姓名为空');

        final clientId = row['clientId']?.toString() ?? '';
        if (clientId.isEmpty) throw Exception('客户号为空');
        
        // ✅ 新增：查询映射词典，如果客户号存在且客户名是客户号本身，则替换为映射的客户名
        if (clientName == clientId) {
          try {
            final mappedName = await _mappingService.getClientNameByClientId(clientId);
            if (mappedName != null && mappedName.isNotEmpty) {
              clientName = mappedName;
              debugPrint('[Import] ✅ 第${i+1}行: 客户号 $clientId 映射为客户名 $mappedName');
            }
          } catch (e) {
            // 未找到映射，使用原客户名（即客户号）
            debugPrint('[Import] ⚠️ 第${i+1}行: 客户号 $clientId 未在映射词典中找到');
          }
        }

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

        // ✅ 修复：允许离线导入，网络失败时使用默认值
        Map<String, dynamic> fundInfo = {  
          'fundName': '',
          'currentNav': 0.0,
          'navDate': DateTime.now(),
          'isValid': false,
          'navReturn1m': null,
          'navReturn3m': null,
          'navReturn6m': null,
          'navReturn1y': null,
        };
        var retryCount = 0;
        const maxRetries = 2;
        Exception? lastError;
        bool networkFailed = false;
        
        while (retryCount <= maxRetries) {
          // ✅ 重试前检查
          if (await _checkPauseOrAbort()) break;
          
          try {
            fundInfo = await fundService.fetchFundInfo(fundCode);
            break;
          } catch (e) {
            lastError = e is Exception ? e : Exception(e.toString());
            retryCount++;
            if (retryCount <= maxRetries) {
              await Future.delayed(Duration(milliseconds: 500 * retryCount));
            }
          }
          
          // ✅ 重试后检查
          if (await _checkPauseOrAbort()) break;
        }
        
        // ✅ 如果被中止，退出循环
        if (_shouldAbortImport) break;
        
        if (retryCount > maxRetries) {
          networkFailed = true;
          dataManager.addLog('导入时获取基金$fundCode信息失败（重试$maxRetries次后）: $lastError', type: LogType.warning);
          // ✅ 关键修复：网络失败时不抛出异常，继续使用默认值
        }

        final fundName = fundInfo['fundName'] as String? ?? '';
        final currentNav = fundInfo['currentNav'] as double? ?? 0.0;
        final navDate = fundInfo['navDate'] as DateTime? ?? DateTime.now();
        final isValid = fundInfo['isValid'] as bool? ?? (currentNav > 0);
        
        // ✅ 新增：提取收益率数据
        final navReturn1m = fundInfo['navReturn1m'] as double?;
        final navReturn3m = fundInfo['navReturn3m'] as double?;
        final navReturn6m = fundInfo['navReturn6m'] as double?;
        final navReturn1y = fundInfo['navReturn1y'] as double?;

        // ✅ 保存前检查
        if (await _checkPauseOrAbort()) break;
        
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
        
        // ✅ 新增：立即更新持仓的净值和收益率数据到UI
        if (currentNav > 0 || navReturn1m != null || navReturn3m != null || navReturn6m != null || navReturn1y != null) {
          try {
            final holdingIndex = dataManager.holdings.indexWhere(
              (h) => h.clientId == clientId && h.fundCode == fundCode,
            );
            if (holdingIndex != -1) {
              final existingHolding = dataManager.holdings[holdingIndex];
              final updatedHolding = existingHolding.copyWith(
                currentNav: currentNav > 0 ? currentNav : existingHolding.currentNav,
                navDate: navDate,
                isValid: isValid || existingHolding.isValid,
                navReturn1m: navReturn1m ?? existingHolding.navReturn1m,
                navReturn3m: navReturn3m ?? existingHolding.navReturn3m,
                navReturn6m: navReturn6m ?? existingHolding.navReturn6m,
                navReturn1y: navReturn1y ?? existingHolding.navReturn1y,
              );
              await dataManager.updateHolding(updatedHolding);
              debugPrint('[Import] ✅ 已更新持仓 $fundCode 的净值和收益率数据');
            }
          } catch (e) {
            debugPrint('[Import] ⚠️ 更新持仓数据失败: $e');
          }
        }
        
        success++;
      } catch (e) {
        fail++;
        errors.add('第${i+1}行: $e');
        dataManager.addLog('导入第${i+1}行失败: $e', type: LogType.error);
      }
      // ✅ 优化：每条数据都更新进度，实现平滑的0-100%动画
      final progress = (i+1) / _validData.length;
      _targetProgress = progress;
      _animationController.animateTo(
        progress,
        duration: const Duration(milliseconds: 200),  // 更短的动画时长，响应更快
        curve: Curves.easeOut,  // 先快后慢，让用户感觉响应迅速
      );
      
      // ✅ 检查是否应该暂停导入（等待用户选择）
      if (_isPaused) {
        debugPrint('[Import] 导入已暂停，等待用户选择...');
        // 等待直到不再暂停
        while (_isPaused && mounted) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        // 如果用户选择了中止，退出循环
        if (_shouldAbortImport) {
          debugPrint('[Import] 用户选择中止导入，当前进度: ${progress * 100}%');
          break;
        }
      }
      
      // ✅ 检查是否应该中止导入
      if (_shouldAbortImport) {
        debugPrint('[Import] 用户选择中止导入，当前进度: ${progress * 100}%');
        break;  // 退出循环
      }
    }

    setState(() {
      _isImporting = false;
      _isBackgroundImport = false;  // ✅ 重置后台导入标志
      _shouldAbortImport = false;  // ✅ 重置中止标志
      _isPaused = false;  // ✅ 重置暂停标志
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
    
    // ✅ 关键修复：导入完成后强制刷新数据库，确保所有数据立即写入磁盘
    // 即使立即退出程序，数据也不会丢失
    if (!kIsWeb && success > 0) {
      debugPrint('[Import] 导入完成，开始强制保存数据...');
      await dataManager.saveData();
      debugPrint('[Import] 数据保存完成，当前持仓数: ${dataManager.holdings.length}, 交易数: ${dataManager.transactions.length}');
    }
    
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
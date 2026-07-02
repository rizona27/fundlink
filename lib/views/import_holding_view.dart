import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:excel/excel.dart' as excel;
import 'package:fast_gbk/fast_gbk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/cupertino.dart' hide Permission;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../models/client_mapping.dart';
import '../models/log_entry.dart';
import '../models/transaction_record.dart';
import '../services/client_mapping_service.dart';
import '../services/data_manager.dart';
import '../services/file_import_service.dart';
import '../services/fund_service.dart';
import '../utils/error_handler.dart';
import '../utils/input_formatters.dart';
import '../utils/permission_gate.dart';
import '../widgets/glass_button.dart';
import '../widgets/toast.dart';

class ImportHoldingView extends StatefulWidget {
  final ({Uint8List bytes, String fileName})? initialFile;

  const ImportHoldingView({super.key, this.initialFile});

  @override
  State<ImportHoldingView> createState() => _ImportHoldingViewState();
}

enum ImportFileType {
  unknown,
  holding,
  mapping,
  fullBackup,
}

class _ImportHoldingViewState extends State<ImportHoldingView> with TickerProviderStateMixin {
  int _currentStep = 1;
  String? _fileName;
  List<String> _headers = [];
  List<List<dynamic>> _rawData = [];
  bool _isProcessing = false;
  final ClientMappingService _mappingService = ClientMappingService();
  
  ImportFileType _detectedFileType = ImportFileType.unknown;

  // Mapping file state
  int _mappingClientIdIndex = -1;
  int _mappingClientNameIndex = -1;
  int _mappingNewCount = 0;
  int _mappingSkipCount = 0;

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
  
  bool _shouldAbortImport = false;
  bool _isBackgroundImport = false;
  bool _isPaused = false;
  bool _isDragging = false;

  bool get _allRequiredMapped => _fieldConfigs.where((f) => f.required).every((f) => f.mappedIndex != -1);
  int get _validRowsCount => _validData.length;
  int get _invalidRowsCount => _invalidData.length;

  int? _tempMappedIndex;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.addListener(() {
      if (mounted) {
        setState(() => _importProgress = _animationController.value);
      }
    });

    // Process initial file if provided (from share intent or drag-drop)
    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final file = widget.initialFile!;
          _fileName = file.fileName;
          _processBytes(file.bytes, file.fileName);
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

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
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('继续'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = AppConstants.isDark(context);
    final backgroundColor = isDarkMode ? AppConstants.darkBackground : AppConstants.lightBackground;

    return PopScope(
      canPop: !_isImporting || _isPaused,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        if (_isImporting && !_isPaused) {
          setState(() {
            _isPaused = true;
          });
          
          final shouldContinue = await _showAbortImportDialog();
          if (shouldContinue == true) {
            setState(() {
              _isPaused = false;
              _isBackgroundImport = true;
            });
          } else if (shouldContinue == false) {
            setState(() {
              _shouldAbortImport = true;
              _isPaused = false;
            });
          }
        } else if (_isImporting && _isPaused) {
          setState(() {
            _isPaused = false;
          });
        } else {
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
    ),
    );
  }

  Widget _buildStepIndicator(bool isDarkMode) {
    final isMapping = _detectedFileType == ImportFileType.mapping;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepCircle(1, '选择文件', isDarkMode),
          _stepLine(1, isDarkMode),
          _stepCircle(2, isMapping ? '映射预览' : '字段映射', isDarkMode),
          _stepLine(2, isDarkMode),
          _stepCircle(3, isMapping ? '开始导入' : '导入确认', isDarkMode),
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
                ? AppConstants.secondaryText
                : (isDone
                ? AppConstants.tertiaryText
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
                ? AppConstants.secondaryText
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
          ? AppConstants.tertiaryText
          : (isDarkMode ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey4),
    );
  }

  Widget _buildStepContent(bool isDarkMode) {
    if (_detectedFileType == ImportFileType.mapping) {
      switch (_currentStep) {
        case 1:
          return _buildUploadStep(isDarkMode);
        case 2:
          return _buildMappingPreviewStep(isDarkMode);
        case 3:
          return _buildMappingConfirmStep(isDarkMode);
        default:
          return const SizedBox();
      }
    }
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
    final isDesktop = kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    Widget uploadContent = GestureDetector(
      onTap: _isProcessing ? null : _pickFile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 60),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: _isDragging
              ? Border.all(color: AppConstants.secondaryText, width: 2.5)
              : null,
          color: _isDragging
              ? AppConstants.secondaryText.withOpacity(0.05)
              : null,
        ),
        child: Column(
          children: [
            Icon(
              _isDragging
                  ? CupertinoIcons.doc_plaintext
                  : CupertinoIcons.cloud_upload,
              size: 48,
              color: AppConstants.secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              _fileName ??
                  (isDesktop
                      ? '点击选择CSV或Excel文件，或将文件拖拽到此处'
                      : '点击选择CSV或Excel文件'),
              style: TextStyle(
                fontSize: 15,
                color: _fileName != null
                    ? AppConstants.secondaryText
                    : (isDarkMode
                        ? CupertinoColors.white.withOpacity(0.7)
                        : CupertinoColors.systemGrey),
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
            if (_isDragging) ...[
              const SizedBox(height: 8),
              const Text(
                '松开以导入文件',
                style: TextStyle(
                  fontSize: 12,
                  color: AppConstants.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (isDesktop) {
      uploadContent = DropTarget(
        onDragDone: (details) async {
          setState(() => _isDragging = false);
          if (details.files.isEmpty) return;
          final dropFile = details.files.first;
          try {
            final bytes = await dropFile.readAsBytes();
            final name = dropFile.name;
            if (mounted) {
              setState(() {
                _fileName = name;
              });
            }
            await _processBytes(bytes, name);
          } catch (e) {
            if (mounted) {
              context.showToast('读取文件失败: $e');
            }
          }
        },
        onDragEntered: (_) {
          if (mounted) setState(() => _isDragging = true);
        },
        onDragExited: (_) {
          if (mounted) setState(() => _isDragging = false);
        },
        child: uploadContent,
      );
    }

    return Column(
      children: [
        uploadContent,
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
                    Icon(CupertinoIcons.arrow_2_squarepath, size: 16, color: AppConstants.secondaryText),
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
                          color: AppConstants.lossRed,
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
                            ? AppConstants.secondaryText.withOpacity(0.3)
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
                                    : AppConstants.secondaryText)
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
        final isDarkMode = AppConstants.isDark(context);
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
        final header = _headers[i].trim().toLowerCase();

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
    final numericOnly = InputUtils.extractDigits(trimmed);
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

  /// Simple field config for mapping column selection.
  static const List<Map<String, String>> _mappingFieldConfigs = [
    {'id': 'clientId', 'label': '客户号', 'hint': '客户号/客户编号/核心客户号'},
    {'id': 'clientName', 'label': '客户姓名', 'hint': '客户姓名/客户名/姓名'},
  ];

  /// Step 2 for mapping files: column mapping with picker, same pattern as
  /// holdings import.
  Widget _buildMappingPreviewStep(bool isDarkMode) {
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
                    Icon(CupertinoIcons.arrow_2_squarepath, size: 16, color: AppConstants.secondaryText),
                    SizedBox(width: 8),
                    Text(
                      '请将字段映射到文件中的对应列',
                      style: TextStyle(fontSize: 13, color: CupertinoColors.label),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0),
              for (int i = 0; i < _mappingFieldConfigs.length; i++)
                _buildMappingFieldItem(_mappingFieldConfigs[i], isDarkMode, i == _mappingFieldConfigs.length - 1),
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
                        onPressed: _mappingClientIdIndex >= 0 && _mappingClientNameIndex >= 0
                            ? () {
                                _prepareMappingPreview();
                                setState(() => _currentStep = 3);
                                _startMappingImport();
                              }
                            : null,
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

  Widget _buildMappingFieldItem(Map<String, String> field, bool isDarkMode, bool isLast) {
    final fieldId = field['id']!;
    final currentIndex = fieldId == 'clientId' ? _mappingClientIdIndex : _mappingClientNameIndex;
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
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.lossRed,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field['label']!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            field['hint']!,
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
                  onTap: () => _showMappingFieldPicker(fieldId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? CupertinoColors.systemGrey6.withOpacity(0.3)
                          : CupertinoColors.systemGrey6,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: currentIndex >= 0
                            ? AppConstants.secondaryText.withOpacity(0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currentIndex >= 0 ? _headers[currentIndex] : '选择列',
                          style: TextStyle(
                            fontSize: 13,
                            color: currentIndex >= 0
                                ? (isDarkMode ? CupertinoColors.white : AppConstants.secondaryText)
                                : (isDarkMode ? CupertinoColors.white.withOpacity(0.8) : CupertinoColors.systemGrey),
                          ),
                        ),
                        Icon(CupertinoIcons.chevron_down, size: 14,
                            color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 0),
      ],
    );
  }

  void _showMappingFieldPicker(String fieldId) {
    final currentIndex = fieldId == 'clientId' ? _mappingClientIdIndex : _mappingClientNameIndex;
    var tempIndex = currentIndex;

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDarkMode = AppConstants.isDark(context);
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
                    initialItem: tempIndex >= 0 ? tempIndex + 1 : 0,
                  ),
                  onSelectedItemChanged: (index) {
                    tempIndex = index == 0 ? -1 : index - 1;
                    setState(() {
                      if (fieldId == 'clientId') {
                        _mappingClientIdIndex = tempIndex;
                      } else {
                        _mappingClientNameIndex = tempIndex;
                      }
                    });
                  },
                  children: [
                    Center(child: Text('不映射', style: TextStyle(color: textColor))),
                    ..._headers.map((h) => Center(child: Text(h, style: TextStyle(color: textColor)))),
                  ],
                ),
              ),
              Container(height: 0.5, color: CupertinoColors.separator),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: '取消',
                        onPressed: () {
                          setState(() {
                            if (fieldId == 'clientId') {
                              _mappingClientIdIndex = currentIndex;
                            } else {
                              _mappingClientNameIndex = currentIndex;
                            }
                          });
                          Navigator.pop(context);
                        },
                        isPrimary: false,
                        height: 44,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassButton(
                        label: '确定',
                        onPressed: () => Navigator.pop(context),
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

  /// Step 3 for mapping files: import progress and result.
  Widget _buildMappingConfirmStep(bool isDarkMode) {
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
                          _isImporting
                              ? CupertinoIcons.arrow_down_circle
                              : CupertinoIcons.checkmark_circle_fill,
                          size: 24,
                          color: _isImporting
                              ? AppConstants.secondaryText
                              : AppConstants.tertiaryText,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isImporting ? '正在导入...' : '导入完成',
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
                        color: AppConstants.secondaryText.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMappingStat(
                            _isImporting ? '$_mappingNewCount' : '${_importResult?.successCount ?? 0}',
                            '新增',
                            AppConstants.secondaryText,
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDarkMode
                                ? CupertinoColors.white.withOpacity(0.2)
                                : CupertinoColors.systemGrey4,
                          ),
                          _buildMappingStat(
                            _isImporting ? '$_mappingSkipCount' : '${_importResult?.skipCount ?? 0}',
                            '跳过',
                            AppConstants.lossRed.withOpacity(0.6),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDarkMode
                                ? CupertinoColors.white.withOpacity(0.2)
                                : CupertinoColors.systemGrey4,
                          ),
                          _buildMappingStat(
                            _isImporting ? '--' : '${_importResult?.failCount ?? 0}',
                            '失败',
                            _importResult != null && _importResult!.failCount > 0
                                ? AppConstants.lossRed
                                : AppConstants.tertiaryText,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Progress bar
                    if (_isImporting) ...[
                      Stack(
                        children: [
                          Container(
                            height: 4,
                            width: double.infinity,
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
                                  color: AppConstants.secondaryText,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_importProgress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode
                              ? CupertinoColors.white.withOpacity(0.7)
                              : CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!_isImporting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Center(
                    child: GlassButton(
                      label: '完成',
                      onPressed: () => Navigator.of(context).pop(),
                      isPrimary: true,
                      width: 200,
                      height: 44,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMappingStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
        ),
      ],
    );
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
                              ? AppConstants.secondaryText
                              : (_importResult!.successCount > 0
                              ? AppConstants.tertiaryText
                              : AppConstants.lossRed),
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
                        color: AppConstants.secondaryText.withOpacity(0.1),
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
                                  color: AppConstants.secondaryText,
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
                                  color: _invalidRowsCount > 0 ? AppConstants.lossRed : AppConstants.tertiaryText,
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
                                  color: AppConstants.secondaryText,
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
                                  color: AppConstants.tertiaryText,
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
                                  color: _importResult!.failCount > 0 ? AppConstants.lossRed : AppConstants.tertiaryText,
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
                          color: AppConstants.lossRed.withOpacity(0.1),
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
                                  color: AppConstants.lossRed,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '异常信息',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.lossRed,
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
                                  color: AppConstants.lossRed,
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
                                    color: AppConstants.lossRed.withOpacity(0.7),
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
                          color: AppConstants.tertiaryText.withOpacity(0.1),
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
                                  color: AppConstants.tertiaryText,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '跳过信息',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.tertiaryText,
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
                                  color: AppConstants.tertiaryText,
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
                                    color: AppConstants.tertiaryText.withOpacity(0.7),
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
                          color: AppConstants.lossRed.withOpacity(0.1),
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
                                  color: AppConstants.lossRed,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '失败信息',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.lossRed,
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
                                  color: AppConstants.lossRed,
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
                                    color: AppConstants.lossRed.withOpacity(0.7),
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
                                  color: AppConstants.secondaryText,
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
    await showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDarkMode = AppConstants.isDark(context);
        
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
  
  Future<void> _downloadHoldingTemplate() async {
    try {
      final headers = [
        '客户姓名', '客户号', '基金代码', '购买金额', '购买份额', '购买日期',
        '交易类型(选填)', '交易金额(选填)', '交易份额(选填)', '交易日期(选填)'
      ];
      final sampleData = [
        ['张三', '001289434001', '000001', '10000.00', '8000.00', '2024-01-15', '', '', '', ''],
        ['李四', '001230109501', '110022', '20000.00', '15000.00', '2024-02-20', '加仓', '5000.00', '3500.00', '2024-03-15'],
        ['王五', '001145237901', '519674', '5000.00', '4500.00', '2024-03-10', '减仓', '2000.00', '1800.00', '2024-04-10'],
      ];

      final bytes = _generateTemplateExcelBytes(headers, sampleData);
      await _saveTemplateFile(bytes, 'FundLink-持仓模板', 'xlsx');

      if (mounted) context.showToast('持仓模板已保存');
    } catch (e) {
      if (mounted) context.showToast('生成模板失败: $e');
    }
  }

  Future<void> _downloadMappingTemplate() async {
    try {
      final headers = ['客户号', '客户姓名'];
      final sampleData = [
        ['001289434001', '张三'],
        ['001230109501', '李四'],
        ['001145237901', '王五'],
        ['001325216901', '赵六'],
        ['001220895601', '孙七'],
      ];

      final bytes = _generateTemplateExcelBytes(headers, sampleData, sheetName: 'biao');
      await _saveTemplateFile(bytes, 'FundLink-映射索引模板', 'xlsx');

      if (mounted) context.showToast('映射模板已保存');
    } catch (e) {
      if (mounted) context.showToast('生成模板失败: $e');
    }
  }

  Uint8List _generateTemplateExcelBytes(
    List<String> headers,
    List<List<String>> sampleData, {
    String sheetName = 'Sheet1',
  }) {
    final excelFile = excel.Excel.createExcel();
    final sheet = excelFile[sheetName];

    for (int i = 0; i < headers.length; i++) {
      final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0);
      sheet.cell(cellIndex).value = excel.TextCellValue(headers[i]);
    }

    for (int r = 0; r < sampleData.length; r++) {
      for (int c = 0; c < sampleData[r].length; c++) {
        final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1);
        sheet.cell(cellIndex).value = excel.TextCellValue(sampleData[r][c]);
      }
    }

    final fileBytes = excelFile.encode();
    if (fileBytes == null) {
      throw Exception('生成 Excel 文件失败');
    }
    return Uint8List.fromList(fileBytes);
  }

  Future<void> _saveTemplateFile(Uint8List bytes, String name, String extension) async {
    if (kIsWeb) {
      final mimeType = extension == 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/csv;charset=utf-8';
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', '$name.$extension')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      if (Platform.isAndroid) {
        final ok = await checkPermission(
          context: context,
          permission: Permission.storage,
          featureDescription: '存储空间',
        );
        if (!ok) return;
      }
      final savedPath = await FileSaver.instance.saveAs(
        name: name,
        bytes: bytes,
        fileExtension: extension,
        mimeType: MimeType.other,
      );

      if (savedPath != null && savedPath.isNotEmpty) {
        // success - message handled by caller
      } else {
        if (mounted) context.showToast('已取消保存');
      }
    }
  }

  Future<void> _pickFile() async {
    // 存储权限：现代系统文件选择器通常自动处理权限，
    // 但旧版 Android 需要存储权限才能读取外部文件
    // NOTE: Platform.isAndroid from dart:io is NOT available on web — guard with kIsWeb.
    if (!kIsWeb && Platform.isAndroid) {
      final ok = await checkPermission(
        context: context,
        permission: Permission.storage,
        featureDescription: '存储空间',
      );
      if (!ok) return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        withData: true,
      );
      if (result != null) {
        final file = result.files.single;
        final fileSize = file.size;
        const int maxFileSize = 5 * 1024 * 1024;

        if (fileSize > maxFileSize) {
          if (mounted) {
            context.showToast('文件大小超过限制(最大5MB)');
          }
          return;
        }

        Uint8List? bytes = file.bytes;

        // On web, FilePicker may not provide bytes directly — read from the
        // platform file bytes or use the HTML File API to read them.
        if (bytes == null && kIsWeb) {
          try {
            bytes = await _pickFileWebFallback();
          } catch (_) {
            if (mounted) context.showToast('无法读取文件内容');
            return;
          }
        }

        if (bytes == null) {
          if (mounted) context.showToast('无法读取文件内容');
          return;
        }

        if (mounted) {
          setState(() {
            _fileName = file.name;
          });
        }
        _processBytes(bytes, file.name);
      }
    } catch (e) {
      if (mounted) {
        context.showToast('文件选择失败: $e');
      }
    }
  }

  /// Web fallback: use a hidden HTML file input when FilePicker doesn't
  /// provide bytes on web.  Reads the first selected file as Uint8List.
  Future<Uint8List?> _pickFileWebFallback() async {
    final completer = Completer<Uint8List?>();
    final input = html.document.createElement('input') as html.InputElement
      ..type = 'file'
      ..accept = '.csv,.xlsx,.xls'
      ..style.display = 'none';

    html.document.body?.append(input);

    StreamSubscription<html.Event>? changeSub;
    StreamSubscription<html.Event>? loadEndSub;
    StreamSubscription<html.Event>? errorSub;
    changeSub = input.onChange.listen((event) {
      changeSub?.cancel();
      final files = (input as html.FileUploadInputElement).files;
      input.remove();
      if (files == null || files.isEmpty) {
        completer.complete(null);
        return;
      }
      final reader = html.FileReader();
      loadEndSub = reader.onLoadEnd.listen((_) {
        loadEndSub?.cancel();
        errorSub?.cancel();
        final result = reader.result;
        if (result is Uint8List) {
          completer.complete(result);
        } else if (result is List<int>) {
          completer.complete(Uint8List.fromList(result));
        } else {
          completer.complete(null);
        }
      });
      errorSub = reader.onError.listen((_) {
        loadEndSub?.cancel();
        errorSub?.cancel();
        completer.complete(null);
      });
      reader.readAsArrayBuffer(files[0]);
    });

    input.click();
    return completer.future;
  }

  String _getCellValue(dynamic cell) {
    if (cell == null) return '';

    try {
      final val = cell.value;
      if (val == null) return '';

      if (val is excel.TextCellValue) {
        return val.value.text ?? '';
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
    // Strip UTF-8 BOM if present (0xEF, 0xBB, 0xBF)
    int offset = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      offset = 3;
      debugPrint('[Import] 检测到 UTF-8 BOM，已跳过');
    }

    final effectiveBytes = offset > 0 ? bytes.sublist(offset) : bytes;

    try {
      return utf8.decode(effectiveBytes, allowMalformed: false);
    } catch (_) {
      // Not valid UTF-8, try GBK
    }

    try {
      return gbk.decode(bytes);
    } catch (_) {
      // Not GBK either, try Latin1
    }

    try {
      return latin1.decode(bytes);
    } catch (_) {
      throw Exception('文件编码无法识别，请确保文件是有效的 CSV 格式\n支持的编码：UTF-8(含BOM), GBK, Latin1');
    }
  }

  Future<void> _processBytes(Uint8List bytes, String fileName) async {
    const int maxFileSize = 5 * 1024 * 1024;
    if (bytes.length > maxFileSize) {
      throw Exception('文件大小超过限制(最大5MB)');
    }

    if (mounted) setState(() => _isProcessing = true);
    try {
      final extension = fileName.split('.').last.toLowerCase();

      final isFullBackup = await FileImportService.detectFullBackup(bytes, extension);

      if (isFullBackup) {
        await _processFullBackup(bytes, extension);
        return;
      }

      final actualFormat = FileImportService.detectFileFormat(bytes, extension);

      if (actualFormat == 'excel') {
        try {
          final excelFile = FileImportService.decodeExcelSafe(bytes);
          if (excelFile.tables.isEmpty) {
            throw Exception('Excel 文件没有工作表');
          }
          final sheet = excelFile.tables[excelFile.tables.keys.first];
          if (sheet == null || sheet.rows.isEmpty) {
            throw Exception('Excel 工作表为空');
          }
          _headers = sheet.rows.first.map((cell) => _getCellValue(cell).trim()).toList();
          _rawData = sheet.rows.skip(1)
              .map((row) => row.map((cell) => _getCellValue(cell)).toList())
              .where((row) => row.any((cell) => cell.trim().isNotEmpty))
              .toList();
        } catch (e) {
          // An xlsx file is a ZIP archive starting with PK. CSV fallback
          // on binary data only produces garbage — skip it and fail early.
          final isZip = bytes.length >= 4 &&
              bytes[0] == 0x50 && bytes[1] == 0x4B;
          if (isZip) {
            throw Exception(
              '无法解析此 Excel 文件，文件可能已损坏或格式不兼容。'
              '请尝试用 Excel 或 WPS 重新保存文件后再次导入。'
              '\n技术细节: $e',
            );
          }
          // Extension says xlsx but it's not a ZIP — maybe a renamed CSV.
          try {
            final csvString = _decodeCsvBytes(bytes);
            final rows = const CsvToListConverter().convert(csvString);
            if (rows.isEmpty) throw Exception('CSV 文件为空');
            _headers = rows.first.map((e) => e?.toString().trim() ?? '').toList();
            _rawData = rows.skip(1)
                .where((row) => row.any((cell) => cell?.toString().trim().isNotEmpty ?? false))
                .toList();
          } catch (csvError) {
            throw Exception('文件格式错误：既不是有效的 Excel 文件，也不是有效的 CSV 文件\n原始错误: $e');
          }
        }
      } else if (actualFormat == 'csv') {
        try {
          final csvString = _decodeCsvBytes(bytes);
          final rows = const CsvToListConverter().convert(csvString);
          if (rows.isEmpty) {
            throw Exception('CSV 文件为空');
          }
          _headers = rows.first.map((e) => e?.toString().trim() ?? '').toList();
          _rawData = rows.skip(1)
              .where((row) => row.any((cell) => cell?.toString().trim().isNotEmpty ?? false))
              .toList();
        } catch (e) {
          throw Exception('CSV 文件解析失败: $e');
        }
      } else {
        throw Exception('不支持的文件格式: $extension，请上传 CSV 或 Excel 文件');
      }

      if (_headers.isEmpty) {
        throw Exception('文件没有表头行，请确保第一行包含列名（如：客户号、客户姓名等）');
      }

      if (_rawData.isEmpty) {
        throw Exception(
          '文件没有数据行，已识别到${_headers.length}个表头列：${_headers.join('、')}，'
          '但未找到有效数据。请检查：\n'
          '1. 文件是否只有表头没有数据\n'
          '2. 数据行是否全部为空\n'
          '3. 如果是 Excel 文件，尝试另存为 .csv 格式再导入',
        );
      }

      _detectedFileType = _detectFileType(_headers);
      debugPrint('[Import] 检测到文件类型: $_detectedFileType');

      if (_detectedFileType == ImportFileType.mapping) {
        _autoDetectMappingColumns();
        _prepareMappingPreview();
        setState(() => _currentStep = 2);
        return;
      }

      _autoSuggestMapping();
      setState(() => _currentStep = 2);
    } catch (e) {
      if (!context.mounted) return;
      final dataManager = DataManagerProvider.of(context);
      dataManager.addLog('导入文件解析失败: $_fileName - $e', type: LogType.error);
      if (context.mounted) {
        final friendlyMessage = ErrorHandler.getUserFriendlyErrorMessage(e);
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
  
  ImportFileType _detectFileType(List<String> headers) {
    final lowerHeaders = headers.map((h) => h.toLowerCase()).toList();

    // Fund code is the key differentiator — only holding files have it
    bool hasFundCode = false;
    for (final header in lowerHeaders) {
      if (header.contains('基金代码') ||
          header.contains('产品代码') ||
          header.contains('fundcode') ||
          header.contains('fund_code') ||
          header.contains('fund code')) {
        hasFundCode = true;
        break;
      }
    }

    if (hasFundCode) {
      return ImportFileType.holding;
    }

    // No fund code — check if it's a mapping file (clientId + clientName)
    bool hasClientIdColumn = false;
    bool hasClientNameColumn = false;

    for (final header in lowerHeaders) {
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

    if (hasClientIdColumn && hasClientNameColumn) {
      return ImportFileType.mapping;
    }

    // Secondary check: amount/shares columns suggest a holding file
    bool hasAmountOrShares = false;
    for (final header in lowerHeaders) {
      if (header.contains('购买金额') ||
          header.contains('申购金额') ||
          header.contains('成本') ||
          header.contains('份额') ||
          header.contains('amount') ||
          header.contains('shares') ||
          header.contains('purchase')) {
        hasAmountOrShares = true;
        break;
      }
    }

    if (hasAmountOrShares) {
      return ImportFileType.holding;
    }

    return ImportFileType.holding;
  }

  /// Auto-detect client ID and client name column indices for mapping files.
  void _autoDetectMappingColumns() {
    _mappingClientIdIndex = -1;
    _mappingClientNameIndex = -1;

    for (int i = 0; i < _headers.length; i++) {
      final header = _headers[i].trim().toLowerCase();

      if (_mappingClientIdIndex == -1 &&
          (header.contains('客户号') ||
           header.contains('核心客户号') ||
           header.contains('用户号') ||
           header.contains('核心用户号') ||
           header.contains('客户代码') ||
           header.contains('clientid') ||
           header.contains('client_id') ||
           header.contains('user_id') ||
           header.contains('userid'))) {
        _mappingClientIdIndex = i;
      }

      if (_mappingClientNameIndex == -1 &&
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
        _mappingClientNameIndex = i;
      }
    }
  }

  /// Counts new vs skipped mappings for the preview step.
  void _prepareMappingPreview() async {
    _mappingNewCount = 0;
    _mappingSkipCount = 0;

    final existingMappings = await _mappingService.getAllMappings();
    final existingMap = <String, String>{};
    for (final m in existingMappings) {
      existingMap[m.clientId] = m.clientName;
    }

    for (final row in _rawData) {
      if (row.length <= _mappingClientIdIndex ||
          row.length <= _mappingClientNameIndex) {
        _mappingSkipCount++;
        continue;
      }
      final clientId = row[_mappingClientIdIndex]?.toString().trim() ?? '';
      final clientName = row[_mappingClientNameIndex]?.toString().trim() ?? '';
      if (clientId.isEmpty || clientName.isEmpty) {
        _mappingSkipCount++;
        continue;
      }
      if (existingMap.containsKey(clientId)) {
        _mappingSkipCount++;
      } else {
        _mappingNewCount++;
        existingMap[clientId] = clientName; // avoid double-counting duplicates
      }
    }
    setState(() {});
  }

  Future<void> _processMappingFile({void Function(double)? onProgress}) async {
    debugPrint('[Import] 开始处理映射索引文件，共${_rawData.length}条记录');

    int success = 0;
    int fail = 0;
    int skip = 0;

    // Pre-load existing mappings once
    final existingMappings = await _mappingService.getAllMappings();
    final existingMap = <String, ClientMapping>{};
    for (final m in existingMappings) {
      existingMap[m.clientId] = m;
    }

    final total = _rawData.length;
    for (int i = 0; i < total; i++) {
      final row = _rawData[i];
      try {
        if (row.length <= _mappingClientIdIndex ||
            row.length <= _mappingClientNameIndex) {
          fail++;
          continue;
        }

        final clientId = row[_mappingClientIdIndex]?.toString().trim();
        final clientName = row[_mappingClientNameIndex]?.toString().trim();

        if (clientId == null || clientId.isEmpty ||
            clientName == null || clientName.isEmpty) {
          skip++;
          continue;
        }

        final existingMapping = existingMap[clientId];

        if (existingMapping != null) {
          skip++;
        } else {
          await _mappingService.addMapping(clientId, clientName);
          success++;
          existingMap[clientId] = ClientMapping(
            id: const Uuid().v4(),
            clientId: clientId,
            clientName: clientName,
          );
        }
      } catch (e) {
        fail++;
        debugPrint('[Import] 导入映射失败: $e');
      }

      // Report progress every 10 rows or on last row
      if ((i + 1) % 10 == 0 || i == total - 1) {
        onProgress?.call((i + 1) / total);
      }
    }

    debugPrint('[Import] 映射导入结果: 成功$success, 跳过$skip, 失败$fail');

    _mappingSuccess = success;
    _mappingFail = fail;
    _mappingSkipCount = skip;

    // Sync client names to existing holdings and transactions
    if (success > 0) {
      final dataManager = DataManagerProvider.of(context);
      await dataManager.syncClientNamesFromMappings();
    }

    // Show result in the UI (don't pop — caller decides)
    final dataManager = DataManagerProvider.of(context);
    dataManager.addLog(
      '映射导入: 成功$success, 跳过$skip, 失败$fail',
      type: fail > 0 ? LogType.warning : LogType.success,
    );

    if (mounted) {
      setState(() {});
    }
  }
  
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
      
      int success = 0;
      int fail = 0;
      int skip = 0;
      
      for (final transaction in result.transactions) {
        try {
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
      
      if (!kIsWeb && success > 0) {
        await dataManager.saveData();
        debugPrint('[Import] 数据已保存到数据库');
      }
      
      if (mounted) {
        String message = '备份恢复完成';
        if (success > 0) message += '\n成功恢复 $success 条交易';
        if (skip > 0) message += '\n跳过 $skip 条重复记录';
        if (fail > 0) message += '\n失败 $fail 条';
        
        context.showToast(message);
        
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
    }
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      try {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } catch (_) {
      }
    }
    final slashParts = dateStr.split('/');
    if (slashParts.length == 3) {
      try {
        return DateTime(int.parse(slashParts[0]), int.parse(slashParts[1]), int.parse(slashParts[2]));
      } catch (_) {
      }
    }
    return null;
  }

  /// Import result counts filled by [_processMappingFile] during execution.
  int _mappingSuccess = 0;
  int _mappingFail = 0;

  Future<void> _startMappingImport() async {
    _mappingSuccess = 0;
    _mappingFail = 0;
    if (mounted) {
      setState(() {
        _isImporting = true;
        _importProgress = 0;
      });
    }

    await _processMappingFile(
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _importProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isImporting = false;
        _importProgress = 1.0;
        _importResult = ImportResult(
          successCount: _mappingSuccess,
          skipCount: _mappingSkipCount,
          failCount: _mappingFail,
          errors: const [],
          skipReasons: const [],
        );
      });
    }
  }

  Future<void> _startImport() async {
    if (mounted) {
      setState(() {
        _isImporting = true;
        _importProgress = 0;
        _shouldAbortImport = false;
        _isBackgroundImport = false;
        _isPaused = false;
      });
    }

    if (!context.mounted) return;
    final dataManager = DataManagerProvider.of(context);

    int success = 0;
    int fail = 0;
    int skip = 0;
    final errors = <String>[];
    final skipReasons = <String>[];

    // Pre-load all mappings into a local map for O(1) lookup
    final mappingMap = <String, String>{};
    try {
      final allMappings = await _mappingService.getAllMappings();
      for (final m in allMappings) {
        mappingMap[m.clientId] = m.clientName;
      }
    } catch (e) {
      debugPrint('加载客户映射失败: $e');
    }

    // Pre-build duplicate set for O(1) duplicate check
    final existingPairs = <String>{};
    for (final h in dataManager.holdings) {
      existingPairs.add('${h.clientId}_${h.fundCode}');
    }

    // Collect all unique fund codes for background fetch
    final uniqueFundCodes = <String>{};

    // Phase 1: build transaction list (no API calls)
    final transactionsToImport = <TransactionRecord>[];
    for (int i = 0; i < _validData.length; i++) {
      final row = _validData[i];
      try {
        String clientName = row['clientName']?.toString() ?? '';
        if (clientName.isEmpty) throw Exception('客户姓名为空');

        final clientId = row['clientId']?.toString() ?? '';
        if (clientId.isEmpty) throw Exception('客户号为空');

        if (clientName == clientId) {
          final mappedName = mappingMap[clientId];
          if (mappedName != null && mappedName.isNotEmpty) {
            clientName = mappedName;
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

        final pairKey = '${clientId}_$fundCode';
        if (existingPairs.contains(pairKey)) {
          skip++;
          skipReasons.add('$clientName / $fundCode');
          continue;
        }
        existingPairs.add(pairKey);

        uniqueFundCodes.add(fundCode);

        final transaction = TransactionRecord(
          clientId: clientId,
          clientName: clientName,
          fundCode: fundCode,
          fundName: '',
          type: TransactionType.buy,
          amount: purchaseAmount,
          shares: purchaseShares,
          tradeDate: date,
          nav: null,
          remarks: '',
        );

        transactionsToImport.add(transaction);
        success++;
      } catch (e) {
        fail++;
        errors.add('第${i + 1}行: $e');
      }

      // Progress driven entirely by Phase 2 (addTransactionsBatch)
    }

    // Phase 2: batch insert (0% → 100% via onProgress)
    if (transactionsToImport.isNotEmpty) {
      await dataManager.addTransactionsBatch(
        transactionsToImport,
        onProgress: (progress) {
          if (mounted) {
            _animationController.animateTo(progress,
                duration: const Duration(milliseconds: 60),
                curve: Curves.easeOut);
          }
        },
      );
    }

    if (mounted) {
      _animationController.animateTo(1.0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }

    if (mounted) {
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
    }

    String message = '导入完成';
    if (success > 0) message += '，成功$success条';
    if (skip > 0) message += '，跳过$skip条';
    if (fail > 0) message += '，失败$fail条';
    if (mounted) context.showToast(message);

    if (fail > 0) {
      dataManager.addLog('批量导入: 成功$success, 跳过$skip, 失败$fail', type: LogType.warning);
    } else {
      dataManager.addLog('批量导入: 成功$success, 跳过$skip', type: LogType.success);
    }

    // Phase 3: fetch fund info in background (non-blocking)
    if (uniqueFundCodes.isNotEmpty) {
      _fetchFundInfoInBackground(uniqueFundCodes.toList(), dataManager);
    }
  }

  Future<void> _fetchFundInfoInBackground(
    List<String> fundCodes,
    DataManager dataManager,
  ) async {
    final fundService = FundService(dataManager);
    const batchSize = 5;

    for (int i = 0; i < fundCodes.length; i += batchSize) {
      final batch = fundCodes.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((code) async {
        try {
          final fundInfo = await fundService.fetchFundInfo(code);
          final fundName = fundInfo['fundName'] as String? ?? '';
          final currentNav = fundInfo['currentNav'] as double? ?? 0.0;
          final navReturn1m = fundInfo['navReturn1m'] as double?;
          final navReturn3m = fundInfo['navReturn3m'] as double?;
          final navReturn6m = fundInfo['navReturn6m'] as double?;
          final navReturn1y = fundInfo['navReturn1y'] as double?;

          if (fundName.isNotEmpty && fundName != '未知基金' && fundName != '加载失败') {
            final holdings = dataManager.holdings;
            for (final holding in holdings) {
              if (holding.fundCode == code && holding.fundName.isEmpty) {
                await dataManager.updateHolding(holding.copyWith(
                  fundName: fundName,
                  currentNav: currentNav > 0 ? currentNav : holding.currentNav,
                  navDate: fundInfo['navDate'] as DateTime? ?? holding.navDate,
                  isValid: currentNav > 0,
                  navReturn1m: navReturn1m ?? holding.navReturn1m,
                  navReturn3m: navReturn3m ?? holding.navReturn3m,
                  navReturn6m: navReturn6m ?? holding.navReturn6m,
                  navReturn1y: navReturn1y ?? holding.navReturn1y,
                ));
              }
            }
          }
        } catch (_) {
          // Background fetch failures are non-critical
        }
      }));
    }

    await dataManager.saveData();
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
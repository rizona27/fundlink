import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart' as excel;
import '../constants/app_constants.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:universal_html/html.dart' as html;

import 'dart:io' as io;
import 'package:permission_handler/permission_handler.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../services/data_manager.dart';
import '../utils/permission_gate.dart';

/// Result returned by [FileExportService] so callers can handle UI themselves.
class ExportResult {
  final bool success;
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String? savedPath;
  final String? errorMessage;

  const ExportResult({
    required this.success,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.savedPath,
    this.errorMessage,
  });

  factory ExportResult.cancelled() {
    return ExportResult(
      success: false,
      bytes: _emptyBytes,
      fileName: '',
      mimeType: '',
    );
  }

  static final Uint8List _emptyBytes = Uint8List(0);
}

class FileExportService {
  static DataManager? _dataManager;

  static void setDataManager(DataManager manager) {
    _dataManager = manager;
  }

  /// Generates export data. Caller handles saving & UI.
  static Future<ExportResult> exportData({
    required String format,
    required List<FundHolding> holdings,
    required List<String> selectedFields,
  }) async {
    if (holdings.isEmpty) {
      return ExportResult(
        success: false,
        bytes: Uint8List(0),
        fileName: '',
        mimeType: '',
        errorMessage: '没有数据可导出',
      );
    }

    final result = await _generateExport(
      holdings: holdings,
      format: format,
      selectedFields: selectedFields,
    );
    return ExportResult(
      success: true,
      bytes: result.bytes,
      fileName: result.fileName,
      mimeType: result.mimeType,
    );
  }

  /// Generates full backup data. Caller handles saving & UI.
  static Future<ExportResult> exportFullBackupData({required String format}) async {
    if (_dataManager == null) {
      return ExportResult(
        success: false,
        bytes: Uint8List(0),
        fileName: '',
        mimeType: '',
        errorMessage: 'DataManager未初始化',
      );
    }

    final holdings = _dataManager!.holdings;
    final transactions = _dataManager!.transactions;

    if (holdings.isEmpty && transactions.isEmpty) {
      return ExportResult(
        success: false,
        bytes: Uint8List(0),
        fileName: '',
        mimeType: '',
        errorMessage: '没有数据可导出',
      );
    }

    final result = await _generateFullBackup(
      holdings: holdings,
      transactions: transactions,
      format: format,
    );
    return ExportResult(
      success: true,
      bytes: result.bytes,
      fileName: result.fileName,
      mimeType: result.mimeType,
    );
  }

  /// Saves file to disk & returns the saved path (or null if cancelled).
  /// Returns (savedPath, errorMessage).
  static Future<({String? savedPath, String? error})> saveToDisk({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    bool checkStoragePermission = true,
  }) async {
    // --- Web path ---
    if (kIsWeb) {
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
      return (savedPath: null, error: null); // web can't report a path
    }

    // --- Native path ---
    if (checkStoragePermission && io.Platform.isAndroid) {
      final ok = await checkPermission(
        permission: Permission.storage,
        featureDescription: '存储空间',
      );
      if (!ok) return (savedPath: null, error: null); // user cancelled permission
    }

    try {
      final nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
      final extension = fileName.split('.').last;
      final savedPath = await FileSaver.instance.saveAs(
        name: nameWithoutExt,
        bytes: bytes,
        fileExtension: extension,
        mimeType: MimeType.other,
      );
      return (savedPath: savedPath?.isNotEmpty == true ? savedPath : null, error: null);
    } catch (e) {
      return (savedPath: null, error: e.toString());
    }
  }

  /// Shares bytes as a temporary file.
  static Future<String?> shareFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb) return null;
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = io.File(filePath);
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(filePath)], text: '分享我的基金持仓数据');
      return null; // success
    } catch (e) {
      return e.toString();
    }
  }

  // ── Internal generators ───────────────────────────────────

  static Future<({Uint8List bytes, String fileName, String mimeType})> _generateExport({
    required List<FundHolding> holdings,
    required String format,
    required List<String> selectedFields,
  }) async {
    final timestamp = DateTime.now();
    final dateStr = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final fileName = 'Fundlink_$dateStr.${format == 'csv' ? 'csv' : 'xlsx'}';
    final mimeType = format == 'csv'
        ? 'text/csv'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    Uint8List bytes;
    if (format == 'csv') {
      bytes = await _generateCsvBytes(holdings, selectedFields);
    } else {
      bytes = await _generateExcelBytes(holdings, selectedFields);
    }
    return (bytes: bytes, fileName: fileName, mimeType: mimeType);
  }

  static Future<({Uint8List bytes, String fileName, String mimeType})> _generateFullBackup({
    required List<FundHolding> holdings,
    required List<TransactionRecord> transactions,
    required String format,
  }) async {
    final timestamp = DateTime.now();
    final dateStr = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}';
    final fileName = 'Fundlink_FullBackup_${dateStr}_${timeStr}.${format == 'csv' ? 'csv' : 'xlsx'}';
    final mimeType = format == 'csv'
        ? 'text/csv'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    Uint8List bytes;
    if (format == 'csv') {
      bytes = await _generateFullBackupCsvBytes(holdings, transactions);
    } else {
      bytes = await _generateFullBackupExcelBytes(holdings, transactions);
    }
    return (bytes: bytes, fileName: fileName, mimeType: mimeType);
  }

  static Future<Uint8List> _generateCsvBytes(List<FundHolding> holdings, List<String> selectedFields) async {
    final headers = selectedFields.map((field) => _getFieldLabel(field)).toList();
    final rows = holdings.map((h) {
      return selectedFields.map((field) => _getFieldValue(h, field, dataManager: _dataManager)).toList();
    }).toList();
    final csvData = [headers, ...rows];
    final csvString = const ListToCsvConverter().convert(csvData);
    return Uint8List.fromList(utf8.encode(csvString));
  }

  static Future<Uint8List> _generateExcelBytes(List<FundHolding> holdings, List<String> selectedFields) async {
    final ex = excel.Excel.createExcel();
    final sheet = ex.sheets['Sheet1'] ?? ex['Sheet1'];

    for (int i = 0; i < selectedFields.length; i++) {
      final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0);
      sheet.cell(cellIndex).value = excel.TextCellValue(_getFieldLabel(selectedFields[i]));
    }

    for (int r = 0; r < holdings.length; r++) {
      final holding = holdings[r];
      for (int c = 0; c < selectedFields.length; c++) {
        final value = _getFieldValue(holding, selectedFields[c], dataManager: _dataManager);
        final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1);
        sheet.cell(cellIndex).value = excel.TextCellValue(value);
      }
    }

    final fileBytes = ex.encode();
    if (fileBytes == null) {
      throw Exception('生成 Excel 文件失败');
    }
    return Uint8List.fromList(fileBytes);
  }

  static String _getFieldLabel(String fieldId) {
    switch (fieldId) {
      case 'clientName': return '客户姓名';
      case 'clientId': return '客户号';
      case 'fundCode': return '基金代码';
      case 'fundName': return '基金名称';
      case 'totalShares': return '持有份额';
      case 'totalCost': return '累计成本';
      case 'averageCost': return '平均成本';
      case 'currentNav': return '当前净值';
      case 'navDate': return '净值日期';
      case 'purchaseDate': return '购买日期';
      case 'purchaseAmount': return '购买金额';
      case 'purchaseShares': return '购买份额';
      case 'profit': return '绝对收益';
      case 'profitRate': return '绝对收益率(%)';
      case 'annualizedProfitRate': return '年化收益率(%)';
      case 'holdingDays': return '持有天数';
      case 'totalValue': return '持仓市值';
      case 'navReturn1m': return '近1月收益(%)';
      case 'navReturn3m': return '近3月收益(%)';
      case 'navReturn6m': return '近6月收益(%)';
      case 'navReturn1y': return '近1年收益(%)';
      case 'remarks': return '备注';
      default: return fieldId;
    }
  }

  static String _getFieldValue(FundHolding holding, String fieldId, {DataManager? dataManager}) {
    switch (fieldId) {
      case 'clientName': return holding.clientName;
      case 'clientId': return holding.clientId;
      case 'fundCode': return holding.fundCode;
      case 'fundName': return holding.fundName;
      case 'totalShares': return holding.totalShares.toStringAsFixed(AppConstants.sharesDecimalPlaces);
      case 'totalCost': return holding.totalCost.toStringAsFixed(2);
      case 'averageCost': return holding.averageCost.toStringAsFixed(4);
      case 'currentNav': return holding.currentNav.toStringAsFixed(4);
      case 'navDate': return holding.navDate.toIso8601String().split('T')[0];
      case 'purchaseDate':
        if (dataManager != null) {
          final transactions = dataManager.getTransactionHistory(holding.clientId, holding.fundCode);
          if (transactions.isNotEmpty) {
            return transactions.first.tradeDate.toIso8601String().split('T')[0];
          }
        }
        return '';
      case 'purchaseAmount': return holding.totalCost.toStringAsFixed(2);
      case 'purchaseShares': return holding.totalShares.toStringAsFixed(AppConstants.sharesDecimalPlaces);
      case 'profit': return holding.profit.toStringAsFixed(2);
      case 'profitRate': return holding.profitRate.toStringAsFixed(2);
      case 'annualizedProfitRate':
        if (dataManager != null) {
          return dataManager.calculateProfit(holding).annualized.toStringAsFixed(2);
        }
        return '0.00';
      case 'holdingDays':
        if (dataManager != null) {
          final transactions = dataManager.getTransactionHistory(holding.clientId, holding.fundCode);
          if (transactions.isNotEmpty) {
            final days = DateTime.now().difference(transactions.last.tradeDate).inDays;
            return days.toString();
          }
        }
        return '0';
      case 'totalValue': return holding.totalValue.toStringAsFixed(2);
      case 'navReturn1m': return holding.navReturn1m?.toStringAsFixed(2) ?? '';
      case 'navReturn3m': return holding.navReturn3m?.toStringAsFixed(2) ?? '';
      case 'navReturn6m': return holding.navReturn6m?.toStringAsFixed(2) ?? '';
      case 'navReturn1y': return holding.navReturn1y?.toStringAsFixed(2) ?? '';
      case 'remarks': return holding.remarks;
      default: return '';
    }
  }

  static List<ExportFieldDefinition> getAvailableFields() {
    return [
      ExportFieldDefinition(id: 'clientName', label: '客户姓名', required: true),
      ExportFieldDefinition(id: 'clientId', label: '客户号', required: true),
      ExportFieldDefinition(id: 'fundCode', label: '基金代码', required: true),
      ExportFieldDefinition(id: 'fundName', label: '基金名称', required: false),
      ExportFieldDefinition(id: 'totalShares', label: '持有份额', required: true),
      ExportFieldDefinition(id: 'totalCost', label: '累计成本', required: true),
      ExportFieldDefinition(id: 'averageCost', label: '平均成本', required: false),
      ExportFieldDefinition(id: 'currentNav', label: '当前净值', required: false),
      ExportFieldDefinition(id: 'navDate', label: '净值日期', required: false),
      ExportFieldDefinition(id: 'profit', label: '绝对收益', required: false),
      ExportFieldDefinition(id: 'profitRate', label: '绝对收益率(%)', required: false),
      ExportFieldDefinition(id: 'annualizedProfitRate', label: '年化收益率(%)', required: false),
      ExportFieldDefinition(id: 'holdingDays', label: '持有天数', required: false),
      ExportFieldDefinition(id: 'totalValue', label: '持仓市值', required: false),
      ExportFieldDefinition(id: 'navReturn1m', label: '近1月收益(%)', required: false),
      ExportFieldDefinition(id: 'navReturn3m', label: '近3月收益(%)', required: false),
      ExportFieldDefinition(id: 'navReturn6m', label: '近6月收益(%)', required: false),
      ExportFieldDefinition(id: 'navReturn1y', label: '近1年收益(%)', required: false),
      ExportFieldDefinition(id: 'remarks', label: '备注', required: false),
    ];
  }

  // ── Full backup helpers ────────────────────────────────────

  static Future<Uint8List> _generateFullBackupCsvBytes(
    List<FundHolding> holdings,
    List<TransactionRecord> transactions,
  ) async {
    final rows = <List<String>>[];
    rows.add(['# FundLink Full Backup', 'Version: 1.1.7', 'Export Time: ${DateTime.now().toIso8601String()}']);
    rows.add([]);
    rows.add(['=== HOLDINGS DATA ===']);
    rows.add(_getFullBackupHoldingHeaders());
    for (final h in holdings) {
      rows.add(_getFullBackupHoldingRow(h));
    }
    rows.add([]);
    rows.add(['=== TRANSACTIONS DATA ===']);
    rows.add(_getFullBackupTransactionHeaders());
    for (final tx in transactions) {
      rows.add(_getFullBackupTransactionRow(tx));
    }
    final csvString = const ListToCsvConverter().convert(rows);
    return Uint8List.fromList(utf8.encode(csvString));
  }

  static Future<Uint8List> _generateFullBackupExcelBytes(
    List<FundHolding> holdings,
    List<TransactionRecord> transactions,
  ) async {
    final ex = excel.Excel.createExcel();
    final holdingsSheet = ex['Holdings'];
    _writeFullBackupHoldingHeadersToSheet(holdingsSheet);
    for (int i = 0; i < holdings.length; i++) {
      _writeFullBackupHoldingRowToSheet(holdingsSheet, holdings[i], i + 1);
    }
    final transactionsSheet = ex['Transactions'];
    _writeFullBackupTransactionHeadersToSheet(transactionsSheet);
    for (int i = 0; i < transactions.length; i++) {
      _writeFullBackupTransactionRowToSheet(transactionsSheet, transactions[i], i + 1);
    }
    final fileBytes = ex.encode();
    if (fileBytes == null) {
      throw Exception('生成 Excel 文件失败');
    }
    return Uint8List.fromList(fileBytes);
  }

  static List<String> _getFullBackupHoldingHeaders() {
    return [
      '客户姓名', '客户号', '基金代码', '基金名称',
      '持有份额', '累计成本', '平均成本',
      '备注', '是否置顶', '置顶时间',
    ];
  }

  static List<String> _getFullBackupHoldingRow(FundHolding h) {
    return [
      h.clientName, h.clientId, h.fundCode, h.fundName,
      h.totalShares.toStringAsFixed(AppConstants.sharesDecimalPlaces),
      h.totalCost.toStringAsFixed(2),
      h.averageCost.toStringAsFixed(4),
      h.remarks ?? '',
      h.isPinned ? '是' : '否',
      h.pinnedTimestamp?.toIso8601String() ?? '',
    ];
  }

  static List<String> _getFullBackupTransactionHeaders() {
    return [
      '交易ID', '客户姓名', '客户号', '基金代码', '基金名称',
      '交易类型', '金额', '份额', '交易日期',
      '成交净值', '手续费率', '备注',
      '创建时间', '是否15点后', '是否待确认', '确认净值',
    ];
  }

  static List<String> _getFullBackupTransactionRow(TransactionRecord tx) {
    return [
      tx.id, tx.clientName, tx.clientId, tx.fundCode, tx.fundName,
      tx.type.displayName,
      tx.amount.toStringAsFixed(AppConstants.amountDecimalPlaces),
      tx.shares.toStringAsFixed(AppConstants.sharesDecimalPlaces),
      tx.tradeDate.toIso8601String().split('T')[0],
      tx.nav?.toStringAsFixed(AppConstants.navDecimalPlaces) ?? '',
      tx.fee?.toStringAsFixed(AppConstants.rateDecimalPlaces) ?? '',
      tx.remarks ?? '',
      tx.createdAt.toIso8601String(),
      tx.isAfter1500 ? '是' : '否',
      tx.isPending ? '是' : '否',
      tx.confirmedNav?.toStringAsFixed(AppConstants.navDecimalPlaces) ?? '',
    ];
  }

  static void _writeFullBackupHoldingHeadersToSheet(excel.Sheet sheet) {
    final headers = _getFullBackupHoldingHeaders();
    for (int i = 0; i < headers.length; i++) {
      final ci = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0);
      sheet.cell(ci).value = excel.TextCellValue(headers[i]);
    }
  }

  static void _writeFullBackupHoldingRowToSheet(excel.Sheet sheet, FundHolding h, int row) {
    final values = _getFullBackupHoldingRow(h);
    for (int i = 0; i < values.length; i++) {
      final ci = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row);
      sheet.cell(ci).value = excel.TextCellValue(values[i]);
    }
  }

  static void _writeFullBackupTransactionHeadersToSheet(excel.Sheet sheet) {
    final headers = _getFullBackupTransactionHeaders();
    for (int i = 0; i < headers.length; i++) {
      final ci = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0);
      sheet.cell(ci).value = excel.TextCellValue(headers[i]);
    }
  }

  static void _writeFullBackupTransactionRowToSheet(excel.Sheet sheet, TransactionRecord tx, int row) {
    final values = _getFullBackupTransactionRow(tx);
    for (int i = 0; i < values.length; i++) {
      final ci = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row);
      sheet.cell(ci).value = excel.TextCellValue(values[i]);
    }
  }
}

class ExportFieldDefinition {
  final String id;
  final String label;
  final bool required;
  ExportFieldDefinition({required this.id, required this.label, required this.required});
}

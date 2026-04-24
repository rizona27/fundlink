import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:universal_html/html.dart' as html;

// 仅在非Web平台导入dart:io
import 'dart:io' as io;
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../services/data_manager.dart';
import '../widgets/toast.dart';

class FileExportService {
  static DataManager? _dataManager;
  
  static void setDataManager(DataManager manager) {
    _dataManager = manager;
  }
  
  static Future<void> exportAndDownload({
    required List<FundHolding> holdings,
    required String format,
    required List<String> selectedFields,
    required BuildContext context,
    bool shareAfterSave = false,
  }) async {
    if (holdings.isEmpty) {
      throw Exception('没有数据可导出');
    }

    final result = await _generateExport(
      holdings: holdings,
      format: format,
      selectedFields: selectedFields,
    );

    await _saveAndDownloadFile(
      bytes: result.bytes,
      fileName: result.fileName,
      mimeType: result.mimeType,
      context: context,
      shareAfterSave: shareAfterSave,
    );
  }

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
    final excelFile = excel.Excel.createExcel();
    final sheet = excelFile.sheets['Sheet1'] ?? excelFile['Sheet1'];

    for (int i = 0; i < selectedFields.length; i++) {
      final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0);
      sheet?.cell(cellIndex).value = excel.TextCellValue(_getFieldLabel(selectedFields[i]));
    }

    for (int r = 0; r < holdings.length; r++) {
      final holding = holdings[r];
      for (int c = 0; c < selectedFields.length; c++) {
        final value = _getFieldValue(holding, selectedFields[c], dataManager: _dataManager);
        final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1);
        sheet?.cell(cellIndex).value = excel.TextCellValue(value);
      }
    }

    final fileBytes = excelFile.encode();
    if (fileBytes == null) {
      throw Exception('生成 Excel 文件失败');
    }
    return Uint8List.fromList(fileBytes);
  }

  static Future<void> _saveAndDownloadFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required BuildContext context,
    bool shareAfterSave = false,
  }) async {
    if (kIsWeb) {
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
      context.showToast('文件已开始下载');
    } else {
      final nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
      final extension = fileName.split('.').last;

      try {
        final savedPath = await FileSaver.instance.saveAs(
          name: nameWithoutExt,
          bytes: bytes,
          fileExtension: extension,
          mimeType: MimeType.other,
        );

        if (savedPath != null && savedPath.isNotEmpty) {
          context.showToast('文件已保存: $fileName');
          _dataManager?.addLog('导出文件成功: $fileName', type: LogType.success);
        } else {
          context.showToast('已取消保存');
          _dataManager?.addLog('导出文件被取消', type: LogType.info);
        }
      } catch (e) {
        context.showToast('保存文件失败: $e');
        _dataManager?.addLog('导出文件失败: $e', type: LogType.error);
      }

      if (shareAfterSave && !kIsWeb) {
        try {
          final directory = await getTemporaryDirectory();
          final filePath = '${directory.path}/$fileName';
          final file = io.File(filePath);
          await file.writeAsBytes(bytes);
          await Share.shareXFiles([XFile(filePath)], text: '分享我的基金持仓数据');
          _dataManager?.addLog('分享导出文件: $fileName', type: LogType.info);
        } catch (e) {
          context.showToast('分享失败: $e');
          _dataManager?.addLog('分享导出文件失败: $e', type: LogType.error);
        }
      }
    }
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
      case 'profit': return '绝对收益';
      case 'profitRate': return '绝对收益率(%)';
      case 'annualizedProfitRate': return '年化收益率(%)';
      case 'holdingDays': return '持有天数';
      case 'totalValue': return '持仓市值';
      case 'navReturn1w': return '近1周收益(%)';
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
      case 'totalShares': return holding.totalShares.toStringAsFixed(4);
      case 'totalCost': return holding.totalCost.toStringAsFixed(2);
      case 'averageCost': return holding.averageCost.toStringAsFixed(4);
      case 'currentNav': return holding.currentNav.toStringAsFixed(4);
      case 'navDate': return holding.navDate.toIso8601String().split('T')[0];
      case 'profit': return holding.profit.toStringAsFixed(2);
      case 'profitRate': return holding.profitRate.toStringAsFixed(2);
      case 'annualizedProfitRate': 
        // 使用DataManager计算准确的年化收益率
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
      case 'navReturn1w': return holding.navReturn1w?.toStringAsFixed(2) ?? '';
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
      ExportFieldDefinition(id: 'navReturn1w', label: '近1周收益(%)', required: false),
      ExportFieldDefinition(id: 'navReturn1m', label: '近1月收益(%)', required: false),
      ExportFieldDefinition(id: 'navReturn3m', label: '近3月收益(%)', required: false),
      ExportFieldDefinition(id: 'navReturn6m', label: '近6月收益(%)', required: false),
      ExportFieldDefinition(id: 'navReturn1y', label: '近1年收益(%)', required: false),
      ExportFieldDefinition(id: 'remarks', label: '备注', required: false),
    ];
  }
}

class ExportFieldDefinition {
  final String id;
  final String label;
  final bool required;
  ExportFieldDefinition({required this.id, required this.label, required this.required});
}
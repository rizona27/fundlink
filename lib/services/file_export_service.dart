import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:universal_html/html.dart' as html;
import '../models/fund_holding.dart';
import '../widgets/toast.dart';

class FileExportService {
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
      return selectedFields.map((field) => _getFieldValue(h, field)).toList();
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
        final value = _getFieldValue(holding, selectedFields[c]);
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
          print('保存路径: $savedPath');
        } else {
          context.showToast('已取消保存');
        }
      } catch (e) {
        print('保存文件失败: $e');
        context.showToast('保存文件失败: $e');
      }

      if (shareAfterSave) {
        try {
          final directory = await getTemporaryDirectory();
          final filePath = '${directory.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          await Share.shareXFiles([XFile(filePath)], text: '分享我的基金持仓数据');
        } catch (e) {
          print('分享文件失败: $e');
          context.showToast('分享失败: $e');
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
      case 'purchaseDate': return '购买日期';
      case 'purchaseAmount': return '购买金额';
      case 'purchaseShares': return '购买份额';
      case 'currentNav': return '当前净值';
      case 'navDate': return '净值日期';
      case 'remarks': return '备注';
      default: return fieldId;
    }
  }

  static String _getFieldValue(FundHolding holding, String fieldId) {
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

  static List<ExportFieldDefinition> getAvailableFields() {
    return [
      ExportFieldDefinition(id: 'clientName', label: '客户姓名', required: true),
      ExportFieldDefinition(id: 'clientId', label: '客户号', required: true),
      ExportFieldDefinition(id: 'fundCode', label: '基金代码', required: true),
      ExportFieldDefinition(id: 'fundName', label: '基金名称', required: false),
      ExportFieldDefinition(id: 'purchaseDate', label: '购买日期', required: true),
      ExportFieldDefinition(id: 'purchaseAmount', label: '购买金额', required: true),
      ExportFieldDefinition(id: 'purchaseShares', label: '购买份额', required: true),
      ExportFieldDefinition(id: 'currentNav', label: '当前净值', required: false),
      ExportFieldDefinition(id: 'navDate', label: '净值日期', required: false),
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
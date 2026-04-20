import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../models/fund_holding.dart';

/// 文件导出服务，支持 CSV 和 Excel 格式生成
class FileExportService {
  /// 导出持仓数据，返回临时文件路径
  /// format: 'csv' 或 'excel'
  /// selectedFields: 要导出的字段ID列表（按顺序）
  static Future<String> exportHoldings({
    required List<FundHolding> holdings,
    required String format,
    required List<String> selectedFields,
  }) async {
    if (holdings.isEmpty) {
      throw Exception('没有数据可导出');
    }

    final timestamp = DateTime.now();
    final dateStr = '${timestamp.year}${timestamp.month}${timestamp.day}_${timestamp.hour}${timestamp.minute}${timestamp.second}';
    final fileName = 'fundlink_export_$dateStr.${format == 'csv' ? 'csv' : 'xlsx'}';
    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/$fileName';

    if (format == 'csv') {
      await _writeCsv(filePath, holdings, selectedFields);
    } else {
      await _writeExcel(filePath, holdings, selectedFields);
    }

    return filePath;
  }

  static Future<void> _writeCsv(String path, List<FundHolding> holdings, List<String> selectedFields) async {
    final headers = selectedFields.map((field) => _getFieldLabel(field)).toList();
    final rows = holdings.map((h) {
      return selectedFields.map((field) => _getFieldValue(h, field)).toList();
    }).toList();

    final csvData = [headers, ...rows];
    final csvString = const ListToCsvConverter().convert(csvData);
    await File(path).writeAsString(csvString);
  }

  static Future<void> _writeExcel(String path, List<FundHolding> holdings, List<String> selectedFields) async {
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
    await File(path).writeAsBytes(fileBytes);
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
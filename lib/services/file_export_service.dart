import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import '../models/fund_holding.dart';

/// 文件导出服务，支持 CSV 和 Excel 格式生成，并处理各平台的文件保存/分享
class FileExportService {
/// 导出并下载/分享持仓数据
/// format: 'csv' 或 'excel'
/// selectedFields: 要导出的字段ID列表（按顺序）
static Future<void> exportAndDownload({
required List<FundHolding> holdings,
required String format,
required List<String> selectedFields,
}) async {
if (holdings.isEmpty) {
throw Exception('没有数据可导出');
}

// 1. 生成字节流、文件名和 MIME 类型
final result = await _generateExport(
holdings: holdings,
format: format,
selectedFields: selectedFields,
);

// 2. 根据平台调用不同的保存/分享逻辑
await _saveAndDownloadFile(
bytes: result.bytes,
fileName: result.fileName,
mimeType: result.mimeType,
);
}

/// 内部生成导出文件的字节流，返回 (bytes, fileName, mimeType)
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

// 写表头
for (int i = 0; i < selectedFields.length; i++) {
final cellIndex = excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0);
sheet?.cell(cellIndex).value = excel.TextCellValue(_getFieldLabel(selectedFields[i]));
}

// 写数据行
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

/// 平台适配的保存/分享文件
static Future<void> _saveAndDownloadFile({
required Uint8List bytes,
required String fileName,
required String mimeType,
}) async {
if (kIsWeb) {
// Web 端：使用 Blob 和 AnchorElement 触发下载
final blob = html.Blob([bytes], mimeType);
final url = html.Url.createObjectUrlFromBlob(blob);
final anchor = html.AnchorElement(href: url)
..setAttribute("download", fileName)
..click();
html.Url.revokeObjectUrl(url);
} else {
// 移动端（iOS/Android）：写入临时文件并通过 share_plus 分享
final directory = await getTemporaryDirectory();
final filePath = '${directory.path}/$fileName';
final file = File(filePath);
await file.writeAsBytes(bytes);
await Share.shareXFiles([XFile(filePath)], text: '导出持仓数据');
}
}

// ==================== 字段映射 ====================
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

/// 获取可用的导出字段定义（供 UI 使用）
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
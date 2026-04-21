import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import '../models/fund_holding.dart';
import 'package:uuid/uuid.dart';

class FileImportService {
  static Future<({List<String> headers, List<List<dynamic>> rows})> parseFile({
    required Uint8List bytes,
    required String extension,
  }) async {
    extension = extension.toLowerCase();
    if (extension == 'csv') {
      return _parseCsv(bytes);
    } else if (extension == 'xlsx' || extension == 'xls') {
      return _parseExcel(bytes);
    } else {
      throw Exception('不支持的文件格式: $extension，请上传 CSV 或 Excel 文件');
    }
  }

  static Future<({List<String> headers, List<List<dynamic>> rows})> _parseCsv(Uint8List bytes) async {
    final csvString = utf8.decode(bytes);
    final rows = const CsvToListConverter().convert(csvString);
    if (rows.isEmpty) {
      throw Exception('CSV 文件为空');
    }
    final headers = rows.first.map((e) => e?.toString().trim() ?? '').toList();
    final dataRows = rows.skip(1).toList();
    return (headers: headers, rows: dataRows);
  }

  static String _getCellValue(dynamic cell) {
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    if (val is excel.TextCellValue) {
      return val.value.text ?? '';
    }
    if (val is excel.IntCellValue) return val.value.toString();
    if (val is excel.DoubleCellValue) return val.value.toString();
    if (val is excel.DateTimeCellValue) {
      return '${val.year}-${val.month}-${val.day}';
    }
    return val.toString();
  }

  static Future<({List<String> headers, List<List<dynamic>> rows})> _parseExcel(Uint8List bytes) async {
    final excelFile = excel.Excel.decodeBytes(bytes);
    if (excelFile.tables.isEmpty) {
      throw Exception('Excel 文件没有工作表');
    }
    final sheet = excelFile.tables[excelFile.tables.keys.first];
    if (sheet == null || sheet.rows.isEmpty) {
      throw Exception('Excel 工作表为空');
    }
    final headers = sheet.rows.first.map((cell) => _getCellValue(cell).trim()).toList();
    final dataRows = sheet.rows.skip(1).map((row) => row.map((cell) => _getCellValue(cell)).toList()).toList();
    return (headers: headers, rows: dataRows);
  }

  static FundHolding rowToHolding(
      List<dynamic> row,
      Map<String, int> fieldMapping, {
        String? customId,
      }) {
    String getString(String fieldId) {
      final idx = fieldMapping[fieldId];
      if (idx == null || idx >= row.length) return '';
      final val = row[idx];
      return val?.toString().trim() ?? '';
    }

    double? getDouble(String fieldId) {
      final str = getString(fieldId);
      if (str.isEmpty) return null;
      return double.tryParse(str);
    }

    DateTime? getDate(String fieldId) {
      final str = getString(fieldId);
      if (str.isEmpty) return null;
      return _parseFlexibleDate(str);
    }

    final clientName = getString('clientName');
    if (clientName.isEmpty) throw Exception('客户姓名不能为空');

    final clientId = getString('clientId');
    if (clientId.isEmpty) throw Exception('客户号不能为空');

    final fundCode = getString('fundCode');
    if (fundCode.isEmpty) throw Exception('基金代码不能为空');

    final purchaseDate = getDate('purchaseDate');
    if (purchaseDate == null) throw Exception('购买日期无效或格式错误');

    final purchaseAmount = getDouble('purchaseAmount');
    if (purchaseAmount == null) throw Exception('购买金额无效');

    final purchaseShares = getDouble('purchaseShares');
    if (purchaseShares == null) throw Exception('购买份额无效');

    final fundName = getString('fundName');
    final currentNav = getDouble('currentNav') ?? 0.0;
    final navDate = getDate('navDate') ?? DateTime.now();
    final remarks = getString('remarks');

    final isValid = currentNav > 0 && fundName.isNotEmpty;

    return FundHolding(
      id: customId ?? const Uuid().v4(),
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
      remarks: remarks.isNotEmpty ? remarks : '',
      isPinned: false,
      pinnedTimestamp: null,
      navReturn1m: null,
      navReturn3m: null,
      navReturn6m: null,
      navReturn1y: null,
    );
  }

  static DateTime _parseFlexibleDate(String dateStr) {
    String normalized = dateStr.replaceAll('/', '-').replaceAll('.', '-');
    final parts = normalized.split('-');
    if (parts.length != 3) {
      throw FormatException('日期格式不正确: $dateStr');
    }
    int year, month, day;
    if (parts[0].length == 4) {
      year = int.parse(parts[0]);
      month = int.parse(parts[1]);
      day = int.parse(parts[2]);
    } else if (parts[2].length == 4) {
      year = int.parse(parts[2]);
      month = int.parse(parts[1]);
      day = int.parse(parts[0]);
    } else {
      month = int.parse(parts[0]);
      day = int.parse(parts[1]);
      year = int.parse(parts[2]);
      if (year < 100) year += 2000;
    }
    return DateTime(year, month, day);
  }
}
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import 'package:uuid/uuid.dart';

class FileImportService {
  static Future<({List<String> headers, List<List<dynamic>> rows})> parseFile({
    required Uint8List bytes,
    required String extension,
  }) async {
    extension = extension.toLowerCase();
    
    // 智能检测文件实际格式，不依赖扩展名
    final actualFormat = _detectFileFormat(bytes, extension);
    
    if (actualFormat == 'csv') {
      return _parseCsv(bytes);
    } else if (actualFormat == 'excel') {
      return _parseExcel(bytes);
    } else {
      throw Exception('不支持的文件格式，请上传 CSV 或 Excel 文件');
    }
  }
  
  /// 检测文件实际格式（基于文件头和内容）
  static String _detectFileFormat(Uint8List bytes, String extension) {
    // 如果扩展名明确是 Excel 格式，优先尝试 Excel
    if (extension == 'xlsx' || extension == 'xls') {
      return 'excel';
    }
    
    // 对于 .csv 扩展名或其他情况，检测实际内容
    // Excel (.xlsx) 文件实际上是 ZIP 格式，以 PK 开头
    if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      // ZIP 格式，很可能是 .xlsx
      return 'excel';
    }
    
    // Excel (.xls) 旧格式有特定的文件头
    if (bytes.length >= 8) {
      // D0 CF 11 E0 是 OLE2 复合文档格式（旧版 Excel）
      if (bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) {
        return 'excel';
      }
    }
    
    // 尝试检测是否为有效的 UTF-8/ASCII 文本（CSV 应该是文本格式）
    try {
      final content = utf8.decode(bytes, allowMalformed: false);
      // CSV 文件通常包含逗号、引号等字符，且不包含大量二进制数据
      // 检查是否包含常见的 CSV 特征
      if (content.contains(',') || content.contains('\t') || content.contains('\n')) {
        return 'csv';
      }
    } catch (e) {
      // 如果无法解码为 UTF-8，可能是二进制格式（Excel）
      return 'excel';
    }
    
    // 默认根据扩展名判断
    if (extension == 'csv') {
      return 'csv';
    }
    
    // 其他情况，尝试作为 CSV 处理
    return 'csv';
  }

  static Future<({List<String> headers, List<List<dynamic>> rows})> _parseCsv(Uint8List bytes) async {
    try {
      // 尝试多种编码方式解码
      String csvString;
      try {
        csvString = utf8.decode(bytes);
      } catch (e) {
        // 如果 UTF-8 失败，尝试 GBK/GB2312（中文 Excel 导出的 CSV 常用编码）
        try {
          csvString = latin1.decode(bytes); // 作为备选
        } catch (e2) {
          throw Exception('文件编码无法识别，请确保文件是有效的 CSV 格式');
        }
      }
      
      final rows = const CsvToListConverter().convert(csvString);
      if (rows.isEmpty) {
        throw Exception('CSV 文件为空');
      }
      final headers = rows.first.map((e) => e?.toString().trim() ?? '').toList();
      final dataRows = rows.skip(1).toList();
      return (headers: headers, rows: dataRows);
    } catch (e) {
      // 如果是 CSV 解析错误，提供更友好的提示
      if (e.toString().contains('custom numfmtld') || 
          e.toString().contains('FormatException')) {
        throw Exception('文件格式错误：这不是一个有效的 CSV 文件。\n\n可能的原因：\n1. 文件实际是 Excel 格式，但扩展名为 .csv\n2. 文件已损坏或编码不正确\n\n建议：\n- 在 Excel 中打开文件，选择“另存为” -> 选择“CSV (逗号分隔)”格式\n- 或直接使用 .xlsx 扩展名保存');
      }
      rethrow;
    }
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

  /// 将行数据转换为交易记录（新模型）
  static TransactionRecord rowToTransaction(
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

    final tradeDate = getDate('purchaseDate') ?? getDate('tradeDate');
    if (tradeDate == null) throw Exception('交易日期无效或格式错误');

    final amount = getDouble('purchaseAmount') ?? getDouble('amount');
    if (amount == null || amount <= 0) throw Exception('交易金额无效');

    final shares = getDouble('purchaseShares') ?? getDouble('shares');
    if (shares == null || shares <= 0) throw Exception('交易份额无效');

    // 判断交易类型：默认为买入，如果有type字段则根据字段值判断
    TransactionType type = TransactionType.buy;
    final typeStr = getString('type').toUpperCase();
    if (typeStr == 'SELL' || typeStr == '卖出') {
      type = TransactionType.sell;
    } else if (typeStr == 'BUY' || typeStr == '买入') {
      type = TransactionType.buy;
    }

    final fundName = getString('fundName');
    final nav = getDouble('currentNav') ?? getDouble('nav');
    final fee = getDouble('fee');
    final remarks = getString('remarks');

    return TransactionRecord(
      id: customId ?? const Uuid().v4(),
      clientId: clientId,
      clientName: clientName,
      fundCode: fundCode,
      fundName: fundName.isNotEmpty ? fundName : '未知基金',
      type: type,
      amount: amount,
      shares: shares,
      tradeDate: tradeDate,
      nav: nav,
      fee: fee,
      remarks: remarks.isNotEmpty ? remarks : '',
    );
  }

  /// 兼容旧方法：将行数据转换为持仓（用于向后兼容）
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
    final averageCost = purchaseAmount / purchaseShares;

    return FundHolding(
      id: customId ?? const Uuid().v4(),
      clientName: clientName,
      clientId: clientId,
      fundCode: fundCode,
      fundName: fundName,
      totalShares: purchaseShares,
      totalCost: purchaseAmount,
      averageCost: averageCost,
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
      transactionIds: [],
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
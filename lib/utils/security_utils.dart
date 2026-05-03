/// 安全工具类 - 用于处理敏感信息和错误消息
class SecurityUtils {
  SecurityUtils._();

  /// 将详细错误消息转换为友好的用户提示
  /// 
  /// 生产环境下不显示技术细节,仅显示通用错误提示
  /// 详细错误应记录到日志系统
  static String getFriendlyErrorMessage(Object error) {
    final errorStr = error.toString().toLowerCase();
    
    // 网络相关错误
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return '请求超时,请检查网络连接后重试';
    }
    if (errorStr.contains('socket') || errorStr.contains('connection')) {
      return '网络连接失败,请检查网络设置';
    }
    if (errorStr.contains('http') && errorStr.contains('4')) {
      return '请求失败,请稍后重试';
    }
    if (errorStr.contains('http') && errorStr.contains('5')) {
      return '服务器错误,请稍后重试';
    }
    
    // 数据解析错误
    if (errorStr.contains('parse') || errorStr.contains('format') || 
        errorStr.contains('decode') || errorStr.contains('json')) {
      return '数据格式错误,请重试';
    }
    
    // 文件操作错误
    if (errorStr.contains('file') || errorStr.contains('permission')) {
      return '文件操作失败,请检查权限';
    }
    
    // 默认友好提示
    return '操作失败,请稍后重试';
  }

  /// 隐藏敏感信息(如客户姓名、基金代码等)
  /// 用于日志记录时脱敏
  static String maskSensitiveData(String data, {int visibleChars = 2}) {
    if (data.length <= visibleChars) {
      return '*' * data.length;
    }
    return data.substring(0, visibleChars) + '*' * (data.length - visibleChars);
  }

  /// 验证并清理用户输入
  /// 移除潜在的危险字符
  static String sanitizeInput(String input) {
    // 移除HTML标签
    String sanitized = input.replaceAll(RegExp(r'<[^>]*>'), '');
    
    // 移除脚本标签
    sanitized = sanitized.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    
    // 限制长度(防止缓冲区溢出)
    if (sanitized.length > 1000) {
      sanitized = sanitized.substring(0, 1000);
    }
    
    return sanitized.trim();
  }
}

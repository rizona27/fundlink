class SecurityUtils {
  SecurityUtils._();

  static String getFriendlyErrorMessage(Object error) {
    final errorStr = error.toString().toLowerCase();
    
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
    
    if (errorStr.contains('parse') || errorStr.contains('format') || 
        errorStr.contains('decode') || errorStr.contains('json')) {
      return '数据格式错误,请重试';
    }
    
    if (errorStr.contains('file') || errorStr.contains('permission')) {
      return '文件操作失败,请检查权限';
    }
    
    return '操作失败,请稍后重试';
  }

  static String maskSensitiveData(String data, {int visibleChars = 2}) {
    if (data.length <= visibleChars) {
      return '*' * data.length;
    }
    return data.substring(0, visibleChars) + '*' * (data.length - visibleChars);
  }

  static String sanitizeInput(String input) {
    String sanitized = input.replaceAll(RegExp(r'<[^>]*>'), '');
    
    sanitized = sanitized.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    
    if (sanitized.length > 1000) {
      sanitized = sanitized.substring(0, 1000);
    }
    
    return sanitized.trim();
  }
}

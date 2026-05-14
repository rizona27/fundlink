/// 用户友好的错误消息映射工具
/// 
/// 将技术性错误消息转换为用户易于理解的提示。
/// 
/// 使用示例：
/// ```dart
/// try {
///   await fetchData();
/// } catch (e) {
///   showToast(getUserFriendlyErrorMessage(e));
/// }
/// ```
class ErrorMessageMapper {
  /// 获取用户友好的错误消息
  static String getUserFriendlyErrorMessage(Object error) {
    final errorStr = error.toString().toLowerCase();
    
    // 网络相关错误
    if (errorStr.contains('socketexception') || 
        errorStr.contains('connection refused') ||
        errorStr.contains('network is unreachable')) {
      return '网络连接失败，请检查网络设置';
    }
    
    if (errorStr.contains('timeout') || 
        errorStr.contains('timed out')) {
      return '请求超时，请稍后重试';
    }
    
    if (errorStr.contains('dns') || 
        errorStr.contains('host not found')) {
      return '无法连接到服务器，请检查网络';
    }
    
    // HTTP 错误
    if (errorStr.contains('404') || 
        errorStr.contains('not found')) {
      return '请求的资源不存在';
    }
    
    if (errorStr.contains('403') || 
        errorStr.contains('forbidden')) {
      return '无权访问该资源';
    }
    
    if (errorStr.contains('500') || 
        errorStr.contains('internal server error')) {
      return '服务器内部错误，请稍后重试';
    }
    
    if (errorStr.contains('502') || 
        errorStr.contains('503') ||
        errorStr.contains('bad gateway') ||
        errorStr.contains('service unavailable')) {
      return '服务暂时不可用，请稍后重试';
    }
    
    // 数据相关错误
    if (errorStr.contains('null') && 
        errorStr.contains('check')) {
      return '数据格式错误，请检查输入';
    }
    
    if (errorStr.contains('parse') || 
        errorStr.contains('format')) {
      return '数据解析失败，请检查数据格式';
    }
    
    if (errorStr.contains('invalid') || 
        errorStr.contains('illegal')) {
      return '无效的数据，请检查后重试';
    }
    
    // 文件相关错误
    if (errorStr.contains('file not found') || 
        errorStr.contains('no such file')) {
      return '文件不存在，请检查文件路径';
    }
    
    if (errorStr.contains('permission denied') || 
        errorStr.contains('access denied')) {
      return '没有权限访问该文件';
    }
    
    if (errorStr.contains('disk full') || 
        errorStr.contains('no space left')) {
      return '存储空间不足，请清理后重试';
    }
    
    // 数据库相关错误
    if (errorStr.contains('database') || 
        errorStr.contains('sqlite')) {
      return '数据库操作失败，请重启应用';
    }
    
    // JSON 解析错误
    if (errorStr.contains('json') || 
        errorStr.contains('decode')) {
      return '数据格式错误，请稍后重试';
    }
    
    // 基金相关特定错误
    if (errorStr.contains('fund') && 
        errorStr.contains('not found')) {
      return '未找到该基金信息';
    }
    
    if (errorStr.contains('nav') && 
        errorStr.contains('unavailable')) {
      return '净值数据暂未公布，请稍后再试';
    }
    
    // 默认错误消息
    return '操作失败，请稍后重试';
  }
  
  /// 根据错误类型获取更详细的建议
  static String getErrorSuggestion(Object error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('network') || 
        errorStr.contains('socket') ||
        errorStr.contains('connection')) {
      return '建议：\n1. 检查网络连接\n2. 切换 WiFi/移动数据\n3. 重启路由器';
    }
    
    if (errorStr.contains('timeout')) {
      return '建议：\n1. 检查网络速度\n2. 稍后重试\n3. 联系客服';
    }
    
    if (errorStr.contains('permission') || 
        errorStr.contains('denied')) {
      return '建议：\n1. 检查应用权限设置\n2. 在系统设置中授权\n3. 重启应用';
    }
    
    if (errorStr.contains('storage') || 
        errorStr.contains('space') ||
        errorStr.contains('disk')) {
      return '建议：\n1. 清理手机存储空间\n2. 删除不需要的文件\n3. 清理应用缓存';
    }
    
    return '';
  }
  
  /// 格式化完整的错误提示（包含建议）
  static String formatCompleteErrorMessage(Object error) {
    final message = getUserFriendlyErrorMessage(error);
    final suggestion = getErrorSuggestion(error);
    
    if (suggestion.isNotEmpty) {
      return '$message\n\n$suggestion';
    }
    
    return message;
  }
}

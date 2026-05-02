import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

/// 版本信息模型
class VersionInfo {
  final String version;
  final String versionCode;
  final String releaseNotes;
  final String downloadUrl;
  final bool hasUpdate;
  final bool forceUpdate;

  VersionInfo({
    required this.version,
    required this.versionCode,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.hasUpdate,
    this.forceUpdate = false,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      version: json['version'] ?? '',
      versionCode: json['version_code'] ?? '',
      releaseNotes: json['release_notes'] ?? '',
      downloadUrl: json['download_url'] ?? '',
      hasUpdate: json['has_update'] ?? false,
      forceUpdate: json['force_update'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'version_code': versionCode,
      'release_notes': releaseNotes,
      'download_url': downloadUrl,
      'has_update': hasUpdate,
      'force_update': forceUpdate,
    };
  }
}

/// 版本检查服务
class VersionCheckService {
  /// 检查最新版本
  static Future<VersionInfo?> checkLatestVersion(String currentVersion) async {
    try {
      debugPrint('正在检查版本更新...');
      
      final response = await http.get(
        Uri.parse(AppConstants.githubReleaseApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'FundLink-Version-Checker',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('版本检查失败: HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      
      // 解析 GitHub Release 数据
      final latestVersion = data['tag_name'] as String? ?? '';
      final releaseNotes = data['body'] as String? ?? '暂无更新说明';
      
      // 根据平台获取下载链接
      String downloadUrl = _getDownloadUrlForPlatform(data);
      
      // 如果没有找到对应平台的文件，使用 HTML URL
      if (downloadUrl.isEmpty) {
        downloadUrl = data['html_url'] as String? ?? '';
      }

      // 清理版本号格式（移除 v 前缀）
      final cleanLatestVersion = latestVersion.startsWith('v') 
          ? latestVersion.substring(1) 
          : latestVersion;

      // 比较版本号
      final hasUpdate = _compareVersions(currentVersion, cleanLatestVersion) < 0;

      debugPrint('当前版本: $currentVersion');
      debugPrint('最新版本: $cleanLatestVersion');
      debugPrint('需要更新: $hasUpdate');

      return VersionInfo(
        version: cleanLatestVersion,
        versionCode: _extractVersionCode(cleanLatestVersion),
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        hasUpdate: hasUpdate,
        forceUpdate: false, // GitHub Release 不支持强制更新标记
      );

    } catch (e) {
      debugPrint('版本检查异常: $e');
      return null;
    }
  }

  /// 比较版本号
  /// 返回值: -1 (v1 < v2), 0 (v1 == v2), 1 (v1 > v2)
  static int _compareVersions(String v1, String v2) {
    try {
      // 处理格式: 1.1.9+19
      final parts1 = v1.split('+');
      final parts2 = v2.split('+');
      
      // 比较主版本号 (1.1.9)
      final mainCompare = _compareMainVersions(parts1[0], parts2[0]);
      if (mainCompare != 0) return mainCompare;
      
      // 主版本号相同，比较构建号 (+19)
      if (parts1.length > 1 && parts2.length > 1) {
        final build1 = int.tryParse(parts1[1]) ?? 0;
        final build2 = int.tryParse(parts2[1]) ?? 0;
        
        if (build1 < build2) return -1;
        if (build1 > build2) return 1;
      }
      
      return 0;
    } catch (e) {
      debugPrint('版本比较失败: $e');
      return 0;
    }
  }

  /// 比较主版本号
  static int _compareMainVersions(String v1, String v2) {
    final segments1 = v1.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final segments2 = v2.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    
    final maxLength = segments1.length > segments2.length 
        ? segments1.length 
        : segments2.length;
    
    for (int i = 0; i < maxLength; i++) {
      final s1 = i < segments1.length ? segments1[i] : 0;
      final s2 = i < segments2.length ? segments2[i] : 0;
      
      if (s1 < s2) return -1;
      if (s1 > s2) return 1;
    }
    
    return 0;
  }

  /// 提取版本号中的构建号
  static String _extractVersionCode(String version) {
    final parts = version.split('+');
    return parts.length > 1 ? parts[1] : '0';
  }

  /// 根据平台获取下载链接
  static String _getDownloadUrlForPlatform(Map<String, dynamic> releaseData) {
    final assets = releaseData['assets'] as List? ?? [];
    final platform = defaultTargetPlatform;
    
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String? ?? '';
      
      // Android: 优先 APK
      if (platform == TargetPlatform.android && name.endsWith('.apk')) {
        return url;
      }
      
      // Windows: 优先 EXE 或 MSI
      if (platform == TargetPlatform.windows && 
          (name.endsWith('.exe') || name.endsWith('.msi'))) {
        return url;
      }
      
      // iOS/macOS: IPA 或 DMG
      if ((platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) &&
          (name.endsWith('.ipa') || name.endsWith('.dmg'))) {
        return url;
      }
    }
    
    return ''; // 未找到对应平台的文件
  }
}

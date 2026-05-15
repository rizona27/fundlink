import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../constants/app_constants.dart';
import 'http_client_provider.dart';

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

class VersionCheckService {
  static Future<VersionInfo?> checkLatestVersion(String currentVersion) async {
    final nasFuture = _checkFromNas(currentVersion).catchError((e) {
      return null;
    });
    
    final githubFuture = _checkFromGitHub(currentVersion).catchError((e) {
      return null;
    });
    
    final results = await Future.wait([nasFuture, githubFuture]);
    final nasInfo = results[0];
    final githubInfo = results[1];
    
    VersionInfo? bestInfo;
    String source = '';
    
    if (nasInfo != null && githubInfo != null) {
      final nasFullVersion = '${nasInfo.version}+${nasInfo.versionCode}';
      final githubFullVersion = '${githubInfo.version}+${githubInfo.versionCode}';
      final compare = _compareVersions(nasFullVersion, githubFullVersion);
      
      if (compare >= 0) {
        bestInfo = nasInfo;
        source = 'NAS';
      } else {
        bestInfo = githubInfo;
        source = 'GitHub';
      }
    } else if (nasInfo != null) {
      bestInfo = nasInfo;
      source = 'NAS (GitHub失败)';
    } else if (githubInfo != null) {
      bestInfo = githubInfo;
      source = 'GitHub (NAS失败)';
    }
    
    return bestInfo;
  }
  
  static Future<VersionInfo?> _checkFromNas(String currentVersion) async {
    try {
      final response = await HttpClientProvider.client.get(
        Uri.parse('${AppConstants.nasBackendUrl}/api/version'),
        headers: {
          'User-Agent': AppConstants.userAgentApp,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      
      final latestVersion = data['version'] as String? ?? '';
      final versionCode = data['versionCode'] as String? ?? '';
      final releaseNotes = data['releaseNotes'] as String? ?? '暂无更新说明';
      
      final downloads = data['downloads'] as Map<String, dynamic>? ?? {};
      String downloadUrl = _getDownloadUrlFromNas(downloads);
      
      if (downloadUrl.isEmpty) {
        downloadUrl = AppConstants.githubProjectUrl;
      }

      final fullLatestVersion = versionCode.isNotEmpty ? '$latestVersion+$versionCode' : latestVersion;
      
      final hasUpdate = _compareVersions(currentVersion, fullLatestVersion) < 0;

      return VersionInfo(
        version: latestVersion,
        versionCode: versionCode,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        hasUpdate: hasUpdate,
        forceUpdate: false,
      );

    } catch (e) {
      return null;
    }
  }
  
  static Future<VersionInfo?> _checkFromGitHub(String currentVersion) async {
    try {
      final response = await HttpClientProvider.client.get(
        Uri.parse(AppConstants.githubReleaseApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': AppConstants.userAgentVersionChecker,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      
      final latestVersion = data['tag_name'] as String? ?? '';
      final releaseNotes = data['body'] as String? ?? '暂无更新说明';
      
      String downloadUrl = _getDownloadUrlForPlatform(data);
      
      if (downloadUrl.isEmpty) {
        downloadUrl = data['html_url'] as String? ?? '';
      }

      final cleanLatestVersion = latestVersion.startsWith('v') 
          ? latestVersion.substring(1) 
          : latestVersion;

      final hasUpdate = _compareVersions(currentVersion, cleanLatestVersion) < 0;

      return VersionInfo(
        version: cleanLatestVersion,
        versionCode: _extractVersionCode(cleanLatestVersion),
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        hasUpdate: hasUpdate,
        forceUpdate: false,
      );

    } catch (e) {
      return null;
    }
  }

  static int _compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.split('+');
      final parts2 = v2.split('+');
      
      final mainCompare = _compareMainVersions(parts1[0], parts2[0]);
      if (mainCompare != 0) return mainCompare;
      
      if (parts1.length > 1 && parts2.length > 1) {
        final build1 = int.tryParse(parts1[1]) ?? 0;
        final build2 = int.tryParse(parts2[1]) ?? 0;
        
        if (build1 < build2) return -1;
        if (build1 > build2) return 1;
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }

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

  static String _extractVersionCode(String version) {
    final parts = version.split('+');
    return parts.length > 1 ? parts[1] : '0';
  }

  static String _getDownloadUrlFromNas(Map<String, dynamic> downloads) {
    final platform = defaultTargetPlatform;
    
    if (platform == TargetPlatform.android) {
      final android = downloads['android'] as Map<String, dynamic>?;
      return android?['url'] as String? ?? '';
    }
    
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      final ios = downloads['ios'] as Map<String, dynamic>?;
      return ios?['url'] as String? ?? '';
    }
    
    if (platform == TargetPlatform.windows) {
      final windows = downloads['windows'] as Map<String, dynamic>?;
      return windows?['url'] as String? ?? '';
    }
    
    return '';
  }

  static String _getDownloadUrlForPlatform(Map<String, dynamic> releaseData) {
    final assets = releaseData['assets'] as List? ?? [];
    final platform = defaultTargetPlatform;
    
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String? ?? '';
      
      if (platform == TargetPlatform.android && name.endsWith('.apk')) {
        return url;
      }
      
      if (platform == TargetPlatform.windows && 
          (name.endsWith('.exe') || name.endsWith('.msi'))) {
        return url;
      }
      
      if ((platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) &&
          (name.endsWith('.ipa') || name.endsWith('.dmg'))) {
        return url;
      }
    }
    
    return '';
  }
}

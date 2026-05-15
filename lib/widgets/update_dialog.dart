import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/version_check_service.dart';

class UpdateDialog extends StatefulWidget {
  final VersionInfo versionInfo;

  const UpdateDialog({
    super.key,
    required this.versionInfo,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.cloud_download,
            color: CupertinoColors.activeBlue,
            size: 24,
          ),
          const SizedBox(width: 8),
          const Text('发现新版本'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'v${widget.versionInfo.version}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '更新内容：',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(
                widget.versionInfo.releaseNotes,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          if (_isDownloading) ...[
            const SizedBox(height: 16),
            CupertinoActivityIndicator(),
            const SizedBox(height: 8),
            Text(
              _downloadStatus,
              style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
            ),
            if (_downloadProgress > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: _downloadProgress),
              ),
          ],
        ],
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('稍后'),
          onPressed: _isDownloading ? null : () => Navigator.pop(context),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: _isDownloading
              ? const Text('下载中...')
              : const Text('立即更新'),
          onPressed: _isDownloading ? null : _handleUpdate,
        ),
      ],
    );
  }

  Future<void> _handleUpdate() async {
    final platform = defaultTargetPlatform;
    
    if (platform == TargetPlatform.android) {
      await _downloadAndInstallApk();
    } else if (platform == TargetPlatform.windows) {
      await _openDownloadUrl();
    } else {
      await _openDownloadUrl();
    }
  }

  Future<void> _downloadAndInstallApk() async {
    if (widget.versionInfo.downloadUrl.isEmpty) {
      await _openDownloadUrl();
      return;
    }

    if (mounted) setState(() {
      _isDownloading = true;
      _downloadStatus = '准备下载...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/fundlink_update.apk';
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(widget.versionInfo.downloadUrl));
      final response = await request.send();
      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;

      final sink = file.openWrite();
      
      await response.stream.forEach((chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          if (mounted) setState(() {
            _downloadProgress = progress;
            _downloadStatus = '下载中: ${(progress * 100).toStringAsFixed(1)}%';
          });
        }
      });

      await sink.close();

      if (mounted) setState(() {
        _downloadStatus = '下载完成，准备安装...';
      });

      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }

    } catch (e) {
      if (mounted) setState(() {
        _isDownloading = false;
        _downloadStatus = '下载失败: $e';
      });
      
      await Future.delayed(const Duration(seconds: 2));
      await _openDownloadUrl();
    }
  }

  Future<void> _openDownloadUrl() async {
    if (widget.versionInfo.downloadUrl.isEmpty) return;
    
    final url = Uri.parse(widget.versionInfo.downloadUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

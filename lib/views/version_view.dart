import 'package:flutter/cupertino.dart';

class VersionView extends StatelessWidget {
  const VersionView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('版本信息'),
        backgroundColor: CupertinoColors.systemBackground,
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.info_circle_fill,
                size: 80,
                color: isDarkMode
                    ? CupertinoColors.systemBlue
                    : const Color(0xFF6366F1),
              ),
              const SizedBox(height: 24),
              Text(
                '基金持仓管理',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '版本 1.0.0',
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode
                      ? CupertinoColors.white.withOpacity(0.7)
                      : CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Build 1',
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode
                      ? CupertinoColors.white.withOpacity(0.5)
                      : CupertinoColors.systemGrey.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? CupertinoColors.systemGrey6.withOpacity(0.4)
                      : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      '更新日志',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• 初始版本发布\n'
                          '• 支持基金持仓管理\n'
                          '• 支持数据导入导出（即将推出）\n'
                          '• 支持深色模式\n'
                          '• 支持隐私模式',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
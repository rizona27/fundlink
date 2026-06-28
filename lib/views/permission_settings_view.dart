import 'dart:io' show InternetAddress;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:permission_handler/permission_handler.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/toast.dart';
import '../constants/app_constants.dart';

class PermissionSettingsView extends StatefulWidget {
  const PermissionSettingsView({super.key});

  @override
  State<PermissionSettingsView> createState() => _PermissionSettingsViewState();
}

class _PermissionSettingsViewState extends State<PermissionSettingsView> with WidgetsBindingObserver {
  late final List<_PermItem> _permissions;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissions = [
      _PermItem.network('网络', '访问互联网以获取基金数据和净值信息'),
      _PermItem(Permission.photos, '相册/媒体', '导入持仓数据、导出净值走势图到相册'),
      _PermItem(Permission.storage, '存储空间', '读取和保存导入/导出的表格文件'),
    ];
    _refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatuses();
    }
  }

  Future<void> _refreshStatuses() async {
    // Check network connectivity
    final networkItem = _permissions.firstWhere((p) => p.isNetwork);
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      networkItem.networkReachable = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      networkItem.networkReachable = false;
    }

    // Check other permissions
    for (final p in _permissions) {
      final perm = p.permission;
      if (perm != null) {
        p.status = await perm.status;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestPermission(_PermItem item) async {
    // Network: no runtime permission API, open system settings
    if (item.isNetwork) {
      await openAppSettings();
      if (mounted) context.showToast('请在系统设置中管理网络权限');
      return;
    }

    setState(() => item.requesting = true);

    final perm = item.permission;
    if (perm == null) return;
    final status = await perm.request();
    item.status = status;

    if (mounted) {
      setState(() => item.requesting = false);
      if (status.isGranted || status.isLimited) {
        context.showToast('${item.name}权限已授权');
      } else if (status.isPermanentlyDenied) {
        final openSettings = await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('需要手动开启'),
            content: Text('${item.name}权限已被系统拒绝。\n请在系统设置中手动开启。'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('打开设置'),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          await openAppSettings();
        }
      } else {
        context.showToast('${item.name}权限请求被拒绝');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppConstants.isDark(context);
    final bgColor = isDark ? AppConstants.darkBackground : AppConstants.lightBackground;

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: 0,
              showBack: true,
              onBack: () => Navigator.of(context).pop(),
              showRefresh: false,
              showExpandCollapse: false,
              showSearch: false,
              showReset: false,
              showFilter: false,
              showSort: false,
              hasData: true,
              backgroundColor: Colors.transparent,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppConstants.darkCardBg
                                : CupertinoColors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.info_circle_fill,
                                    size: 16,
                                    color: isDark
                                        ? CupertinoColors.systemBlue
                                        : AppConstants.accentIndigo,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '需要用户授权以下权限用于程序相关功能',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? CupertinoColors.systemGrey
                                          : CupertinoColors.systemGrey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '点击任意权限可重新发起系统授权请求。\n无授权会导致相关功能不可用。',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? CupertinoColors.systemGrey.withOpacity(0.7)
                                      : CupertinoColors.systemGrey2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._permissions.map((p) => _buildPermissionRow(p, isDark)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionRow(_PermItem item, bool isDark) {
    final isNetwork = item.isNetwork;
    final networkOk = isNetwork && item.networkReachable;
    final granted = networkOk || (!isNetwork && (item.status?.isGranted == true || item.status?.isLimited == true));
    final permanent = !isNetwork && item.status?.isPermanentlyDenied == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.darkCardBg : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isNetwork
                  ? CupertinoColors.systemBlue.withOpacity(0.15)
                  : granted
                      ? AppConstants.successGreen.withOpacity(0.15)
                      : permanent
                          ? AppConstants.errorRed.withOpacity(0.15)
                          : AppConstants.warningOrange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isNetwork
                  ? CupertinoIcons.globe
                  : granted
                      ? CupertinoIcons.checkmark_circle_fill
                      : permanent
                          ? CupertinoIcons.xmark_circle_fill
                          : CupertinoIcons.exclamationmark_circle_fill,
              size: 20,
              color: isNetwork
                  ? CupertinoColors.systemBlue
                  : granted
                      ? AppConstants.successGreen
                      : permanent
                          ? AppConstants.errorRed
                          : AppConstants.warningOrange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          if (item.requesting)
            const CupertinoActivityIndicator()
          else
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () => _requestPermission(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isNetwork
                      ? CupertinoColors.systemBlue.withOpacity(0.12)
                      : granted
                          ? CupertinoColors.systemGreen.withOpacity(0.15)
                          : CupertinoColors.activeBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  isNetwork
                      ? (networkOk ? '已连接' : '无法连接')
                      : granted
                          ? '已授权'
                          : permanent
                              ? '去设置'
                              : '授权',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isNetwork
                        ? CupertinoColors.systemBlue
                        : granted
                            ? CupertinoColors.systemGreen
                            : CupertinoColors.activeBlue,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermItem {
  final Permission? permission;
  final String name;
  final String description;
  final bool isNetwork;
  PermissionStatus? status;
  bool requesting = false;
  bool networkReachable = false;

  _PermItem(this.permission, this.name, this.description) : isNetwork = false;

  _PermItem.network(this.name, this.description)
      : permission = null,
        isNetwork = true;
}

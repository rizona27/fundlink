import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/toast.dart';

/// 检查权限。如果已授权返回 true。
/// 如果被拒绝但可重新请求，弹系统权限请求。
/// 如果被永久拒绝，弹出引导对话框让用户去设置中开启。
/// 返回 true 表示可以继续操作，false 表示缺少权限。
Future<bool> checkPermission({
  required BuildContext context,
  required Permission permission,
  required String featureDescription,
}) async {
  final status = await permission.status;

  if (status.isGranted || status.isLimited) return true;

  if (status.isDenied) {
    // 首次拒绝，可以重新弹出系统请求（仅 iOS 可重复，Android 一次拒绝后不再弹出）
    if (Platform.isIOS) {
      final result = await permission.request();
      if (result.isGranted || result.isLimited) return true;
    } else {
      // Android：拒绝后不再弹，直接提示
      if (context.mounted) {
        context.showToast('需要$featureDescription权限，请在设置中开启');
      }
      return false;
    }
  }

  if (status.isPermanentlyDenied) {
    if (context.mounted) {
      await _showSettingsDialog(context, featureDescription);
    }
    return false;
  }

  return false;
}

Future<void> _showSettingsDialog(BuildContext context, String feature) async {
  final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

  await showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('需要权限'),
      content: Text(
        '此功能需要$feature权限才能使用。\n\n'
        '您之前拒绝了该权限，请在系统设置中手动开启。',
        style: TextStyle(
          fontSize: 14,
          color: isDark ? CupertinoColors.white : CupertinoColors.label,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(ctx);
            openAppSettings();
          },
          child: const Text('打开设置'),
        ),
      ],
    ),
  );
}

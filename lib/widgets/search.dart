import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

/// 封装的搜索组件（增强磨玻璃风格）
class Search extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const Search({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    // 优化磨玻璃背景色：深色模式使用更深更透的底色，浅色模式保持半透白
    final frostedBgColor = isDarkMode
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.75)
        : CupertinoColors.white.withValues(alpha: 0.75);
    // 增强模糊强度
    const blurSigma = 12.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            decoration: BoxDecoration(
              color: frostedBgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDarkMode
                    ? CupertinoColors.white.withValues(alpha: 0.15)
                    : CupertinoColors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
            child: CupertinoSearchTextField(
              controller: controller,
              focusNode: focusNode,
              placeholder: '搜索客户名、客户号、基金代码、基金名称',
              placeholderStyle: TextStyle(
                fontSize: 16,
                color: isDarkMode
                    ? CupertinoColors.white.withValues(alpha: 0.6)
                    : CupertinoColors.systemGrey.withValues(alpha: 0.9),
              ),
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              onChanged: onChanged,
              onSuffixTap: () {
                controller.clear();
                onClear();
                onChanged('');
              },
            ),
          ),
        ),
      ),
    );
  }
}
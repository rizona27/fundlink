import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

/// 封装的搜索组件（磨玻璃风格）
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
    final frostedBgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
        : CupertinoColors.white.withValues(alpha: 0.85);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: frostedBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CupertinoSearchTextField(
              controller: controller,
              focusNode: focusNode,
              placeholder: '搜索客户名、客户号、基金代码、基金名称',
              placeholderStyle: TextStyle(
                fontSize: 16,
                color: isDarkMode
                    ? CupertinoColors.white.withValues(alpha: 0.5)
                    : CupertinoColors.systemGrey.withValues(alpha: 0.8),
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
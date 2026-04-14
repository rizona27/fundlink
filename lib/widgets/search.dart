import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

/// 封装的搜索组件（支持清空）
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? CupertinoColors.systemGrey6 : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: CupertinoSearchTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: '搜索客户名、客户号、基金代码、基金名称',
        placeholderStyle: const TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
        style: const TextStyle(fontSize: 16),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        onChanged: onChanged,
        // 确保清除按钮触发 onClear
        onSuffixTap: () {
          controller.clear();
          onClear();
          onChanged('');
        },
      ),
    );
  }
}
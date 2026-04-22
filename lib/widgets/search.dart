import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class Search extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String? placeholder;

  const Search({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final frostedBgColor = isDarkMode
        ? const Color(0xFF1C1C1E).withOpacity(0.75)
        : CupertinoColors.white.withOpacity(0.75);
    const blurSigma = 12.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            decoration: BoxDecoration(
              color: frostedBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.15)
                    : CupertinoColors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
            child: CupertinoSearchTextField(
              controller: controller,
              focusNode: focusNode,
              placeholder: placeholder ?? '搜索客户名、客户号、基金代码、基金名称',
              placeholderStyle: TextStyle(
                fontSize: 15,
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.6)
                    : CupertinoColors.systemGrey.withOpacity(0.9),
              ),
              style: TextStyle(
                fontSize: 15,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              onChanged: onChanged,
              onSuffixTap: () {
                controller.clear();
                onClear();
                onChanged('');
                focusNode.requestFocus();
              },
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

enum ThemeMode {
  light,
  dark,
  system,
}

extension ThemeModeExtension on ThemeMode {
  String get displayName {
    switch (this) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
}

class ThemeSwitch extends StatefulWidget {
  final ThemeMode initialMode;
  final ValueChanged<ThemeMode> onChanged;

  const ThemeSwitch({
    super.key,
    required this.initialMode,
    required this.onChanged,
  });

  @override
  State<ThemeSwitch> createState() => _ThemeSwitchState();
}

class _ThemeSwitchState extends State<ThemeSwitch> with SingleTickerProviderStateMixin {
  late ThemeMode _selectedMode;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _updateAnimation();
  }

  void _updateAnimation() {
    final targetValue = _getAnimationValue();
    _animationController.animateTo(
      targetValue,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  double _getAnimationValue() {
    switch (_selectedMode) {
      case ThemeMode.light:
        return 0.0;
      case ThemeMode.system:
        return 0.5;
      case ThemeMode.dark:
        return 1.0;
    }
  }

  void _selectMode(ThemeMode mode) {
    if (_selectedMode != mode) {
      setState(() {
        _selectedMode = mode;
      });
      _updateAnimation();
      widget.onChanged(mode);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: 260,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          // 滑动的药丸指示器 - 使用 AnimatedBuilder 实现平滑动画
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final slideValue = _animationController.value;
              final leftOffset = slideValue * 168; // 168 = 总宽度(260) - 药丸宽度(80) - 边距(12)
              return Transform.translate(
                offset: Offset(leftOffset, 0),
                child: Container(
                  width: 80,
                  height: 32,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // 三个选项
          Row(
            children: [
              _buildOption(ThemeMode.light, '浅色'),
              _buildOption(ThemeMode.system, '跟随系统'),
              _buildOption(ThemeMode.dark, '深色'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOption(ThemeMode mode, String label) {
    final isSelected = _selectedMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectMode(mode),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isSelected ? 1.0 : 0.6,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
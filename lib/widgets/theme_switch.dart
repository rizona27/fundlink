import 'package:flutter/cupertino.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        // ✅ 动态计算：根据实际容器宽度计算滑块位置，避免硬编码
        final containerWidth = constraints.maxWidth;
        const sliderWidth = 72.0; // 滑块宽度
        const margin = 2.0; // 左右margin
        
        // 可移动距离 = 容器宽度 - 滑块宽度 - 左右margin
        final maxOffset = containerWidth - sliderWidth - (margin * 2);
        
        return Container(
          height: 36,
          width: 240, 
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey5,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final slideValue = _animationController.value;
                  // ✅ 动态计算偏移量，确保三个位置都能精确对齐
                  final leftOffset = slideValue * maxOffset;
                  return Transform.translate(
                    offset: Offset(leftOffset, 0),
                    child: Container(
                      width: sliderWidth, 
                      height: 32,
                      margin: const EdgeInsets.all(margin),
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
      },
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
                fontSize: 12, 
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
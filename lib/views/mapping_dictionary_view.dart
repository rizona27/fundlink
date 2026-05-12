import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MappingDictionaryView extends StatefulWidget {
  const MappingDictionaryView({super.key});

  @override
  State<MappingDictionaryView> createState() => _MappingDictionaryViewState();
}

class _MappingDictionaryViewState extends State<MappingDictionaryView> {
  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('映射词典'),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.book,
                size: 64,
                color: CupertinoColors.systemGrey,
              ),
              const SizedBox(height: 16),
              Text(
                '映射词典功能开发中',
                style: TextStyle(
                  fontSize: 18,
                  color: CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '映射客户号与客户名',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.systemGrey2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

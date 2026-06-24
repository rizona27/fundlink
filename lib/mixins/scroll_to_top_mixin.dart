import 'package:flutter/cupertino.dart';
import '../widgets/page_scroll_to_top.dart';

mixin ScrollToTopMixin<T extends StatefulWidget> on State<T> {
  ScrollController get scrollController;

  double get showThreshold => 100.0;

  double get rightMargin => 16.0;

  double get bottomMargin => 76.0;

  double Function()? get scrollToPosition => null;

  Widget buildWithScrollToTop(Widget child) {
    return Stack(
      children: [
        child,
        PageScrollToTop(
          scrollController: scrollController,
          showThreshold: showThreshold,
          rightMargin: rightMargin,
          bottomMargin: bottomMargin,
          scrollToPosition: scrollToPosition,
        ),
      ],
    );
  }
}

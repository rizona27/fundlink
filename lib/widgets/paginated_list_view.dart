import 'package:flutter/cupertino.dart';
import '../utils/animation_config.dart';

class PaginationController extends ChangeNotifier {
  int _currentPage = 0;
  int _pageSize = 20;
  bool _isLoading = false;
  bool _hasMore = true;
  int _totalCount = 0;
  
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  int get totalCount => _totalCount;
  int get loadedCount => (_currentPage + 1) * _pageSize;
  
  PaginationController({int pageSize = 20}) : _pageSize = pageSize;
  
  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      _currentPage++;
      
      if (loadedCount >= _totalCount) {
        _hasMore = false;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  void reset({int totalCount = 0}) {
    _currentPage = 0;
    _hasMore = true;
    _totalCount = totalCount;
    _isLoading = false;
    notifyListeners();
  }
  
  void setTotalCount(int count) {
    _totalCount = count;
    _hasMore = loadedCount < count;
    notifyListeners();
  }
  
  Future<void> refresh() async {
    reset();
    await loadNextPage();
  }
}

class PaginatedListView<T> extends StatefulWidget {
  final Future<List<T>> Function(int page, int pageSize) onLoadPage;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final int pageSize;
  final String? emptyMessage;
  final Widget? emptyWidget;
  final bool enablePullRefresh;
  final bool enableLoadMore;
  final VoidCallback? onRefresh;
  
  const PaginatedListView({
    super.key,
    required this.onLoadPage,
    required this.itemBuilder,
    this.pageSize = 20,
    this.emptyMessage,
    this.emptyWidget,
    this.enablePullRefresh = true,
    this.enableLoadMore = true,
    this.onRefresh,
  });
  
  @override
  State<PaginatedListView<T>> createState() => _PaginatedListViewState<T>();
}

class _PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  late PaginationController _controller;
  List<T> _items = [];
  bool _isInitialLoading = true;
  
  @override
  void initState() {
    super.initState();
    _controller = PaginationController(pageSize: widget.pageSize);
    _loadFirstPage();
  }
  
  Future<void> _loadFirstPage() async {
    if (mounted) setState(() {
      _isInitialLoading = true;
    });
    
    try {
      final items = await widget.onLoadPage(0, widget.pageSize);
      if (mounted) setState(() {
        _items = items;
        _isInitialLoading = false;
        _controller.setTotalCount(items.length);
      });
    } catch (e) {
      if (mounted) setState(() {
        _isInitialLoading = false;
      });
    }
  }
  
  Future<void> _onRefresh() async {
    if (widget.onRefresh != null) {
      widget.onRefresh!();
    }
    await _loadFirstPage();
  }
  
  Future<void> _loadMore() async {
    if (!_controller.hasMore || _controller.isLoading) return;
    
    await _controller.loadNextPage();
    
    try {
      final newItems = await widget.onLoadPage(
        _controller.currentPage,
        widget.pageSize,
      );
      
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
        });
      }
    } catch (e) {
      _controller.reset(totalCount: _items.length);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return Center(
        child: CupertinoActivityIndicator(radius: 16),
      );
    }
    
    if (_items.isEmpty) {
      return widget.emptyWidget ?? 
        Center(
          child: Text(
            widget.emptyMessage ?? '暂无数据',
            style: TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 14,
            ),
          ),
        );
    }
    
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!widget.enableLoadMore) return false;
        
        if (notification is ScrollUpdateNotification &&
            notification.metrics.pixels >= 
            notification.metrics.maxScrollExtent - 200) {
          _loadMore();
        }
        return false;
      },
      child: widget.enablePullRefresh
        ? CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              CupertinoSliverRefreshControl(
                onRefresh: _onRefresh,
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _items.length) {
                      if (_controller.hasMore) {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: _controller.isLoading
                              ? CupertinoActivityIndicator(radius: 12)
                              : Text(
                                  '上拉加载更多',
                                  style: TextStyle(
                                    color: CupertinoColors.systemGrey,
                                    fontSize: 12,
                                  ),
                                ),
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              '没有更多了',
                              style: TextStyle(
                                color: CupertinoColors.systemGrey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }
                    }
                    
                    return AnimationConfig.fadeTransition(
                      duration: const Duration(milliseconds: 300),
                      opacity: 1.0,
                      child: widget.itemBuilder(context, _items[index], index),
                    );
                  },
                  childCount: _items.length + (_controller.hasMore ? 1 : 0),
                ),
              ),
            ],
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _items.length + (_controller.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _items.length) {
                if (_controller.hasMore) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: _controller.isLoading
                        ? CupertinoActivityIndicator(radius: 12)
                        : Text(
                            '上拉加载更多',
                            style: TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                            ),
                          ),
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        '没有更多了',
                        style: TextStyle(
                          color: CupertinoColors.systemGrey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }
              }
              
              return AnimationConfig.fadeTransition(
                duration: const Duration(milliseconds: 300),
                opacity: 1.0,
                child: widget.itemBuilder(context, _items[index], index),
              );
            },
          ),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

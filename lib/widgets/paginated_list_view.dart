import 'package:flutter/cupertino.dart';
import '../utils/animation_config.dart';

/// 分页加载控制器
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
  
  /// 加载下一页
  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      await Future.delayed(const Duration(milliseconds: 100)); // 模拟加载
      _currentPage++;
      
      // 检查是否还有更多数据
      if (loadedCount >= _totalCount) {
        _hasMore = false;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// 重置分页
  void reset({int totalCount = 0}) {
    _currentPage = 0;
    _hasMore = true;
    _totalCount = totalCount;
    _isLoading = false;
    notifyListeners();
  }
  
  /// 设置总数量
  void setTotalCount(int count) {
    _totalCount = count;
    _hasMore = loadedCount < count;
    notifyListeners();
  }
  
  /// 刷新
  Future<void> refresh() async {
    reset();
    await loadNextPage();
  }
}

/// 分页列表视图 - 支持下拉刷新和上拉加载更多
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
    if (mounted) setState(() {  // ✅ 添加 mounted 检查
      _isInitialLoading = true;
    });
    
    try {
      final items = await widget.onLoadPage(0, widget.pageSize);
      if (mounted) setState(() {  // ✅ 添加 mounted 检查
        _items = items;
        _isInitialLoading = false;
        _controller.setTotalCount(items.length); // 简化处理，实际应该从后端获取总数
      });
    } catch (e) {
      if (mounted) setState(() {  // ✅ 添加 mounted 检查
        _isInitialLoading = false;
      });
    }
  }
  
  Future<void> _onRefresh() async {
    if (widget.onRefresh != null) {
      widget.onRefresh!();  // ✅ 修复：VoidCallback返回void，不能await
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
      // 加载失败，回滚页码
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
        ? CustomScrollView(  // ✅ 修复：使用 CustomScrollView 而不是 CupertinoScrollView
            physics: const BouncingScrollPhysics(),
            slivers: [  // ✅ 修复：使用 slivers 而不是 children
              CupertinoSliverRefreshControl(
                onRefresh: _onRefresh,
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _items.length) {
                      // 加载更多指示器
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
                      opacity: 1.0,  // ✅ 修复：添加必需的 opacity 参数
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
                // 加载更多指示器
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
                opacity: 1.0,  // ✅ 修复：添加必需的 opacity 参数
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

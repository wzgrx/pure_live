import 'dart:async';

import 'package:dio/dio.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/interface/live_directory.dart';

/// A bounded, per-tab native-page pool. Keeps complete responses (including
/// overflow) and presents independent mobile/desktop page sizes. No other
/// paging implementation changes for platforms without the optional contract.
class LiveDirectoryController extends BasePageScrollAndStateBone<LiveRoom> {
  LiveDirectoryController({
    required this.directory,
    this.category,
    this.transform,
    this.maxBufferedItems = 20000,
    this.maxRequestsPerLoad = 20,
  });
  final LiveSiteDirectoryPager directory;
  final LiveArea? category;
  final List<LiveRoom> Function(List<LiveRoom>)? transform;
  final int maxBufferedItems;
  final int maxRequestsPerLoad;
  final _pool = <LiveRoom>[];
  final _identities = <String>{};
  int _nextNativePage = 1;
  bool _serverHasMore = true;
  bool _capacityReached = false;
  int _epoch = 0;
  int _visiblePage = 1;
  bool _disposed = false;
  Future<void>? _activeLoad;
  Future<void>? _pendingRepage;
  CancelToken? _cancel;

  bool _owns(int epoch) => !_disposed && !isClosed && epoch == _epoch;

  @override
  Future<void> refreshData() async {
    final epoch = ++_epoch;
    _cancel?.cancel();
    await _activeLoad;
    if (!_owns(epoch)) return;
    _pool.clear();
    _identities.clear();
    _nextNativePage = 1;
    _serverHasMore = true;
    _capacityReached = false;
    currentPage = 1;
    _visiblePage = 1;
    await _startLoad(1);
  }

  @override
  Future<void> loadData() => _pendingRepage ?? _activeLoad ?? _startLoad(currentPage);

  @override
  Future<void> loadMoreData() async {
    if (_activeLoad != null || _pendingRepage != null || !canLoadMore.value) return;
    final partialPage = _pool.length < _visiblePage * pageSize.value && _serverHasMore;
    await _startLoad(partialPage ? _visiblePage : _visiblePage + 1);
  }

  @override
  Future<void> goToPage(int page) async {
    if (!usesDesktopPagination || _activeLoad != null || _pendingRepage != null || page < 1) return;
    if (page > _visiblePage && !canLoadMore.value && (page - 1) * pageSize.value >= _pool.length) return;
    await _startLoad(page);
  }

  @override
  void setPageSize(int? newSize) {
    if (newSize == null || newSize < 1 || newSize == pageSize.value || _disposed) return;
    final firstIndex = usesDesktopPagination ? (_visiblePage - 1) * pageSize.value : 0;
    pageSize.value = newSize;
    currentPage = firstIndex ~/ newSize + 1;
    // Coalesce size changes while an old request is in flight; preserve the
    // completed native page pool rather than restarting its network cursor.
    final epoch = ++_epoch;
    _cancel?.cancel();
    late final Future<void> repage;
    repage =
        (() async {
          await _activeLoad;
          if (_owns(epoch)) await _startLoad(currentPage);
        }()).whenComplete(() {
          if (identical(_pendingRepage, repage)) _pendingRepage = null;
        });
    _pendingRepage = repage;
    unawaited(repage);
  }

  Future<void> _startLoad(int targetPage) {
    if (_disposed || isClosed) return Future.value();
    final active = _activeLoad;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performLoad(targetPage, _epoch).whenComplete(() {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    });
    _activeLoad = operation;
    return operation;
  }

  Future<void> _performLoad(int targetPage, int epoch) async {
    if (targetPage < 1 || pageSize.value < 1 || maxRequestsPerLoad < 1 || maxBufferedItems < 1) {
      return;
    }
    final targetSize = pageSize.value;
    final targetEnd = targetPage * targetSize;
    final targetStart = usesDesktopPagination ? (targetPage - 1) * targetSize : 0;
    final token = CancelToken();
    _cancel = token;
    Object? failure;
    try {
      loadding.value = true;
      pageLoadding.value = list.isEmpty;
      pageError.value = false;
      notLogin.value = false;
      errorMsg.value = '';
      var requests = 0;
      while (_pool.length < targetEnd && _serverHasMore && !_capacityReached && requests < maxRequestsPerLoad) {
        final networkReady = await checkNetworkBeforeRequest();
        if (!_owns(epoch)) return;
        if (!networkReady) {
          finishRefreshControllers(IndicatorResult.fail);
          return;
        }
        final expectedPage = _nextNativePage;
        late final LiveDirectoryPage response;
        try {
          response = await directory.getDirectoryPage(page: expectedPage, category: category, cancel: token);
        } catch (error) {
          if (!_owns(epoch)) return;
          failure = error;
          break;
        }
        if (!_owns(epoch)) return;
        if (response.page != expectedPage || response.rooms.length > 1000) {
          failure = StateError('Directory pagination mismatch');
          break;
        }
        var rows = response.rooms.toList();
        if (category != null) rows = rows.map((room) => room.copyWith(area: category!.areaName)).toList();
        if (transform != null) rows = transform!(rows);
        final fresh = <LiveRoom>[];
        final pageIdentities = <String>{};
        for (final room in rows) {
          if (!_identities.contains(room.identityKey) && pageIdentities.add(room.identityKey)) fresh.add(room);
        }
        // Never partially consume a native page and then advance past the
        // discarded remainder. A capacity failure keeps that page uncommitted.
        if (_pool.length + fresh.length > maxBufferedItems) {
          _capacityReached = true;
          failure = i18n('directory_cache_limit');
          break;
        }
        _pool.addAll(fresh);
        _identities.addAll(pageIdentities);
        _nextNativePage++;
        _serverHasMore = response.hasMore;
        requests++;
      }
      if (!_owns(epoch)) return;
      if (_pool.length < targetEnd && _serverHasMore && !_capacityReached && failure == null) {
        failure = i18n('directory_continue_loading');
      }
      // Errors and request budgets are retryable, not a fabricated end of the
      // list. Already committed cards remain available, including overflow.
      if (targetStart < _pool.length || (_pool.isEmpty && targetPage == 1 && !_serverHasMore)) {
        final end = targetEnd.clamp(0, _pool.length);
        list.assignAll(_pool.sublist(targetStart, end));
        _visiblePage = targetPage;
        currentPage = targetPage;
        if (usesDesktopPagination) scrollToTopImmediate();
      } else {
        currentPage = _visiblePage;
      }
      final visibleEnd = _visiblePage * targetSize;
      canLoadMore.value = visibleEnd < _pool.length || (_serverHasMore && !_capacityReached);
      totalCount.value = !_serverHasMore ? _pool.length : null;
      pageEmpty.value = list.isEmpty && !_serverHasMore && failure == null;
      if (failure != null) {
        // Keep the visible list mounted; BasePageView renders a full-page error
        // only when there are no usable cards. Retry resumes the failed page.
        handleError(failure, showPageError: list.isEmpty);
        finishRefreshControllers(IndicatorResult.fail);
      } else {
        finishRefreshControllers(canLoadMore.value ? IndicatorResult.success : IndicatorResult.noMore);
      }
    } catch (error) {
      if (_owns(epoch)) {
        currentPage = _visiblePage;
        handleError(error, showPageError: list.isEmpty);
        finishRefreshControllers(IndicatorResult.fail);
      }
    } finally {
      if (identical(_cancel, token)) _cancel = null;
      if (_owns(epoch)) {
        loadding.value = false;
        pageLoadding.value = false;
      }
    }
  }

  @override
  void onClose() {
    _disposed = true;
    _epoch++;
    _cancel?.cancel();
    _cancel = null;
    _pool.clear();
    _identities.clear();
    super.onClose();
  }
}

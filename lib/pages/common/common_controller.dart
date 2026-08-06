import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:winwin/http/loading_state.dart';

mixin ScrollOrRefreshMixin {
  ScrollController get scrollController;

  Future<void> onRefresh();

  DateTime? _lastTopOrRefresh;

  /// Scroll back to the top. Falls back to a jump when the distance is
  /// too far for a smooth animation.
  void animateToTop() {
    if (!scrollController.hasClients) return;
    if (scrollController.offset.abs() >=
        scrollController.position.viewportDimension * 7) {
      scrollController.jumpTo(0);
    } else {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  /// If already at the top, trigger a refresh (throttled);
  /// otherwise scroll back to the top.
  void toTopOrRefresh() {
    if (scrollController.hasClients) {
      if (scrollController.position.pixels == 0) {
        final now = DateTime.now();
        if (_lastTopOrRefresh != null &&
            now.difference(_lastTopOrRefresh!) <
                const Duration(milliseconds: 500)) {
          return;
        }
        _lastTopOrRefresh = now;
        onRefresh();
      } else {
        animateToTop();
      }
    }
  }
}

abstract class CommonController<R, T> extends GetxController
    with ScrollOrRefreshMixin {
  @override
  final ScrollController scrollController = ScrollController();

  bool isLoading = false;

  Rx<LoadingState> get loadingState;

  Future<LoadingState<R>> customGetData();

  Future<void> queryData([bool isRefresh = true]);

  /// Return true to take over response handling.
  bool customHandleResponse(bool isRefresh, Success<R> response) => false;

  /// Return true to take over error handling.
  bool handleError(String? errMsg) => false;

  @override
  Future<void> onRefresh() => queryData();

  Future<void> onLoadMore() => queryData(false);

  Future<void> onReload() => onRefresh();

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}

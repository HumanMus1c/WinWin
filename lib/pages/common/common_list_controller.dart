import 'package:get/get.dart';

import 'package:winwin/http/dio_error_message.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/common/common_controller.dart';

abstract class CommonListController<R, T> extends CommonController<R, T> {
  int page = 1;
  bool isEnd = false;

  @override
  Rx<LoadingState<List<T>?>> loadingState =
      LoadingState<List<T>?>.loading().obs;

  /// Hook for subclasses to preprocess the incoming list
  /// (e.g. merging previously saved data) before it is committed.
  void handleListResponse(List dataList) {}

  List<T>? getDataList(R response) => response as List<T>?;

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    if (isLoading || (!isRefresh && isEnd)) return;
    isLoading = true;
    LoadingState<R> res;
    try {
      res = await customGetData();
    } catch (e) {
      // Never let a thrown exception strand the UI in Loading state.
      // 友好文案（复盘第十轮）：避免把 Dio 原文（如 "DioException [receive timeout]…"）
      // 直接显示给用户。
      res = Error(dioErrorMessage(e));
    }
    if (res case Success(:final response)) {
      if (!customHandleResponse(isRefresh, res)) {
        final dataList = getDataList(response);
        if (dataList == null || dataList.isEmpty) {
          isEnd = true;
          if (isRefresh) {
            loadingState.value = Success(dataList);
          } else {
            loadingState.refresh();
          }
          isLoading = false;
          return;
        }
        handleListResponse(dataList);
        if (isRefresh) {
          loadingState.value = Success(dataList);
        } else if (loadingState.value case Success(:final response)) {
          response!.addAll(dataList);
          loadingState.refresh();
        }
      }
      page++;
    } else {
      if (isRefresh && !handleError(res is Error ? res.errMsg : null)) {
        loadingState.value = res as Error;
      }
    }
    isLoading = false;
  }

  @override
  Future<void> onRefresh() {
    page = 1;
    isEnd = false;
    return super.onRefresh();
  }

  @override
  Future<void> onReload() {
    loadingState.value = LoadingState<List<T>?>.loading();
    return super.onReload();
  }
}

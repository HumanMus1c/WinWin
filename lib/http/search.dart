import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/search/result.dart';
import 'package:winwin/models/search/search_type.dart';
import 'package:winwin/models/search/suggest.dart';
import 'package:winwin/utils/wbi_sign.dart';

/// 搜索 HTTP 请求封装。
///
/// 移植自 PiliPlus 的 `SearchHttp`，精简风控处理和泛型设计，
/// 保留核心的 searchByType / searchSuggest / searchTrending 方法。
abstract final class SearchHttp {
  /// 搜索建议（联想）。
  static Future<LoadingState<SearchSuggestModel>> searchSuggest({
    required String term,
  }) async {
    final res = await Request().get(
      Api.searchSuggest,
      queryParameters: {
        'term': term,
        'main_ver': 'v1',
        'highlight': term,
      },
    );
    if (res.data is String) {
      final Map<String, dynamic> resultMap = json.decode(res.data);
      if (resultMap['code'] == 0 && resultMap['result'] is Map) {
        return Success(SearchSuggestModel.fromJson(resultMap['result']));
      }
    }
    return const Error(null);
  }

  /// 分类搜索（核心）。
  ///
  /// [searchType] 指定搜索分类，[keyword] 为关键词，[page] 从 1 开始。
  static Future<LoadingState<SearchNumData>> searchByType({
    required SearchType searchType,
    required String keyword,
    required int page,
    int pageSize = 20,
  }) async {
    final params = await WbiSign.makSign({
      'search_type': searchType.name,
      'keyword': keyword,
      'page': page,
      'page_size': pageSize,
      'platform': 'pc',
      'web_location': 1430654,
    });
    final res = await Request().get(
      Api.searchByType,
      queryParameters: params,
      options: Options(
        headers: {
          'origin': 'https://search.bilibili.com',
          'referer':
              'https://search.bilibili.com/${searchType.name}?keyword=${Uri.encodeFull(keyword)}',
        },
      ),
    );
    final resData = res.data;
    if (resData is Map) {
      if (resData['code'] == 0) {
        final dataData = resData['data'];
        if (dataData == null) {
          return const Error('没有相关数据');
        }
        try {
          final SearchNumData data;
          switch (searchType) {
            case SearchType.video:
              data = SearchVideoData.fromJson(dataData);
            case SearchType.liveRoom:
              data = SearchLiveData.fromJson(dataData);
            case SearchType.biliUser:
              data = SearchUserData.fromJson(dataData);
            case SearchType.mediaBangumi:
            case SearchType.mediaFt:
              data = SearchPgcData.fromJson(dataData);
            case SearchType.article:
              data = SearchArticleData.fromJson(dataData);
          }
          return Success(data);
        } catch (e, s) {
          return Error('$e\n\n$s');
        }
      } else {
        return Error(resData['message'], code: resData['code']);
      }
    }
    return const Error('服务器错误');
  }

  /// 热搜榜。
  static Future<LoadingState<SearchTrendingData>> searchTrending({
    int limit = 30,
  }) async {
    final res = await Request().get(
      Api.searchTrending,
      queryParameters: {'limit': limit},
    );
    if (res.data is Map && res.data['code'] == 0) {
      return Success(SearchTrendingData.fromJson(res.data['data']));
    }
    return Error(res.data is Map ? res.data['message'] : '获取热搜失败');
  }

  /// 默认搜索词（搜索框占位）。
  static Future<LoadingState<String>> searchDefault() async {
    final params = await WbiSign.makSign({});
    final res = await Request().get(
      Api.searchDefault,
      queryParameters: params,
    );
    if (res.data is Map && res.data['code'] == 0) {
      return Success(res.data['data']?['value'] as String? ?? '');
    }
    return const Error(null);
  }
}

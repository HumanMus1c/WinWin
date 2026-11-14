import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/core/player/sponsorblock_usecase.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(String body, int statusCode) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('SponsorBlockCategory 社区映射', () {
    test('wireName 与 fromString 往返', () {
      for (final category in SponsorBlockCategory.values) {
        if (category == SponsorBlockCategory.unknown) continue;
        expect(
          SponsorBlockCategory.fromString(category.wireName),
          category,
        );
      }
      expect(SponsorBlockCategory.fromString('selfpromo'),
          SponsorBlockCategory.selfPromo);
      expect(SponsorBlockCategory.fromString('music_offtopic'),
          SponsorBlockCategory.musicOfftopic);
    });
  });

  group('SponsorBlockUseCase 社区上报', () {
    late Dio dio;
    late _FakeAdapter adapter;
    late SponsorBlockUseCase useCase;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://www.bsbsb.top'))
        ..options.validateStatus = (_) => true;
      adapter = _FakeAdapter((_) async => _jsonResponse('[]', 200));
      dio.httpClientAdapter = adapter;
      useCase = SponsorBlockUseCase(dio: dio);
    });

    tearDown(() => useCase.dispose());

    test('提交请求包含视频、时间段、类别与动作', () async {
      final result = await useCase.submitSegment(
        bvid: 'BV1xx411c7mD',
        cid: 123456,
        videoDurationSeconds: 300,
        startSeconds: 10,
        endSeconds: 25,
        category: 'sponsor',
        actionType: 'skip',
        userId: 'user123456789012345678901234567890',
      );

      expect(result.isSuccess, isTrue);
      final request = adapter.lastRequest!;
      expect(request.path, '/api/skipSegments');
      expect(request.method, 'POST');
      expect(request.data['videoID'], 'BV1xx411c7mD');
      expect(request.data['cid'], '123456');
      expect(request.data['videoDuration'], 300);
      expect(request.data['segments'], [
        {
          'segment': [10.0, 25.0],
          'category': 'sponsor',
          'actionType': 'skip',
        },
      ]);
    });

    test('无效时间段与空用户 ID 在本地被拒绝', () async {
      final invalidRange = await useCase.submitSegment(
        bvid: 'BV1xx411c7mD',
        cid: 1,
        videoDurationSeconds: 300,
        startSeconds: 30,
        endSeconds: 30,
        category: 'sponsor',
        actionType: 'skip',
        userId: 'user123456789012345678901234567890',
      );
      expect(invalidRange.isSuccess, isFalse);
      expect(invalidRange.error, contains('时间范围'));

      final emptyUser = await useCase.submitSegment(
        bvid: 'BV1xx411c7mD',
        cid: 1,
        videoDurationSeconds: 300,
        startSeconds: 1,
        endSeconds: 2,
        category: 'sponsor',
        actionType: 'skip',
        userId: '',
      );
      expect(emptyUser.isSuccess, isFalse);
      expect(emptyUser.error, contains('用户 ID'));
    });

    test('409 映射为重复提交', () async {
      adapter = _FakeAdapter((_) async => _jsonResponse('', 409));
      dio.httpClientAdapter = adapter;

      final result = await useCase.submitSegment(
        bvid: 'BV1xx411c7mD',
        cid: 1,
        videoDurationSeconds: 300,
        startSeconds: 1,
        endSeconds: 2,
        category: 'sponsor',
        actionType: 'skip',
        userId: 'user123456789012345678901234567890',
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('重复提交'));
    });

    test('投票请求路径与类型', () async {
      final error = await useCase.voteSegment(
        uuid: 'segment-uuid',
        type: 1,
        userId: 'user123456789012345678901234567890',
      );
      expect(error, isNull);
      final request = adapter.lastRequest!;
      expect(request.path, '/api/voteOnSponsorTime');
      expect(request.data['UUID'], 'segment-uuid');
      expect(request.data['type'], 1);
    });
  });
}

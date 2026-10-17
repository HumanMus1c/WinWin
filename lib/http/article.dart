import 'package:dio/dio.dart';

import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/response_map.dart';
import 'package:winwin/utils/wbi_sign.dart';

/// 专栏 HTTP 请求接口。
abstract final class ArticleHttp {
  /// 获取专栏文章详情（`/x/article/view`）。
  static Future<LoadingState<ArticleDetailModel>> articleView({
    required dynamic cvId,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.articleView,
        queryParameters: await WbiSign.makSign({
          'id': cvId,
          'gaia_source': 'main_web',
          'web_location': '333.976',
        }),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0 && data['data'] != null) {
        return Success(
          ArticleDetailModel.fromJson(data['data'] as Map<String, dynamic>),
        );
      }
      return Error(data['message']?.toString() ?? '获取专栏内容失败');
    } on DioException catch (e) {
      return Error('获取专栏内容失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取专栏内容失败：$e');
    }
  }
}

/// 专栏文章详情模型。
class ArticleDetailModel {
  final int? id;
  final String? title;
  final String? authorName;
  final String? authorFace;
  final int? authorMid;
  final int? pubTime;
  final String? bannerUrl;
  final List<String> imageUrls;
  final List<ArticleParagraph> paragraphs;
  final int? viewCount;
  final int? likeCount;
  final int? replyCount;

  ArticleDetailModel({
    this.id,
    this.title,
    this.authorName,
    this.authorFace,
    this.authorMid,
    this.pubTime,
    this.bannerUrl,
    this.imageUrls = const [],
    this.paragraphs = const [],
    this.viewCount,
    this.likeCount,
    this.replyCount,
  });

  factory ArticleDetailModel.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    final stats = json['stats'] as Map<String, dynamic>?;
    final rawImages = json['origin_image_urls'] as List?;
    final images = rawImages?.map((e) => e.toString()).toList() ?? <String>[];

    final paragraphs = <ArticleParagraph>[];

    // 1. 若含有 opus.content.paragraphs 结构（新版 Opus 富文本排版）
    final opusParagraphs =
        json['opus']?['content']?['paragraphs'] as List?;
    if (opusParagraphs != null && opusParagraphs.isNotEmpty) {
      for (final p in opusParagraphs) {
        if (p is Map<String, dynamic>) {
          final paraType = _asInt(p['para_type']);
          if (paraType == 2) {
            // 图片段落
            final pics = p['pic']?['pics'] as List?;
            if (pics != null) {
              for (final pic in pics) {
                final url = pic['url']?.toString();
                if (url != null && url.isNotEmpty) {
                  paragraphs.add(
                    ArticleParagraph(
                      type: ArticleParagraphType.image,
                      imageUrl: url,
                    ),
                  );
                  if (!images.contains(url)) images.add(url);
                }
              }
            }
          } else {
            // 文字/标题段落
            final textObj = p['text'];
            String? text;
            if (textObj is Map) {
              final nodes = textObj['nodes'] as List?;
              if (nodes != null) {
                text = nodes
                    .map((n) => n is Map ? (n['word']?['words'] ?? n['text'] ?? '') : '')
                    .join();
              }
            } else if (textObj is String) {
              text = textObj;
            }
            if (text != null && text.trim().isNotEmpty) {
              paragraphs.add(
                ArticleParagraph(
                  type: paraType == 3
                      ? ArticleParagraphType.header
                      : ArticleParagraphType.text,
                  text: text.trim(),
                ),
              );
            }
          }
        }
      }
    }

    // 2. 若 opus 没有段落，解析 HTML 正文 content
    if (paragraphs.isEmpty && json['content'] is String) {
      final html = json['content'] as String;
      // 提取所有段落与插图
      final pRegex = RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true);
      final imgRegex = RegExp(r'<img[^>]+(?:data-src|src)="([^"]+)"', caseSensitive: false);

      final matches = pRegex.allMatches(html);
      for (final m in matches) {
        final inner = m.group(1) ?? '';
        final imgMatch = imgRegex.firstMatch(inner);
        if (imgMatch != null) {
          final imgUrl = imgMatch.group(1)!;
          paragraphs.add(
            ArticleParagraph(
              type: ArticleParagraphType.image,
              imageUrl: imgUrl,
            ),
          );
          if (!images.contains(imgUrl)) images.add(imgUrl);
        } else {
          // 清除 HTML 标签得到纯文本
          final cleanText = inner
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll('&nbsp;', ' ')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&amp;', '&')
              .trim();
          if (cleanText.isNotEmpty) {
            paragraphs.add(
              ArticleParagraph(
                type: ArticleParagraphType.text,
                text: cleanText,
              ),
            );
          }
        }
      }
    }

    return ArticleDetailModel(
      id: _asInt(json['id']),
      title: json['title']?.toString(),
      authorName: author?['name']?.toString() ?? json['author_name']?.toString(),
      authorFace: author?['face']?.toString() ?? json['author_face']?.toString(),
      authorMid: _asInt(author?['mid'] ?? json['mid']),
      pubTime: _asInt(json['publish_time'] ?? json['ctime']),
      bannerUrl: json['banner_url']?.toString(),
      imageUrls: images,
      paragraphs: paragraphs,
      viewCount: _asInt(stats?['view']),
      likeCount: _asInt(stats?['like']),
      replyCount: _asInt(stats?['reply']),
    );
  }
}

enum ArticleParagraphType {
  text,
  header,
  image,
}

class ArticleParagraph {
  final ArticleParagraphType type;
  final String? text;
  final String? imageUrl;

  ArticleParagraph({
    required this.type,
    this.text,
    this.imageUrl,
  });
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

/// 官方表情包 / 表情条目模型（`/x/emote/user/panel/web`、`/x/emote/package`）。
///
/// 字段对齐 bilibili-API-collect 定义与参考实现（PiliPlus models_new/emote）：
/// 包 type：1=普通 2=会员专属 3=购买所得 4=颜文字；表情 meta.size：1=小 2=大。
class EmotePackage {
  final int id;
  final String text;
  final String url;
  final int type;
  final List<EmoteInfo> emote;

  const EmotePackage({
    this.id = 0,
    this.text = '',
    this.url = '',
    this.type = 1,
    this.emote = const [],
  });

  factory EmotePackage.fromJson(Map<String, dynamic> json) => EmotePackage(
    id: _asInt(json['id']) ?? 0,
    text: json['text']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    type: _asInt(json['type']) ?? 1,
    emote:
        (json['emote'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((e) => EmoteInfo.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false) ??
        const [],
  );
}

class EmoteInfo {
  final String text;
  final String url;
  final int type;
  final int size;
  final String? alias;

  const EmoteInfo({
    this.text = '',
    this.url = '',
    this.type = 1,
    this.size = 1,
    this.alias,
  });

  factory EmoteInfo.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'];
    return EmoteInfo(
      text: json['text']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: _asInt(json['type']) ?? 1,
      size: _asInt(meta is Map ? meta['size'] : null) ?? 1,
      alias: meta is Map ? meta['alias']?.toString() : null,
    );
  }

  /// 颜文字：`text` 即输入内容，无图片。
  bool get isText => type == 4;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

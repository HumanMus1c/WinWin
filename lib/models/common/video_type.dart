import 'package:winwin/http/api.dart';

/// 视频业务类型（对标 PiliPlus VideoType）。
///
/// 用于区分普通视频（UGC）、番剧/影视（PGC）与课堂（PUGV），
/// 确保心跳进度上报（heartBeat）与解析接口下发正确的目标参数。
enum VideoType {
  /// 普通视频（UGC）
  ugc(
    type: 3,
    api: Api.ugcUrl,
  ),

  /// 番剧 / 影视（PGC）
  pgc(
    type: 4,
    api: Api.pgcUrl,
  ),

  /// 课堂视频（PUGV）
  pugv(
    type: 10,
    replyType: 33,
    api: Api.pugvUrl,
  ),
  ;

  final int type;
  final String api;
  final int replyType;

  const VideoType({
    required this.api,
    required this.type,
    this.replyType = 1,
  });
}

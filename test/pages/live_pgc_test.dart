import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/image/image_gallery_viewer.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/live.dart';
import 'package:winwin/tcp/live.dart';
import 'package:winwin/utils/bilibili_url_parser.dart';
import 'package:winwin/utils/image_utils.dart';

void main() {
  group('LiveItemModel Tests', () {
    test('parses getRoomList payload correctly with isLiving defaulting to true', () {
      final json = <String, dynamic>{
        'roomid': 7734200,
        'uid': 50329118,
        'title': '【直播】英雄联盟赛事',
        'uname': '赛事官方',
        'online': 64967224,
        'user_cover': 'http://i0.hdslb.com/bfs/live/test_cover.jpg',
        'cover': '',
        'face': 'http://i2.hdslb.com/bfs/face/test_face.jpg',
        'area_name': '游戏赛事',
      };

      final item = LiveItemModel.fromJson(json);

      expect(item.roomId, 7734200);
      expect(item.uid, 50329118);
      expect(item.title, '【直播】英雄联盟赛事');
      expect(item.uname, '赛事官方');
      expect(item.online, 64967224);
      expect(item.cover, 'https://i0.hdslb.com/bfs/live/test_cover.jpg');
      expect(item.face, 'https://i2.hdslb.com/bfs/face/test_face.jpg');
      expect(item.areaName, '游戏赛事');
      expect(item.isLiving, isTrue);
    });

    test('respects explicit live_status if present', () {
      final livingJson = <String, dynamic>{'roomid': 101, 'live_status': 1};
      final offlineJson = <String, dynamic>{'roomid': 102, 'live_status': 0};

      expect(LiveItemModel.fromJson(livingJson).isLiving, isTrue);
      expect(LiveItemModel.fromJson(offlineJson).isLiving, isFalse);
    });

    test('parses followed live stream with room_cover correctly', () {
      final json = <String, dynamic>{
        'roomid': 88888,
        'uid': 123456,
        'title': '正在直播中',
        'uname': '关注主播',
        'room_cover': 'http://i0.hdslb.com/bfs/live/follow_cover.jpg',
        'watched_show': {
          'num': 15000,
          'text_small': '1.5万',
        },
        'area_name': '单机游戏',
        'live_status': 1,
      };

      final item = LiveItemModel.fromJson(json);
      expect(item.roomId, 88888);
      expect(item.uid, 123456);
      expect(item.title, '正在直播中');
      expect(item.cover, 'https://i0.hdslb.com/bfs/live/follow_cover.jpg');
      expect(item.online, 15000);
      expect(item.areaName, '单机游戏');
      expect(item.isLiving, isTrue);
    });
  });

  group('LiveAreaItem & LiveFollowData Tests', () {
    test('defaultAreas provides core live parent areas', () {
      expect(LiveAreaItem.defaultAreas.isNotEmpty, isTrue);
      final names = LiveAreaItem.defaultAreas.map((e) => e.name).toList();
      expect(names.contains('网游'), isTrue);
      expect(names.contains('手游'), isTrue);
      expect(names.contains('单机游戏'), isTrue);
      expect(names.contains('娱乐'), isTrue);
      expect(names.contains('虚拟主播'), isTrue);
    });

    test('LiveAreaItem parses api payload with children correctly', () {
      final json = <String, dynamic>{
        'id': 2,
        'name': '网游',
        'list': [
          {'id': 86, 'name': '英雄联盟'},
          {'id': 329, 'name': '无畏契约'},
        ],
      };
      final item = LiveAreaItem.fromJson(json);
      expect(item.id, 2);
      expect(item.name, '网游');
      expect(item.children.length, 2);
      expect(item.children[0].name, '英雄联盟');
      expect(item.children[1].name, '无畏契约');
    });

    test('LiveFollowData filters living items only', () {
      final json = <String, dynamic>{
        'live_count': 1,
        'count': 2,
        'list': [
          {
            'roomid': 1001,
            'title': '直播中主播',
            'live_status': 1,
            'uname': '主播A',
          },
          {
            'roomid': 1002,
            'title': '未开播主播',
            'live_status': 0,
            'uname': '主播B',
          },
        ],
      };
      final followData = LiveFollowData.fromJson(json);
      expect(followData.liveCount, 1);
      expect(followData.count, 2);
      expect(followData.list.length, 1);
      expect(followData.list.first.roomId, 1001);
      expect(followData.list.first.uname, '主播A');
    });
  });

  group('Live Room Extended Tests', () {
    test('LiveRoomInitData parses realRoomId and liveStatus correctly', () {
      final json = <String, dynamic>{
        'room_id': 7734200,
        'short_id': 6,
        'uid': 50329118,
        'live_status': 1,
        'live_time': 1788762159,
        'is_portrait': false,
      };

      final initData = LiveRoomInitData.fromJson(json);
      expect(initData.roomId, 7734200);
      expect(initData.shortId, 6);
      expect(initData.uid, 50329118);
      expect(initData.liveStatus, 1);
      expect(initData.isLiving, isTrue);
      expect(initData.liveTime, 1788762159);
    });

    test('LiveRoomInfo parses full H5 payload with anchor_info and watched_show', () {
      final json = <String, dynamic>{
        'room_info': {
          'room_id': 7734200,
          'short_id': 6,
          'uid': 50329118,
          'title': '英雄联盟赛事',
          'cover': 'http://i0.hdslb.com/bfs/live/cover.jpg',
          'area_name': '游戏赛事',
          'live_status': 1,
          'live_start_time': 1788762159,
        },
        'anchor_info': {
          'base_info': {
            'uname': '哔哩哔哩英雄联盟赛事',
            'face': 'http://i2.hdslb.com/bfs/face/face.jpg',
          },
        },
        'watched_show': {
          'num': 36490000,
          'text_large': '3649万人气',
        },
      };

      final info = LiveRoomInfo.fromJson(json);
      expect(info.roomId, 7734200);
      expect(info.shortId, 6);
      expect(info.uid, 50329118);
      expect(info.title, '英雄联盟赛事');
      expect(info.cover, 'https://i0.hdslb.com/bfs/live/cover.jpg');
      expect(info.uname, '哔哩哔哩英雄联盟赛事');
      expect(info.face, 'https://i2.hdslb.com/bfs/face/face.jpg');
      expect(info.areaName, '游戏赛事');
      expect(info.liveStatus, 1);
      expect(info.isLiving, isTrue);
      expect(info.online, 36490000);
      expect(info.watchedShowText, '3649万人气');
    });

    test('LiveDanmakuMessage.fromPrefetch extracts user and text correctly', () {
      final prefetchItem = <String, dynamic>{
        'text': '主播太强了！666',
        'user': {
          'uid': 12345678,
          'base': {
            'name': '热心观众',
            'face': 'http://i0.hdslb.com/bfs/face/u.jpg',
          },
        },
      };

      final msg = LiveDanmakuMessage.fromPrefetch(prefetchItem);
      expect(msg.isDanmaku, isTrue);
      expect(msg.senderName, '热心观众');
      expect(msg.danmakuText, '主播太强了！666');
    });

    test('ImageGalleryViewer.getRawUrl strips thumbnail query suffixes', () {
      const cdnUrl = 'http://i0.hdslb.com/bfs/album/test.jpg@518w_1e_1c.webp';
      expect(
        ImageGalleryViewer.getRawUrl(cdnUrl),
        'https://i0.hdslb.com/bfs/album/test.jpg',
      );
    });

    test('BilibiliUrlParser parses various live URL formats correctly', () {
      expect(
        BilibiliUrlParser.parse('https://live.bilibili.com/7734200').roomId,
        7734200,
      );
      expect(
        BilibiliUrlParser.parse('https://live.bilibili.com/h5/7734200?broadcast_type=0').roomId,
        7734200,
      );
      expect(
        BilibiliUrlParser.parse('https://live.bilibili.com/blanc/6').roomId,
        6,
      );
      expect(
        BilibiliUrlParser.parse('http://live.bilibili.com/21452505').roomId,
        21452505,
      );
    });

    test('DynLive.fromMajor extracts real room_id from jump_url and injects author info', () {
      final major = {
        'type': 'MAJOR_TYPE_LIVE_RCMD',
        'live_rcmd': {
          'content': jsonEncode({
            'live_play_info': {
              'room_id': 7734200,
              'room_type': 1,
              'title': '【直播】全球总决赛',
              'cover': 'http://i0.hdslb.com/bfs/live/cover.jpg',
              'live_status': 1,
              'watched_show': {'text_large': '100万人气'},
            }
          })
        }
      };

      final dynLiveFromRcmd = DynLive.fromMajor(major);
      expect(dynLiveFromRcmd, isNotNull);
      expect(dynLiveFromRcmd!.roomId, 7734200);
      expect(dynLiveFromRcmd.liveStatus, 1);
      expect(dynLiveFromRcmd.title, '【直播】全球总决赛');

      final majorLive = {
        'type': 'MAJOR_TYPE_LIVE',
        'live': {
          'id': '100099882233', // 场次ID，非房间号
          'title': '日常直播中',
          'jump_url': 'https://live.bilibili.com/21452505',
          'badge': {'text': '直播中'},
        }
      };
      final author = DynAuthor(
        mid: 123456,
        name: '测试UP主',
        face: 'http://i0.hdslb.com/bfs/face/up.jpg',
      );

      final dynLive = DynLive.fromMajor(majorLive, author: author);
      expect(dynLive, isNotNull);
      expect(dynLive!.roomId, 21452505); // 成功解析出真实房间号
      expect(dynLive.uname, '测试UP主');
      expect(dynLive.cover, 'http://i0.hdslb.com/bfs/face/up.jpg');
      expect(dynLive.badge, '直播中');
      expect(dynLive.isLiving, isTrue);
    });

    test('LiveDanmakuTokenData & LiveDanmakuHost parse correctly', () {
      final json = {
        'token': 'test_token_123456',
        'host_list': [
          {'host': 'zj-cn-live-comet.chat.bilibili.com', 'port': 2243, 'wss_port': 2245, 'ws_port': 2244},
          {'host': 'broadcastlv.chat.bilibili.com', 'port': 2243, 'wss_port': 443, 'ws_port': 80},
        ],
      };
      final data = LiveDanmakuTokenData.fromJson(json);
      expect(data.token, 'test_token_123456');
      expect(data.hostList.length, 2);
      expect(data.hostList[0].host, 'zj-cn-live-comet.chat.bilibili.com');
      expect(data.hostList[0].wssPort, 2245);
      expect(data.hostList[1].wssPort, 443);
    });

    test('LivePlayUrlData.allPlayUrls extracts all candidate streams across FLV and HLS', () {
      final json = {
        'room_id': 7734200,
        'live_status': 1,
        'playurl_info': {
          'playurl': {
            'stream': [
              {
                'protocol_name': 'http_stream',
                'format': [
                  {
                    'format_name': 'flv',
                    'codec': [
                      {
                        'codec_name': 'avc',
                        'base_url': '/live/stream_flv.flv',
                        'url_info': [
                          {'host': 'https://flv1.bilivideo.com', 'extra': '?token=1'},
                          {'host': 'https://flv2.bilivideo.com', 'extra': '?token=2'},
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                'protocol_name': 'http_hls',
                'format': [
                  {
                    'format_name': 'fmp4',
                    'codec': [
                      {
                        'codec_name': 'avc',
                        'base_url': '/live/stream_hls.m3u8',
                        'url_info': [
                          {'host': 'https://hls1.bilivideo.com', 'extra': '?token=3'},
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
      };

      final playData = LivePlayUrlData.fromJson(json);
      expect(playData.isLiving, isTrue);
      expect(playData.bestPlayUrl, 'https://flv1.bilivideo.com/live/stream_flv.flv?token=1');
      final allUrls = playData.allPlayUrls;
      expect(allUrls.length, 3);
      expect(allUrls[0], 'https://flv1.bilivideo.com/live/stream_flv.flv?token=1');
      expect(allUrls[1], 'https://flv2.bilivideo.com/live/stream_flv.flv?token=2');
      expect(allUrls[2], 'https://hls1.bilivideo.com/live/stream_hls.m3u8?token=3');

      // Test streamLines and quality
      expect(playData.streamLines.length, 3);
      expect(playData.streamLines[0].title, contains('FLV 线路 1'));
      expect(playData.streamLines[2].title, contains('HLS 线路 1'));
    });

    test('LiveQuality and LiveRoomInfo app_background parse correctly', () {
      expect(LiveQuality.descFromCode(10000), '原画');
      expect(LiveQuality.descFromCode(400), '蓝光');
      expect(LiveQuality.descFromCode(250), '超清');
      expect(LiveQuality.descFromCode(150), '高清');
      expect(LiveQuality.descFromCode(80), '流畅');
      expect(LiveQuality.descFromCode(null), '自动');

      final h5Json = {
        'room_info': {
          'room_id': 7734200,
          'title': '2026 LPL',
          'cover': 'http://i0.hdslb.com/cover.jpg',
          'app_background': 'http://i0.hdslb.com/bg.jpg',
          'background': 'http://i0.hdslb.com/web_bg.jpg',
          'keyframe': 'http://i0.hdslb.com/keyframe.jpg',
          'live_start_time': 1788762159,
          'live_status': 1,
        }
      };
      final info = LiveRoomInfo.fromJson(h5Json);
      expect(info.appBackground, 'https://i0.hdslb.com/bg.jpg');
      expect(info.background, 'https://i0.hdslb.com/web_bg.jpg');
      expect(info.keyframe, 'https://i0.hdslb.com/keyframe.jpg');
      expect(info.effectiveBackground, 'https://i0.hdslb.com/bg.jpg');
      expect(info.liveStartTime, 1788762159);
      expect(info.isLiving, isTrue);

      // Fallback 1: background when app_background is empty
      final fallback1 = LiveRoomInfo.fromJson({
        'room_info': {
          'room_id': 1,
          'background': 'http://i0.hdslb.com/web_bg.jpg',
          'keyframe': 'http://i0.hdslb.com/keyframe.jpg',
          'cover': 'http://i0.hdslb.com/cover.jpg',
        }
      });
      expect(fallback1.effectiveBackground, 'https://i0.hdslb.com/web_bg.jpg');

      // Fallback 2: keyframe when backgrounds are empty
      final fallback2 = LiveRoomInfo.fromJson({
        'room_info': {
          'room_id': 2,
          'keyframe': 'http://i0.hdslb.com/keyframe.jpg',
          'cover': 'http://i0.hdslb.com/cover.jpg',
        }
      });
      expect(fallback2.effectiveBackground, 'https://i0.hdslb.com/keyframe.jpg');

      // Fallback 3: cover when everything else is empty
      final fallback3 = LiveRoomInfo.fromJson({
        'room_info': {
          'room_id': 3,
          'cover': 'http://i0.hdslb.com/cover.jpg',
        }
      });
      expect(fallback3.effectiveBackground, 'https://i0.hdslb.com/cover.jpg');
    });

    test('ImageUtils.thumbnailUrl downscales background to 1280w webp', () {
      final bgUrl = ImageUtils.thumbnailUrl(
        'http://i0.hdslb.com/bfs/live/7e345cf1412cde6545c812122d1bc52f8c542347.jpg',
        type: 'background',
      );
      expect(
        bgUrl,
        'https://i0.hdslb.com/bfs/live/7e345cf1412cde6545c812122d1bc52f8c542347.jpg@1280w.webp',
      );
    });
  });
}


// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/feature/video/danmaku/DanmakuProto.kt
//
// B 站弹幕 Protobuf 手写解析器（作为 PiliPlus .pb.dart 生成代码的补充/备选）。
//
// BiliPai 的手写解析器比 .pb.dart 生成代码更灵活地处理 API 版本差异：
// - DmWebViewReply 的字段号在新旧版 web/view 接口间存在歧义（dmSge/flag/
//   specialDms/count/commandDms/dmSetting 的 field number 在 3-10 间漂移），
//   本解析器用启发式判断（isLikelyDmSegConfig / isLikelyDanmakuFlagConfig）
//   消解歧义，而非依赖固定 field number。
// - DanmakuElem 解析 29 个字段（id/progress/mode/fontsize/color/midHash/
//   content/ctime/weight/action/pool/idStr/attr/like/animation/extra/colorful/
//   type/oid/dmFrom/count/isSelf）。
//
// 协议格式（Protobuf Wire Format）：
// - DmSegMobileReply { repeated DanmakuElem elems = 1; }
// - 每个 tag = (fieldNumber << 3) | wireType
// - wireType: 0=Varint, 1=64-bit, 2=length-delimited, 5=32-bit

import 'dart:convert';
import 'dart:typed_data';

/// 弹幕彩色类型常量（与 v1.pbenum.dart 的 DmColorfulType 对齐）。
abstract final class ProtoDmColorfulType {
  static const int none = 0;
  static const int vipGradualColor = 60001;
}

/// 弹幕元素（手写解析版，字段与 v1.pb.dart 的 DanmakuElem 语义一致）。
///
/// 当 .pb.dart 生成代码因 API 版本差异解析失败时，可作为备选解析器。
class ProtoDanmakuElem {
  final int id;
  final int progress; // 出现时间（毫秒）
  final int mode; // 1-3=滚动, 4=底部, 5=顶部, 7=高级
  final int fontsize;
  final int color; // RGB 24 位
  final String midHash;
  final String content;
  final int weight; // AI 过滤权重
  final int pool; // 0=普通, 1=字幕, 2=特殊
  final int like;
  final int colorful; // 60001=大会员渐变彩
  int count; // 服务端合并计数（可变，合并去重时累加）
  bool isSelf; // 当前账号发送（解析后由上层标记）

  ProtoDanmakuElem({
    this.id = 0,
    this.progress = 0,
    this.mode = 1,
    this.fontsize = 25,
    this.color = 0xFFFFFF,
    this.midHash = '',
    this.content = '',
    this.weight = 0,
    this.pool = 0,
    this.like = 0,
    this.colorful = ProtoDmColorfulType.none,
    this.count = 0,
    this.isSelf = false,
  });
}

/// 弹幕分段配置。
class ProtoDmSegConfig {
  final int pageSize;
  final int total;
  const ProtoDmSegConfig({this.pageSize = 0, this.total = 0});
}

/// 弹幕推荐标记配置。
class ProtoDanmakuFlagConfig {
  final int recFlag;
  final String recText;
  final int recSwitch;
  const ProtoDanmakuFlagConfig({
    this.recFlag = 0,
    this.recText = '',
    this.recSwitch = 0,
  });
}

/// 互动弹幕指令（DmWebViewReply.commandDms）。
class ProtoCommandDm {
  final int id;
  final int oid;
  final int mid;
  final String command;
  final String content;
  final int progress;
  final String ctime;
  final String mtime;
  final String extra;
  final String idStr;

  const ProtoCommandDm({
    this.id = 0,
    this.oid = 0,
    this.mid = 0,
    this.command = '',
    this.content = '',
    this.progress = 0,
    this.ctime = '',
    this.mtime = '',
    this.extra = '',
    this.idStr = '',
  });
}

/// 弹幕元数据响应（x/v2/dm/web/view）。
///
/// 字段号在新旧版接口间存在歧义，[DanmakuProto.parseWebViewReply] 用启发式
/// 判断消解：dmSge/flag/specialDms/count/commandDms/dmSetting 在 field 3-10
/// 间漂移。
class ProtoDmWebViewReply {
  final int state; // 1=UP 关闭弹幕
  final String textSide;
  final ProtoDmSegConfig? dmSge;
  final ProtoDanmakuFlagConfig? flag;
  final List<String> specialDms; // 高级弹幕 URL 列表
  final bool checkBox;
  final int count;
  final List<ProtoCommandDm> commandDms; // 互动弹幕指令
  final ProtoDmSetting? dmSetting;

  const ProtoDmWebViewReply({
    this.state = 0,
    this.textSide = '',
    this.dmSge,
    this.flag,
    this.specialDms = const [],
    this.checkBox = true,
    this.count = 0,
    this.commandDms = const [],
    this.dmSetting,
  });
}

/// 弹幕设置（DmWebViewReply.dmSetting）。
class ProtoDmSetting {
  final bool dmSwitch;
  final bool aiSwitch;
  final int aiLevel;
  final bool blocktop;
  final bool blockscroll;
  final bool blockbottom;
  final bool blockcolor;
  final bool blockspecial;
  final bool preventeshading;
  final bool dmask;
  final double opacity;
  final int dmarea;
  final double speedplus;
  final double fontsize;
  final bool screensync;
  final bool speedsync;
  final String fontfamily;
  final bool bold;
  final int fontborder;
  final String drawType;

  const ProtoDmSetting({
    this.dmSwitch = true,
    this.aiSwitch = true,
    this.aiLevel = 0,
    this.blocktop = false,
    this.blockscroll = false,
    this.blockbottom = false,
    this.blockcolor = false,
    this.blockspecial = false,
    this.preventeshading = false,
    this.dmask = false,
    this.opacity = 1.0,
    this.dmarea = 0,
    this.speedplus = 1.0,
    this.fontsize = 1.0,
    this.screensync = false,
    this.speedsync = false,
    this.fontfamily = '',
    this.bold = false,
    this.fontborder = 0,
    this.drawType = '',
  });
}

/// B 站弹幕 Protobuf 手写解析器。
///
/// 作为 .pb.dart 生成代码的补充/备选：当 API 版本差异导致生成代码解析
/// 失败时，本解析器的启发式字段判断能更宽松地兼容旧/新接口。
abstract final class DanmakuProto {
  /// 解析 DmSegMobileReply → 弹幕元素列表。
  ///
  /// 过滤掉 content 为空的元素（B 站偶发返回空内容占位）。
  static List<ProtoDanmakuElem> parse(Uint8List data) {
    final result = <ProtoDanmakuElem>[];
    if (data.isEmpty) return result;
    try {
      final input = _ProtoInput(data);
      // DmSegMobileReply 的 field 1 是 repeated DanmakuElem。
      while (!input.isAtEnd) {
        final tag = input.readTag();
        final fieldNumber = tag >>> 3;
        final wireType = tag & 0x07;
        if (fieldNumber == 1 && wireType == 2) {
          final elemData = input.readBytes();
          final elem = _parseDanmakuElem(elemData);
          if (elem != null && elem.content.isNotEmpty) {
            result.add(elem);
          }
        } else {
          input.skipField(wireType);
        }
      }
    } catch (_) {
      // 解析失败返回已解析部分。
    }
    return result;
  }

  /// 解析 DmWebViewReply（含字段号歧义消解启发式）。
  static ProtoDmWebViewReply parseWebViewReply(Uint8List data) {
    if (data.isEmpty) return const ProtoDmWebViewReply();

    var state = 0;
    var textSide = '';
    ProtoDmSegConfig? dmSge;
    ProtoDanmakuFlagConfig? flag;
    final specialDms = <String>[];
    var checkBox = true;
    var count = 0;
    final commandDms = <ProtoCommandDm>[];
    ProtoDmSetting? dmSetting;

    try {
      final input = _ProtoInput(data);
      while (!input.isAtEnd) {
        final tag = input.readTag();
        final fieldNumber = tag >>> 3;
        final wireType = tag & 0x07;

        switch (fieldNumber) {
          case 1:
            state = input.readVarint().toInt();
          case 2:
            input.skipField(wireType);
          // 兼容旧/新 web/view 字段：旧版 dmSge=3、flag=4；新版 dmSge=4、flag=5
          case 3:
            if (wireType == 2) {
              final bytes = input.readBytes();
              final candidate = _parseDmSegConfig(bytes);
              if (_isLikelyDmSegConfig(candidate)) {
                dmSge = candidate;
              } else {
                textSide = utf8.decode(bytes, allowMalformed: true);
              }
            } else {
              input.skipField(wireType);
            }
          case 4:
            if (wireType == 2) {
              final bytes = input.readBytes();
              final dmSegCandidate = _parseDmSegConfig(bytes);
              if (_isLikelyDmSegConfig(dmSegCandidate)) {
                dmSge = dmSegCandidate;
              } else {
                final flagCandidate = _parseDanmakuFlagConfig(bytes);
                if (_isLikelyDanmakuFlagConfig(flagCandidate)) {
                  flag = flagCandidate;
                }
              }
            } else {
              input.skipField(wireType);
            }
          // 旧版 specialDms=5，新版 flag=5
          case 5:
            if (wireType == 2) {
              final bytes = input.readBytes();
              final flagCandidate = _parseDanmakuFlagConfig(bytes);
              if (_isLikelyDanmakuFlagConfig(flagCandidate)) {
                flag = flagCandidate;
              } else {
                final url = _decodeSpecialDmUrl(bytes);
                if (url != null) specialDms.add(url);
              }
            } else {
              input.skipField(wireType);
            }
          case 6:
            if (wireType == 2) {
              final url = _decodeSpecialDmUrl(input.readBytes());
              if (url != null) specialDms.add(url);
            } else {
              input.skipField(wireType);
            }
          // 旧版 count=7，新版 count=8；旧版 commandDms=8，新版 commandDms=9
          case 7:
            switch (wireType) {
              case 0:
                final value = input.readVarint();
                if (value > 1) {
                  count = value.toInt();
                } else {
                  checkBox = value != 0;
                }
              case 2:
                final cmd = _parseCommandDm(input.readBytes());
                if (cmd != null) commandDms.add(cmd);
              default:
                input.skipField(wireType);
            }
          case 8:
            switch (wireType) {
              case 0:
                count = input.readVarint().toInt();
              case 2:
                final cmd = _parseCommandDm(input.readBytes());
                if (cmd != null) commandDms.add(cmd);
              default:
                input.skipField(wireType);
            }
          // 旧版 dmSetting=9，新版 dmSetting=10
          case 9:
            if (wireType == 2) {
              final bytes = input.readBytes();
              final cmd = _parseCommandDm(bytes);
              if (cmd != null) {
                commandDms.add(cmd);
              } else {
                dmSetting = _parseDmSetting(bytes);
              }
            } else {
              input.skipField(wireType);
            }
          case 10:
            if (wireType == 2) {
              dmSetting = _parseDmSetting(input.readBytes());
            } else {
              input.skipField(wireType);
            }
          default:
            input.skipField(wireType);
        }
      }
    } catch (_) {
      // 解析失败返回已解析部分。
    }

    return ProtoDmWebViewReply(
      state: state,
      textSide: textSide,
      dmSge: dmSge,
      flag: flag,
      specialDms: specialDms,
      checkBox: checkBox,
      count: count,
      commandDms: commandDms,
      dmSetting: dmSetting,
    );
  }

  // ── 启发式判断（消解字段号歧义）──

  static bool _isLikelyDmSegConfig(ProtoDmSegConfig config) {
    return config.pageSize >= 1000 && config.total >= 1 && config.total <= 10000;
  }

  static bool _isLikelyDanmakuFlagConfig(ProtoDanmakuFlagConfig config) {
    return config.recFlag != 0 ||
        config.recSwitch != 0 ||
        config.recText.isNotEmpty;
  }

  static String? _decodeSpecialDmUrl(Uint8List data) {
    if (data.isEmpty) return null;
    final text = utf8.decode(data, allowMalformed: true).trim();
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('//')) {
      return text;
    }
    return null;
  }

  // ── 子消息解析 ──

  static ProtoDanmakuElem? _parseDanmakuElem(Uint8List data) {
    if (data.isEmpty) return null;
    var id = 0, progress = 0, mode = 1, fontsize = 25, color = 0xFFFFFF;
    var weight = 0, pool = 0, like = 0;
    var colorful = ProtoDmColorfulType.none;
    var count = 0;
    var isSelf = false;
    var midHash = '', content = '';
    try {
      final input = _ProtoInput(data);
      while (!input.isAtEnd) {
        final tag = input.readTag();
        final fieldNumber = tag >>> 3;
        final wireType = tag & 0x07;
        switch (fieldNumber) {
          case 1:
            id = input.readVarint().toInt();
          case 2:
            progress = input.readVarint().toInt();
          case 3:
            mode = input.readVarint().toInt();
          case 4:
            fontsize = input.readVarint().toInt();
          case 5:
            color = input.readVarint().toInt();
          case 6:
            midHash = input.readString();
          case 7:
            content = input.readString();
          case 8:
            input.readVarint(); // ctime (skip)
          case 9:
            weight = input.readVarint().toInt();
          case 10:
            input.readString(); // action (skip)
          case 11:
            pool = input.readVarint().toInt();
          case 12:
            input.readString(); // idStr (skip)
          case 13:
            input.readVarint(); // attr (skip)
          case 15:
            like = input.readVarint().toInt();
          case 22:
            input.readString(); // animation (skip)
          case 23:
            input.readString(); // extra (skip)
          case 24:
            colorful = input.readVarint().toInt();
          case 25:
            input.readVarint(); // type (skip)
          case 26:
            input.readVarint(); // oid (skip)
          case 27:
            input.readVarint(); // dmFrom (skip)
          case 28:
            count = input.readVarint().toInt();
          case 29:
            isSelf = input.readVarint() != 0;
          default:
            input.skipField(wireType);
        }
      }
    } catch (_) {
      return null;
    }
    return ProtoDanmakuElem(
      id: id,
      progress: progress,
      mode: mode,
      fontsize: fontsize,
      color: color,
      midHash: midHash,
      content: content,
      weight: weight,
      pool: pool,
      like: like,
      colorful: colorful,
      count: count,
      isSelf: isSelf,
    );
  }

  static ProtoDmSegConfig _parseDmSegConfig(Uint8List data) {
    var pageSize = 0, total = 0;
    try {
      final input = _ProtoInput(data);
      while (!input.isAtEnd) {
        final tag = input.readTag();
        final fieldNumber = tag >>> 3;
        final wireType = tag & 0x07;
        switch (fieldNumber) {
          case 1:
            pageSize = input.readVarint().toInt();
          case 2:
            total = input.readVarint().toInt();
          default:
            input.skipField(wireType);
        }
      }
    } catch (_) {}
    return ProtoDmSegConfig(pageSize: pageSize, total: total);
  }

  static ProtoDanmakuFlagConfig _parseDanmakuFlagConfig(Uint8List data) {
    var recFlag = 0, recSwitch = 0;
    var recText = '';
    try {
      final input = _ProtoInput(data);
      while (!input.isAtEnd) {
        final tag = input.readTag();
        final wireType = tag & 0x07;
        switch (tag >>> 3) {
          case 1:
            recFlag = input.readVarint().toInt();
          case 2:
            recText = input.readString();
          case 3:
            recSwitch = input.readVarint().toInt();
          default:
            input.skipField(wireType);
        }
      }
    } catch (_) {}
    return ProtoDanmakuFlagConfig(
      recFlag: recFlag,
      recText: recText,
      recSwitch: recSwitch,
    );
  }

  static ProtoCommandDm? _parseCommandDm(Uint8List data) {
    if (data.isEmpty) return null;
    var id = 0, oid = 0, mid = 0, progress = 0;
    var command = '', content = '', ctime = '', mtime = '', extra = '', idStr = '';
    try {
      final input = _ProtoInput(data);
      while (!input.isAtEnd) {
        final tag = input.readTag();
        final wireType = tag & 0x07;
        switch (tag >>> 3) {
          case 1:
            id = input.readVarint().toInt();
          case 2:
            oid = input.readVarint().toInt();
          case 3:
            mid = input.readVarint().toInt();
          case 4:
            command = input.readString();
          case 5:
            content = input.readString();
          case 6:
            progress = input.readVarint().toInt();
          case 7:
            ctime = input.readString();
          case 8:
            mtime = input.readString();
          case 9:
            extra = input.readString();
          case 10:
            idStr = input.readString();
          default:
            input.skipField(wireType);
        }
      }
    } catch (_) {
      return null;
    }
    if (command.trim().isEmpty &&
        content.trim().isEmpty &&
        extra.trim().isEmpty) {
      return null;
    }
    return ProtoCommandDm(
      id: id,
      oid: oid,
      mid: mid,
      command: command,
      content: content,
      progress: progress,
      ctime: ctime,
      mtime: mtime,
      extra: extra,
      idStr: idStr,
    );
  }

  static ProtoDmSetting _parseDmSetting(Uint8List data) {
    var dmSwitch = true, aiSwitch = true, aiLevel = 0;
    var blocktop = false, blockscroll = false, blockbottom = false;
    var blockcolor = false, blockspecial = false, preventeshading = false;
    var dmask = false, dmarea = 0;
    var opacity = 1.0, speedplus = 1.0, fontsize = 1.0;
    var screensync = false, speedsync = false, bold = false, fontborder = 0;
    var fontfamily = '', drawType = '';
    try {
      final input = _ProtoInput(data);
      while (!input.isAtEnd) {
        final tag = input.readTag();
        final wireType = tag & 0x07;
        switch (tag >>> 3) {
          case 1:
            dmSwitch = input.readVarint() != 0;
          case 2:
            aiSwitch = input.readVarint() != 0;
          case 3:
            aiLevel = input.readVarint().toInt();
          case 4:
            blocktop = input.readVarint() != 0;
          case 5:
            blockscroll = input.readVarint() != 0;
          case 6:
            blockbottom = input.readVarint() != 0;
          case 7:
            blockcolor = input.readVarint() != 0;
          case 8:
            blockspecial = input.readVarint() != 0;
          case 9:
            preventeshading = input.readVarint() != 0;
          case 10:
            dmask = input.readVarint() != 0;
          case 11:
            opacity = input.readFloat();
          case 12:
            dmarea = input.readVarint().toInt();
          case 13:
            speedplus = input.readFloat();
          case 14:
            fontsize = input.readFloat();
          case 15:
            screensync = input.readVarint() != 0;
          case 16:
            speedsync = input.readVarint() != 0;
          case 17:
            fontfamily = input.readString();
          case 18:
            bold = input.readVarint() != 0;
          case 19:
            fontborder = input.readVarint().toInt();
          case 20:
            drawType = input.readString();
          default:
            input.skipField(wireType);
        }
      }
    } catch (_) {}
    return ProtoDmSetting(
      dmSwitch: dmSwitch,
      aiSwitch: aiSwitch,
      aiLevel: aiLevel,
      blocktop: blocktop,
      blockscroll: blockscroll,
      blockbottom: blockbottom,
      blockcolor: blockcolor,
      blockspecial: blockspecial,
      preventeshading: preventeshading,
      dmask: dmask,
      opacity: opacity,
      dmarea: dmarea,
      speedplus: speedplus,
      fontsize: fontsize,
      screensync: screensync,
      speedsync: speedsync,
      fontfamily: fontfamily,
      bold: bold,
      fontborder: fontborder,
      drawType: drawType,
    );
  }
}

/// 简易 Protobuf 输入流读取器。
///
/// 移植自 BiliPai `ProtoInput` 内部类，提供 varint/bytes/string/float 读取
/// 与未知字段跳过能力。
class _ProtoInput {
  _ProtoInput(this.data);

  final Uint8List data;
  int _position = 0;

  bool get isAtEnd => _position >= data.length;

  int readTag() => readVarint().toInt();

  /// 读取 Varint（变长整数）。
  ///
  /// 每字节低 7 位为数据，最高位为继续标志。最多 10 字节（64 位）。
  int readVarint() {
    var result = 0;
    var shift = 0;
    while (_position < data.length) {
      final byte = data[_position++] & 0xFF;
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
      if (shift >= 64) {
        // Varint 过长，截断保护。
        break;
      }
    }
    return result;
  }

  /// 读取 length-delimited 字节数组。
  Uint8List readBytes() {
    final length = readVarint();
    if (length <= 0 || _position + length > data.length) {
      return Uint8List(0);
    }
    final result = Uint8List.sublistView(data, _position, _position + length);
    _position += length;
    return result;
  }

  /// 读取 UTF-8 字符串。
  String readString() {
    final bytes = readBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 读取 32-bit 浮点数（小端）。
  double readFloat() {
    if (_position + 4 > data.length) return 0.0;
    final bits = (data[_position] & 0xFF) |
        ((data[_position + 1] & 0xFF) << 8) |
        ((data[_position + 2] & 0xFF) << 16) |
        ((data[_position + 3] & 0xFF) << 24);
    _position += 4;
    // 将 int 位模式转为 double（IEEE 754 单精度）。
    final byteData = ByteData(4)..setInt32(0, bits, Endian.little);
    return byteData.getFloat32(0, Endian.little);
  }

  /// 跳过未知字段。
  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint(); // Varint
      case 1:
        _position += 8; // 64-bit
      case 2:
        final length = readVarint(); // Length-delimited
        _position += length;
      case 5:
        _position += 4; // 32-bit
      default:
        // 未知 wireType 忽略（可能破坏后续解析，但 BiliPai 同样如此）。
        break;
    }
  }
}

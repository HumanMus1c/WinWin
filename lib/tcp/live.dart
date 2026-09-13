// Ported from PiliPlus (Dart) -> WinWin
// Original: lib/tcp/live.dart
//
// 直播弹幕二进制 WebSocket 协议客户端。
//
// B 站直播弹幕走自研二进制协议（非标准 WebSocket 文本帧）：
//   - 每帧 16 字节头 + payload
//   - 头部：packetLength(4 BE) + headerLength(2 BE) + protocolVersion(2 BE)
//           + operation(4 BE) + sequenceId(4 BE)
//   - protocolVersion: 0=裸 JSON, 1=心跳, 2=zlib, 3=brotli
//   - operation:
//       2   = heartbeat ack（人气值）
//       3   = heartbeat req
//       5   = normal（弹幕/礼物/入场等消息）
//       7   = auth req
//       8   = auth ack
//   - payload 可能嵌套：zlib/brotli 解压后是一组子帧，递归解析
//
// 连接流程：
//   1. wss://<host>:<port>/sub
//   2. 发送 auth req（含 uid/roomid/key/buvid3/...）
//   3. 收到 auth ack（op=8）→ 连接就绪
//   4. 每 30s 发送 heartbeat req（op=3）
//   5. 收到 heartbeat ack（op=2）→ 人气值（payload 4 字节 BE int）
//   6. 收到 normal（op=5）→ 解析弹幕/礼物/事件

import 'dart:async';
import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:winwin/http/loading_state.dart';

/// 直播弹幕协议常量。
abstract final class LiveDanmakuProtocol {
  /// WebSocket 子协议路径。
  static const String subPath = '/sub';

  /// 协议版本。
  static const int protocolVersion = 1;

  // ── operation 值 ──
  static const int opHeartbeatAck = 2;
  static const int opHeartbeatReq = 3;
  static const int opNormal = 5;
  static const int opAuthReq = 7;
  static const int opAuthAck = 8;

  // ── protocolVersion 值 ──
  static const int verPlain = 0;
  static const int verHeartbeat = 1;
  static const int verZlib = 2;
  static const int verBrotli = 3;

  /// 默认直播弹幕服务器（B 站哈勃分配的备用地址）。
  static const String defaultHost = 'hw-bj-live-comet-07.chat.bilibili.com';
  static const int defaultPort = 712;

  /// 心跳间隔（秒）。
  static const int heartbeatIntervalSec = 30;
}

/// 直播弹幕消息体（一条 normal 消息或预拉取历史消息解析后）。
class LiveDanmakuMessage {
  /// 消息类型（cmd 字段值，如 'DANMU_MSG'、'SEND_GIFT'、'INTERACT_WORD'）。
  final String cmd;
  /// 发送者昵称（若显式指定）。
  final String? userName;
  /// 弹幕正文（若显式指定）。
  final String? customText;
  /// 原始 JSON 数据。
  final Map<String, dynamic> raw;

  LiveDanmakuMessage({
    required this.cmd,
    this.userName,
    this.customText,
    required this.raw,
  });

  factory LiveDanmakuMessage.fromJson(Map<String, dynamic> json) {
    return LiveDanmakuMessage(
      cmd: json['cmd']?.toString() ?? '',
      raw: json,
    );
  }

  /// 从云端历史弹幕条目（/xlive/web-room/v1/dM/gethistory data.room 节点）构造。
  factory LiveDanmakuMessage.fromPrefetch(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final base = user?['base'] as Map<String, dynamic>?;
    final uname = base?['name']?.toString() ??
        user?['name']?.toString() ??
        '观众';
    final text = json['text']?.toString() ?? '';
    return LiveDanmakuMessage(
      cmd: 'DANMU_MSG',
      userName: uname,
      customText: text,
      raw: json,
    );
  }

  /// 是否为弹幕消息（DANMU_MSG）。
  bool get isDanmaku => cmd == 'DANMU_MSG';

  /// 弹幕发送者昵称。
  String get senderName {
    if (userName != null && userName!.isNotEmpty) return userName!;
    final info = raw['info'] as List?;
    if (info != null &&
        info.length > 2 &&
        info[2] is List &&
        (info[2] as List).length > 1) {
      final name = info[2][1]?.toString();
      if (name != null && name.isNotEmpty) return name;
    }
    return '观众';
  }

  /// 弹幕文本（仅 isDanmaku 时有效）。
  String? get danmakuText {
    if (customText != null) return customText;
    return raw['info'] is List && raw['info'].length > 1
        ? raw['info'][1]?.toString()
        : null;
  }

  /// 弹幕颜色（仅 isDanmaku 时有效，十进制 RGB）。
  int? get danmakuColor => raw['info'] is List && raw['info'].length > 3
      ? _asInt(raw['info'][3])
      : null;
}

/// 直播弹幕连接状态。
enum LiveDanmakuStatus {
  disconnected,
  connecting,
  authing,
  connected,
  authFailed,
  closed,
  error,
}

/// 直播弹幕 WebSocket 客户端。
///
/// 生命周期：
///   [connect] → [statusStream] 变为 connected → [messageStream] 推送弹幕 → [disconnect]。
/// 连接成功后自动每 [LiveDanmakuProtocol.heartbeatIntervalSec] 秒发送心跳，
/// 并在收到 auth ack 后开始解析 normal 消息。
class LiveDanmakuClient {
  LiveDanmakuClient({
    this.host = LiveDanmakuProtocol.defaultHost,
    this.port = LiveDanmakuProtocol.defaultPort,
    this.uid = 0,
    required this.roomId,
    this.token = '',
    this.buvid3 = '',
    this.platform = 'web',
    this.version = '0.6.5',
    this.servers = const [],
  });

  final String host;
  final int port;
  final int uid;
  final int roomId;
  final String token;
  final String buvid3;
  final String platform;
  final String version;
  final List<String> servers;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;

  /// zlib 解压编解码器（桌面端 dart:io）。
  static final ZLibCodec _zlib = ZLibCodec();

  /// 连接状态流。
  final StreamController<LiveDanmakuStatus> _statusController =
      StreamController<LiveDanmakuStatus>.broadcast();
  Stream<LiveDanmakuStatus> get statusStream => _statusController.stream;

  void _setStatus(LiveDanmakuStatus s) {
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// 弹幕消息流（仅 normal op=5 解析后的消息）。
  final StreamController<LiveDanmakuMessage> _messageController =
      StreamController<LiveDanmakuMessage>.broadcast();
  Stream<LiveDanmakuMessage> get messageStream => _messageController.stream;

  /// 人气流（heartbeat ack 携带的人气值，每 30s 一次）。
  final StreamController<int> _popularityController =
      StreamController<int>.broadcast();
  Stream<int> get popularityStream => _popularityController.stream;

  bool _disposed = false;

  /// 连接直播弹幕服务器。
  ///
  /// 优先轮询 [servers] 彗星集群，失败兜底至默认服务器。
  /// 成功后 [statusStream] 推送 connected，失败推送 error/authFailed。
  Future<LoadingState<void>> connect() async {
    if (_disposed) return const Error('client disposed');
    _setStatus(LiveDanmakuStatus.connecting);
    try {
      final candidateUris = <Uri>[];
      for (final s in servers) {
        final parsed = Uri.tryParse(s);
        if (parsed != null && parsed.host.isNotEmpty) {
          candidateUris.add(parsed);
        }
      }
      if (candidateUris.isEmpty) {
        candidateUris.add(
          Uri.parse('wss://$host:$port${LiveDanmakuProtocol.subPath}'),
        );
      }

      WebSocketChannel? connectedChannel;
      for (final uri in candidateUris) {
        try {
          final ch = IOWebSocketChannel.connect(
            uri,
            pingInterval: const Duration(seconds: 30),
          );
          await ch.ready;
          connectedChannel = ch;
          break;
        } catch (_) {
          // 连接当前节点失败，尝试候选列表中的下一个节点
        }
      }

      if (connectedChannel == null) {
        _setStatus(LiveDanmakuStatus.error);
        return const Error('连接直播弹幕服务器集群全部失败');
      }

      _channel = connectedChannel;
      _setStatus(LiveDanmakuStatus.authing);
      _subscription = _channel!.stream.listen(
        _onData,
        onError: (Object e) {
          _setStatus(LiveDanmakuStatus.error);
        },
        onDone: () {
          _setStatus(LiveDanmakuStatus.closed);
        },
      );
      // 发送 auth 包。
      _sendAuth();
      return const Success(null);
    } catch (e) {
      _setStatus(LiveDanmakuStatus.error);
      return Error('连接直播弹幕失败：$e');
    }
  }

  /// 断开连接。
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setStatus(LiveDanmakuStatus.disconnected);
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _statusController.close();
    _messageController.close();
    _popularityController.close();
  }

  // ── 内部：协议帧编码 ──

  /// 发送 auth 包（op=7）。
  void _sendAuth() {
    final authBody = jsonEncode({
      'roomid': roomId,
      'uid': uid,
      'protover': 3,
      'platform': platform,
      'type': 2,
      'key': token,
      if (buvid3.isNotEmpty) 'buvid': buvid3,
    });
    final frame = _buildFrame(
      operation: LiveDanmakuProtocol.opAuthReq,
      payload: Uint8List.fromList(utf8.encode(authBody)),
      protocolVersion: LiveDanmakuProtocol.protocolVersion,
    );
    _channel?.sink.add(frame);
  }

  /// 发送心跳包（op=3）。
  void _sendHeartbeat() {
    final frame = _buildFrame(
      operation: LiveDanmakuProtocol.opHeartbeatReq,
      payload: Uint8List(0),
      protocolVersion: LiveDanmakuProtocol.verHeartbeat,
    );
    _channel?.sink.add(frame);
  }

  /// 构造协议帧：16 字节头 + payload。
  ///
  /// - packetLength（4 BE）：header(16) + payload.length
  /// - headerLength（2 BE）：固定 16
  /// - protocolVersion（2 BE）
  /// - operation（4 BE）
  /// - sequenceId（4 BE）：固定 1
  Uint8List _buildFrame({
    required int operation,
    required Uint8List payload,
    int protocolVersion = LiveDanmakuProtocol.protocolVersion,
    int sequenceId = 1,
  }) {
    final headerLength = 16;
    final packetLength = headerLength + payload.length;
    final frame = ByteData(packetLength);
    frame.setUint32(0, packetLength, Endian.big);
    frame.setUint16(4, headerLength, Endian.big);
    frame.setUint16(6, protocolVersion, Endian.big);
    frame.setUint32(8, operation, Endian.big);
    frame.setUint32(12, sequenceId, Endian.big);
    final bytes = frame.buffer.asUint8List();
    bytes.setRange(headerLength, packetLength, payload);
    return bytes;
  }

  // ── 内部：协议帧解码 ──

  /// 收到二进制数据：按 packetLength 切分，每帧递归解析。
  void _onData(dynamic data) {
    if (data is! List<int>) return;
    final bytes = Uint8List.fromList(data);
    _parseFrames(bytes);
  }

  /// 解析一组协议帧（可能含多个 packetLength 切分）。
  void _parseFrames(Uint8List bytes) {
    var offset = 0;
    while (offset + 16 <= bytes.length) {
      final view = ByteData.sublistView(bytes, offset);
      final packetLength = view.getUint32(0, Endian.big);
      if (packetLength < 16 || offset + packetLength > bytes.length) break;
      final headerLength = view.getUint16(4, Endian.big);
      final protocolVersion = view.getUint16(6, Endian.big);
      final operation = view.getUint32(8, Endian.big);
      final payloadStart = offset + headerLength;
      final payloadEnd = offset + packetLength;
      final payload = Uint8List.sublistView(bytes, payloadStart, payloadEnd);
      _dispatchFrame(operation, protocolVersion, payload);
      offset += packetLength;
    }
  }

  /// 分发单帧：按 operation 处理。
  void _dispatchFrame(int operation, int protocolVersion, Uint8List payload) {
    switch (operation) {
      case LiveDanmakuProtocol.opAuthAck:
        // 认证成功：启动心跳定时器。
        _heartbeatTimer?.cancel();
        _heartbeatTimer = Timer.periodic(
          const Duration(seconds: LiveDanmakuProtocol.heartbeatIntervalSec),
          (_) => _sendHeartbeat(),
        );
        _setStatus(LiveDanmakuStatus.connected);
        break;
      case LiveDanmakuProtocol.opHeartbeatAck:
        // 人气值：payload 4 字节 BE int。
        if (payload.length >= 4) {
          final pop = ByteData.sublistView(payload).getUint32(0, Endian.big);
          if (!_popularityController.isClosed) _popularityController.add(pop);
        }
        break;
      case LiveDanmakuProtocol.opNormal:
        // 普通消息：按 protocolVersion 解压后递归解析。
        _handleNormal(protocolVersion, payload);
        break;
      default:
        // 未知 operation 忽略。
        break;
    }
  }

  /// 处理 normal 消息：按 protocolVersion 决定是否解压。
  void _handleNormal(int protocolVersion, Uint8List payload) {
    switch (protocolVersion) {
      case LiveDanmakuProtocol.verPlain:
        // 裸 JSON：直接解析。
        _emitMessage(payload);
        break;
      case LiveDanmakuProtocol.verZlib:
        // zlib 压缩：解压后递归解析（解压结果是一组帧）。
        try {
          final decompressed = Uint8List.fromList(_zlib.decode(payload));
          _parseFrames(decompressed);
        } catch (_) {
          // 解压失败忽略。
        }
        break;
      case LiveDanmakuProtocol.verBrotli:
        // brotli 压缩：解压后递归解析。
        try {
          final decompressed = brotli.decode(payload);
          _parseFrames(Uint8List.fromList(decompressed));
        } catch (_) {
          // 解压失败忽略。
        }
        break;
      default:
        // 未知版本忽略。
        break;
    }
  }

  /// 解析 JSON payload 并推送到 messageStream。
  void _emitMessage(Uint8List payload) {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is Map<String, dynamic>) {
        if (!_messageController.isClosed) {
          _messageController.add(LiveDanmakuMessage.fromJson(decoded));
        }
      }
    } catch (_) {
      // 非合法 JSON 忽略。
    }
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

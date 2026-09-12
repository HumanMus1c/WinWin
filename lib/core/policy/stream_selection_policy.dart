// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/data/model/response/VideoResponse.kt
//   Dash.getBestVideo() / Dash.getBestAudio() 逻辑
//
// 编解码器感知选流：在同等清晰度（qn）下优先选择更高效的编解码器，
// 并匹配设备解码能力。AV1 > HEVC > AVC（评分 +3 / +2 / +1）。
// 杜比全景声 / Hi-Res 音频走特殊处理路径。

import 'package:winwin/models/video/play_url.dart';

/// 视频编解码器类型。
enum VideoCodec {
  /// H.264 / AVC，兼容性最好。
  avc,
  /// H.265 / HEVC，同码率画质优于 AVC。
  hevc,
  /// AV1，同码率画质最优，但解码开销较高。
  av1,
  /// 未知 / 无法识别的编解码器。
  unknown,
}

/// 设备解码能力档位。
enum DeviceCodecCapability {
  /// 仅保证 AVC（H.264）硬解。
  avcOnly,
  /// 支持 AVC + HEVC 硬解。
  hevc,
  /// 支持 AVC + HEVC + AV1 硬解（桌面端典型档位）。
  av1,
}

/// 音频特殊类型。
enum SpecialAudioKind {
  /// 普通音轨（DASH audio 列表内）。
  normal,
  /// 杜比全景声（dash.dolby.audio）。
  dolbyAtmos,
  /// Hi-Res 无损（audio id 30251）。
  hiRes,
}

/// 选流结果。
class StreamSelectionResult {
  final DashVideo? video;
  final DashAudio? audio;
  final VideoCodec videoCodec;
  final SpecialAudioKind audioKind;

  const StreamSelectionResult({
    required this.video,
    required this.audio,
    required this.videoCodec,
    required this.audioKind,
  });
}

/// 编解码器感知选流策略。
///
/// 评分规则（同一 qn 下多个编解码器轨道时）：
/// - AV1  +3（画质最优）
/// - HEVC +2（画质次优）
/// - AVC  +1（兼容性兜底）
///
/// 最终轨道 = 最高 qn（不超过 [maxQn]）中评分最高的编解码器。
/// 若设备不支持某编解码器则跳过该轨道（降级到下一档）。
class StreamSelectionPolicy {
  StreamSelectionPolicy._();

  /// 从 [codecs] 字符串推断编解码器类型。
  ///
  /// B 站 DASH video 的 codecs 字段示例：
  /// - "avc1.640032" → AVC
  /// - "hev1.1.6.L120.B0" / "hvc1.*" → HEVC
  /// - "av01.0.08M.08" → AV1
  static VideoCodec identifyVideoCodec(String? codecs) {
    if (codecs == null || codecs.isEmpty) return VideoCodec.unknown;
    final lower = codecs.toLowerCase();
    if (lower.startsWith('av01')) return VideoCodec.av1;
    if (lower.startsWith('hev1') || lower.startsWith('hvc1')) {
      return VideoCodec.hevc;
    }
    if (lower.startsWith('avc1') || lower.startsWith('avc3')) {
      return VideoCodec.avc;
    }
    return VideoCodec.unknown;
  }

  /// 编解码器评分：默认优先通用硬件解码（HEVC +3 / AVC +2 / AV1 +1 / unknown 0）。
  /// 优先选取具备广泛 GPU 零拷贝硬解支持的格式（HEVC/AVC），避免回退到 dav1d CPU 软解引发卡顿掉帧。
  static int codecScore(VideoCodec codec, {List<VideoCodec>? preferredOrder}) {
    if (preferredOrder != null && preferredOrder.isNotEmpty) {
      final idx = preferredOrder.indexOf(codec);
      if (idx >= 0) {
        return preferredOrder.length - idx;
      }
    }
    switch (codec) {
      case VideoCodec.hevc:
        return 3;
      case VideoCodec.avc:
        return 2;
      case VideoCodec.av1:
        return 1;
      case VideoCodec.unknown:
        return 0;
    }
  }

  /// 判断设备是否支持该编解码器硬解。
  ///
  /// 桌面端（Windows + mdk）通常支持全档位；这里按 [capability] 严格
  /// 判断以便未来在移动端复用。unknown 编解码器视为可播放（兜底）。
  static bool isCodecSupported(VideoCodec codec, DeviceCodecCapability capability) {
    switch (codec) {
      case VideoCodec.avc:
        return true; // 所有档位均支持
      case VideoCodec.hevc:
        return capability == DeviceCodecCapability.hevc ||
            capability == DeviceCodecCapability.av1;
      case VideoCodec.av1:
        return capability == DeviceCodecCapability.av1;
      case VideoCodec.unknown:
        return true; // 兜底：未知编解码器不拦截
    }
  }

  /// 选最佳视频轨。
  ///
  /// 步骤：
  /// 1. 过滤掉 qn 超过 [maxQn] 的轨道。
  /// 2. 在剩余轨道中找出最高 qn。
  /// 3. 在该 qn 的所有编解码器轨道中，按设备支持 + 编解码器评分选最优。
  /// 4. 若全部被设备能力过滤掉，回退到该 qn 的第一个轨道（兜底）。
  /// 5. 若无满足 maxQn 的轨道，退回整个列表的最低清晰度。
  static DashVideo? selectBestVideo(
    List<DashVideo>? videos, {
    int maxQn = 80,
    DeviceCodecCapability capability = DeviceCodecCapability.av1,
    List<VideoCodec>? preferredCodecs,
  }) {
    if (videos == null || videos.isEmpty) return null;

    final playable = videos.where((v) {
      final qn = v.id;
      if (qn == null) return false;
      return qn <= maxQn;
    }).toList();
    if (playable.isEmpty) {
      // 无满足 maxQn 的轨道：退回最低清晰度（通常是兜底流）。
      return videos.reduce(
        (a, b) => (a.id ?? 0) <= (b.id ?? 0) ? a : b,
      );
    }

    final topQn = playable
        .map((v) => v.id ?? 0)
        .reduce((a, b) => a > b ? a : b);
    final topTracks = playable.where((v) => v.id == topQn).toList();

    // 在 topQn 轨道中按编解码器评分选最优（设备支持优先）。
    DashVideo? best;
    int bestScore = -1;
    for (final track in topTracks) {
      final codec = identifyVideoCodec(track.codecs);
      if (!isCodecSupported(codec, capability)) continue;
      final score = codecScore(codec, preferredOrder: preferredCodecs);
      // 同分时保留 bandwidth 更高的（更高质量）。
      if (score > bestScore ||
          (score == bestScore &&
              (track.bandwidth ?? 0) > (best?.bandwidth ?? 0))) {
        best = track;
        bestScore = score;
      }
    }
    // 设备能力过滤后无可用轨道：回退到 topQn 第一个轨道。
    return best ?? topTracks.first;
  }

  /// 选最佳音轨。
  ///
  /// 特殊音轨优先级（当 [preferSpecialAudio] 为 true 时）：
  /// 1. 杜比全景声（dolbyAudio 列表，需设备/会员支持）。
  /// 2. Hi-Res 无损（audio id 30251）。
  /// 3. 普通 DASH audio 中 bandwidth 最高的。
  ///
  /// [preferSpecialAudio] 为 false 时仅走普通音轨。
  static DashAudio? selectBestAudio(
    List<DashAudio>? audios, {
    List<DashAudio>? dolbyAudios,
    bool preferSpecialAudio = false,
  }) {
    // Hi-Res 无损（id 30251）优先（高保真立体声母带）。
    if (preferSpecialAudio && audios != null && audios.isNotEmpty) {
      for (final a in audios) {
        if (a.id == 30251 && (a.baseUrl?.isNotEmpty ?? false)) return a;
      }
    }

    // 杜比全景声（多声道下混容易衰减对白音量，仅在显式偏好时选取）。
    if (preferSpecialAudio &&
        dolbyAudios != null &&
        dolbyAudios.isNotEmpty) {
      return dolbyAudios.reduce(
        (a, b) => (b.bandwidth ?? 0) > (a.bandwidth ?? 0) ? b : a,
      );
    }

    if (audios == null || audios.isEmpty) return null;

    // 普通：bandwidth 最高的立体声音轨（如 30280=192K）。
    return audios.reduce(
      (a, b) => (b.bandwidth ?? 0) > (a.bandwidth ?? 0) ? b : a,
    );
  }

  /// 识别音轨的特殊类型。
  static SpecialAudioKind identifySpecialAudio(DashAudio? audio, {bool fromDolbyList = false}) {
    if (audio == null) return SpecialAudioKind.normal;
    if (fromDolbyList) return SpecialAudioKind.dolbyAtmos;
    if (audio.id == 30251) return SpecialAudioKind.hiRes;
    return SpecialAudioKind.normal;
  }

  /// 一次性选流：视频 + 音频，返回 [StreamSelectionResult]。
  ///
  /// 便捷封装，等价于分别调用 [selectBestVideo] 与 [selectBestAudio]。
  static StreamSelectionResult selectStreams(
    PlayUrlModel? playUrl, {
    int maxQn = 80,
    DeviceCodecCapability capability = DeviceCodecCapability.av1,
    bool preferSpecialAudio = false,
    List<VideoCodec>? preferredCodecs,
  }) {
    final dash = playUrl?.dash;
    final video = selectBestVideo(
      dash?.video,
      maxQn: maxQn,
      capability: capability,
      preferredCodecs: preferredCodecs,
    );
    final audio = selectBestAudio(
      dash?.audio,
      dolbyAudios: dash?.dolbyAudio,
      preferSpecialAudio: preferSpecialAudio,
    );
    return StreamSelectionResult(
      video: video,
      audio: audio,
      videoCodec: identifyVideoCodec(video?.codecs),
      audioKind: identifySpecialAudio(audio),
    );
  }
}

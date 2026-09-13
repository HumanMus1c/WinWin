import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show ThemeMode, ValueNotifier;
import 'package:hive_ce/hive.dart';

import 'package:winwin/core/account/login_utils.dart' show LoginUtils;
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/models/user/user_info.dart';
import 'package:winwin/models/common/cdn_type.dart';
import 'package:winwin/utils/credential_crypto.dart';
import 'package:winwin/theme/ui_style.dart';

/// Trimmed-down preference accessor.
/// Only covers settings that WinWin Phase 1 actually uses:
/// theme, network, player, danmaku, subtitle, and essential keys.
abstract final class Pref {
  static final Box _setting = GStorage.setting;
  static final Box _video = GStorage.video;
  static final Box _localCache = GStorage.localCache;

  // ---------- theme ----------
  static int get _themeTypeInt => _setting.get(
    SettingBoxKey.themeMode,
    defaultValue: 2, // ThemeType.system
  );

  /// 0=light 1=dark 2=system
  static int get themeType => _themeTypeInt;

  static ThemeMode get themeMode => switch (_themeTypeInt) {
    0 => ThemeMode.light,
    1 => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Phase 7.1：UI 风格（ios / material3 / miuix）。
  /// 持久化在 [SettingBoxKey.uiStyle]，默认 iOS 风格。
  static UiStyle get uiStyle => UiStyle.fromLegacyInt(
        _setting.get(SettingBoxKey.uiStyle, defaultValue: 0) as int,
      );

  static double get defaultTextScale =>
      _setting.get(SettingBoxKey.defaultTextScale, defaultValue: 1.0);

  static bool get dynamicColor =>
      !Platform.isIOS &&
      _setting.get(SettingBoxKey.dynamicColor, defaultValue: true);

  static int get customColor =>
      _setting.get(SettingBoxKey.customColor, defaultValue: 0);

  // ---------- onboarding ----------
  /// 用户协议是否已确认（版本化 key，默认 false 使新/老用户首次启动都会弹门禁）。
  static bool get userAgreementAck =>
      _setting.get(SettingBoxKey.userAgreementAckV1, defaultValue: false);

  static Future<void> setUserAgreementAck(bool value) =>
      _setting.put(SettingBoxKey.userAgreementAckV1, value);

  // ---------- network ----------
  static bool get enableHttp2 =>
      _setting.get(SettingBoxKey.enableHttp2, defaultValue: false);

  static int get retryCount =>
      _setting.get(SettingBoxKey.retryCount, defaultValue: 2);

  static int get retryDelay =>
      _setting.get(SettingBoxKey.retryDelay, defaultValue: 500);

  static bool get enableSystemProxy =>
      _setting.get(SettingBoxKey.enableSystemProxy, defaultValue: false);

  static String get systemProxyHost =>
      _setting.get(SettingBoxKey.systemProxyHost, defaultValue: '');

  static String get systemProxyPort =>
      _setting.get(SettingBoxKey.systemProxyPort, defaultValue: '');

  static bool get badCertificateCallback =>
      _setting.get(SettingBoxKey.badCertificateCallback, defaultValue: false);

  // ---------- player ----------
  static int get defaultVideoQa =>
      _setting.get(SettingBoxKey.defaultVideoQa, defaultValue: 127); // 8K

  /// 持久化默认画质偏好（switchQuality 后写入）。
  static set defaultVideoQa(int value) =>
      _setting.put(SettingBoxKey.defaultVideoQa, value);

  static int get defaultVideoQaCellular =>
      _setting.get(SettingBoxKey.defaultVideoQaCellular, defaultValue: 80);

  static int get defaultAudioQa =>
      _setting.get(SettingBoxKey.defaultAudioQa, defaultValue: 30251); // Hi-Res

  static int get defaultAudioQaCellular =>
      _setting.get(SettingBoxKey.defaultAudioQaCellular, defaultValue: 30216);

  static String get hardwareDecoding => _setting.get(
    SettingBoxKey.hardwareDecoding,
    defaultValue: Platform.isAndroid ? 'auto-copy' : 'auto',
  );

  static String get videoSync =>
      _setting.get(SettingBoxKey.videoSync, defaultValue: 'display-resample');

  static String get autosync => _setting.get(
    SettingBoxKey.autosync,
    defaultValue: Platform.isAndroid ? '30' : '0',
  );

  static double get bufferSize =>
      _setting.get(SettingBoxKey.bufferSize, defaultValue: 4.0);

  static double get bufferSec =>
      _setting.get(SettingBoxKey.bufferSec, defaultValue: 16.0);

  static Map<String, String> initBuffer([double playbackSpeed = 1.0]) {
    final bufSec = Pref.bufferSec * playbackSpeed;
    final bufSiz = (Pref.bufferSize * 0x100000).toStringAsFixed(0);
    return {
      'cache': 'yes',
      'cache-secs': bufSec.toStringAsFixed(3),
      'demuxer-hysteresis-secs': (bufSec / 1.5).toStringAsFixed(3),
      'demuxer-max-bytes': bufSiz,
      'demuxer-max-back-bytes': bufSiz,
    };
  }

  static Map<String, String> initLiveBuffer() {
    return {
      'cache': 'yes',
      'demuxer-max-bytes': (Pref.bufferSize * 0x200000).toStringAsFixed(0),
      'demuxer-max-back-bytes': '0',
    };
  }

  static CDNService get defaultCDNService {
    if (_setting.get(SettingBoxKey.CDNService) case final String cdnName) {
      try {
        return CDNService.values.byName(cdnName);
      } catch (_) {}
    }
    return CDNService.backupUrl;
  }

  static set defaultCDNService(CDNService service) {
    _setting.put(SettingBoxKey.CDNService, service.name);
  }

  static bool get disableAudioCDN =>
      _setting.get(SettingBoxKey.disableAudioCDN, defaultValue: false);

  static double get playSpeedDefault =>
      _video.get(VideoBoxKey.playSpeedDefault, defaultValue: 1.0);

  static double get longPressSpeedDefault =>
      _video.get(VideoBoxKey.longPressSpeedDefault, defaultValue: 3.0);

  static List<double> get speedList => List<double>.from(
    _video.get(
      VideoBoxKey.speedsList,
      defaultValue: const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0],
    ),
  );

  static bool get autoPlayEnable =>
      _setting.get(SettingBoxKey.autoPlayEnable, defaultValue: false);

  /// 是否启用自动 1080P（非 VIP 用户尝试请求 1080P）。
  /// 对应 SettingBoxKey.p1080，默认关闭。
  static bool get auto1080pEnabled =>
      _setting.get(SettingBoxKey.p1080, defaultValue: false);

  /// 是否启用自动最高画质（VIP 用户优先请求 HDR/4K/8K）。
  /// 当 defaultVideoQa >= 125（HDR 及以上）时视为开启。
  static bool get autoHighestQuality => defaultVideoQa >= 125;

  static bool get enableHA =>
      _setting.get(SettingBoxKey.enableHA, defaultValue: true);

  static bool get enableOnlineTotal =>
      _setting.get(SettingBoxKey.enableOnlineTotal, defaultValue: false);

  static bool get autoEnterFullScreen =>
      _setting.get(SettingBoxKey.enableAutoEnter, defaultValue: false);

  static bool get autoExitFullscreen =>
      _setting.get(SettingBoxKey.enableAutoExit, defaultValue: true);

  static bool get enableBackgroundPlay =>
      _setting.get(SettingBoxKey.enableBackgroundPlay, defaultValue: true);

  /// 播放器折叠（pin）时自动暂停；展开仅恢复本次被自动暂停的播放。
  static bool get collapseAutoPause =>
      _setting.get(SettingBoxKey.collapseAutoPause, defaultValue: true);

  // ---------- danmaku ----------
  static bool get enableShowDanmaku =>
      _setting.get(SettingBoxKey.enableShowDanmaku, defaultValue: true);

  static bool get enableShowLiveDanmaku =>
      _setting.get(SettingBoxKey.enableShowLiveDanmaku, defaultValue: true);

  static double get danmakuOpacity =>
      _setting.get(SettingBoxKey.danmakuOpacity, defaultValue: 1.0);

  static double get danmakuFontScale => _setting.get(
    SettingBoxKey.danmakuFontScale,
    defaultValue: 1.4,
  );

  static double get danmakuFontScaleFS =>
      _setting.get(SettingBoxKey.danmakuFontScaleFS, defaultValue: 1.7);

  static double get danmakuDuration =>
      _setting.get(SettingBoxKey.danmakuDuration, defaultValue: 7.0);

  static Set<int> get danmakuBlockType => Set<int>.from(
    _setting.get(SettingBoxKey.danmakuBlockType, defaultValue: const <int>{}),
  );

  static double get danmakuLineHeight =>
      _setting.get(SettingBoxKey.danmakuLineHeight, defaultValue: 1.6);

  static double get danmakuStrokeWidth =>
      _setting.get(SettingBoxKey.danmakuStrokeWidth, defaultValue: 2.5);

  static int get danmakuFontWeight =>
      _setting.get(SettingBoxKey.danmakuFontWeight, defaultValue: 6);

  /// 智能云屏蔽等级（0-11），权重低于该值的弹幕在渲染前被丢弃。
  static int get danmakuWeight =>
      _setting.get(SettingBoxKey.danmakuWeight, defaultValue: 0);

  /// 弹幕显示区域占视频高度比例（0.1-1.0）。
  static double get danmakuShowArea =>
      _setting.get(SettingBoxKey.danmakuShowArea, defaultValue: 1.0);

  /// 静态（顶部/底部）弹幕停留时长，秒。
  static double get danmakuStaticDuration =>
      _setting.get(SettingBoxKey.danmakuStaticDuration, defaultValue: 4.0);

  /// 海量弹幕模式：轨道占满时叠加显示。
  static bool get danmakuMassiveMode =>
      _setting.get(SettingBoxKey.danmakuMassiveMode, defaultValue: false);

  /// 滚动弹幕固定速度（不随内容长度变化）。
  static bool get danmakuFixedV =>
      _setting.get(SettingBoxKey.danmakuFixedV, defaultValue: false);

  /// 静态弹幕溢出时降级为滚动弹幕。
  static bool get danmakuStatic2Scroll =>
      _setting.get(SettingBoxKey.danmakuStatic2Scroll, defaultValue: false);

  /// 屏蔽彩色弹幕（强制为白色）。
  ///
  /// 约定：[danmakuBlockType] 集合包含 6 时视为屏蔽彩色。
  static bool get blockColorful => danmakuBlockType.contains(6);

  /// 弹幕过滤规则（关键词/正则/用户），持久化在 localCache box。
  static dynamic get danmakuFilterRule =>
      _localCache.get(LocalCacheKey.danmakuFilterRules);

  static set danmakuFilterRule(dynamic value) =>
      _localCache.put(LocalCacheKey.danmakuFilterRules, value);

  // ---------- subtitle ----------
  /// 字幕是否开启（用户手动开关，记忆上次状态）。
  static bool get subtitleEnabled =>
      _setting.get(SettingBoxKey.subtitleEnabled, defaultValue: true);

  static set subtitleEnabled(bool value) =>
      _setting.put(SettingBoxKey.subtitleEnabled, value);

  static double get subtitleFontScale =>
      _setting.get(SettingBoxKey.subtitleFontScale, defaultValue: 1.0);

  static double get subtitleFontScaleFS =>
      _setting.get(SettingBoxKey.subtitleFontScaleFS, defaultValue: 1.5);

  static double get subtitleBgOpacity =>
      _setting.get(SettingBoxKey.subtitleBgOpacity, defaultValue: 0.67);

  static double get subtitleStrokeWidth =>
      _setting.get(SettingBoxKey.subtitleStrokeWidth, defaultValue: 2.0);

  static int get subtitlePaddingH =>
      _setting.get(SettingBoxKey.subtitlePaddingH, defaultValue: 24);

  static int get subtitlePaddingB =>
      _setting.get(SettingBoxKey.subtitlePaddingB, defaultValue: 24);

  static int get subtitleFontWeight =>
      _setting.get(SettingBoxKey.subtitleFontWeight, defaultValue: 5);

  // ---------- sponsorblock ----------
  static bool get enableSponsorBlock =>
      _setting.get(SettingBoxKey.enableSponsorBlock, defaultValue: true);

  // ---------- audio / volume ----------
  static double get desktopVolume =>
      (_setting.get(SettingBoxKey.desktopVolume, defaultValue: 100.0) as num)
          .toDouble();

  static set desktopVolume(double val) =>
      _setting.put(SettingBoxKey.desktopVolume, val);

  static double get maxVolume =>
      (_setting.get(SettingBoxKey.maxVolume, defaultValue: 200.0) as num)
          .toDouble();

  static set maxVolume(double val) =>
      _setting.put(SettingBoxKey.maxVolume, val);

  /// 音频归一化配置：'0'=禁用, '1'=dynaudnorm, '2'=loudnorm (默认)
  static String get audioNormalization =>
      _setting.get(SettingBoxKey.audioNormalization, defaultValue: '2');

  static set audioNormalization(String val) =>
      _setting.put(SettingBoxKey.audioNormalization, val);

  static String get fallbackNormalization =>
      _setting.get(SettingBoxKey.fallbackNormalization, defaultValue: '2');

  static set fallbackNormalization(String val) =>
      _setting.put(SettingBoxKey.fallbackNormalization, val);

  static bool get enableAudioNormalize =>
      _setting.get(SettingBoxKey.enableAudioNormalize, defaultValue: true);

  static set enableAudioNormalize(bool val) =>
      _setting.put(SettingBoxKey.enableAudioNormalize, val);

  // ---------- essential / recommend ----------
  static String get banWordForRecommend =>
      _setting.get(SettingBoxKey.banWordForRecommend, defaultValue: '');

  static String get banWordForReply =>
      _setting.get(SettingBoxKey.banWordForReply, defaultValue: '');

  static String get banWordForZone =>
      _setting.get(SettingBoxKey.banWordForZone, defaultValue: '');

  static String get banWordForDyn =>
      _setting.get(SettingBoxKey.banWordForDyn, defaultValue: '');

  static bool get appRcmd =>
      _setting.get(SettingBoxKey.appRcmd, defaultValue: true);

  static bool get enableLog =>
      _setting.get(SettingBoxKey.enableLog, defaultValue: true);

  static Set<int> get blackMids =>
      _localCache.get(LocalCacheKey.blackMids, defaultValue: <int>{});

  static set blackMids(Set<int> blackMidsSet) =>
      _localCache.put(LocalCacheKey.blackMids, blackMidsSet);

  static bool get historyPause =>
      _localCache.get(LocalCacheKey.historyPause, defaultValue: false);

  // ---------- live quality ----------
  static int get liveQuality =>
      _setting.get(SettingBoxKey.liveQuality, defaultValue: 10000);

  static int get liveQualityCellular =>
      _setting.get(SettingBoxKey.liveQualityCellular, defaultValue: 150);

  // ---------- misc ----------
  static int get picQuality =>
      _setting.get(SettingBoxKey.defaultPicQa, defaultValue: 10);

  static bool get showVipDanmaku =>
      _setting.get(SettingBoxKey.showVipDanmaku, defaultValue: true);

  static bool get mergeDanmaku =>
      _setting.get(SettingBoxKey.mergeDanmaku, defaultValue: false);

  static bool get directExitOnBack =>
      _setting.get(SettingBoxKey.directExitOnBack, defaultValue: false);

  static bool get horizontalScreen {
    bool? horizontalScreen = _setting.get(SettingBoxKey.horizontalScreen);
    if (horizontalScreen == null) {
      _setting.put(SettingBoxKey.horizontalScreen, false);
      return false;
    }
    return horizontalScreen;
  }

  static bool get enableSystemBrightness =>
      _setting.get(SettingBoxKey.setSystemBrightness, defaultValue: false);

  static bool get enableShrinkVideoSize =>
      _setting.get(SettingBoxKey.enableShrinkVideoSize, defaultValue: true);

  // ---------- global-data ----------
  static bool get showMedal =>
      _setting.get(SettingBoxKey.showMedal, defaultValue: true);

  static bool get dynamicsWaterfallFlow => _setting.get(
    SettingBoxKey.dynamicsWaterfallFlow,
    defaultValue: horizontalScreen,
  );

  // ---------- buvid ----------
  static String get buvid {
    String? buvid = _localCache.get(LocalCacheKey.buvid);
    if (buvid == null) {
      buvid = LoginUtils.generateBuvid();
      _localCache.put(LocalCacheKey.buvid, buvid);
    }
    return buvid;
  }

  // ---------- userInfoCache（加密持久化） ----------
  /// 读取缓存的用户信息（解密后反序列化）。无缓存返回 null。
  static UserInfoModel? get userInfoCache {
    final raw = _localCache.get(LocalCacheKey.userInfoCache) as String?;
    if (raw == null || raw.isEmpty) return null;
    final json = CredentialCrypto.decrypt(raw);
    if (json.isEmpty) return null;
    try {
      return UserInfoModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 写入用户信息（加密后持久化）。
  static set userInfoCache(UserInfoModel? info) {
    if (info == null) {
      _localCache.delete(LocalCacheKey.userInfoCache);
      return;
    }
    final json = jsonEncode(info.toJson());
    _localCache.put(LocalCacheKey.userInfoCache, CredentialCrypto.encrypt(json));
  }

  // ---------- bangumi ----------
  static final ValueNotifier<bool> bangumiEpisodesDescending = ValueNotifier<bool>(
    _setting.get(SettingBoxKey.bangumiEpisodesDescending, defaultValue: false) as bool,
  );

  static void setBangumiEpisodesDescending(bool value) {
    if (bangumiEpisodesDescending.value != value) {
      bangumiEpisodesDescending.value = value;
    }
    _setting.put(SettingBoxKey.bangumiEpisodesDescending, value);
  }

  // ---------- desktop ----------
  static bool get showWindowTitleBar =>
      _setting.get(SettingBoxKey.showWindowTitleBar, defaultValue: true) as bool;
}

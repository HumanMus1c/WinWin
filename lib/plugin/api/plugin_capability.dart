/// 插件能力声明（移植自 BiliPai `plugin-sdk/PluginCapabilityManifest.kt`）。
///
/// 能力清单只用于「安装前告知 / 详情页展示 / 启用前授权确认」，
/// 不参与运行时权限校验——WinWin 不执行外部代码，声明式插件不存在越权面。
enum PluginCapability {
  playerState('PLAYER_STATE', '播放器状态'),
  playerControl('PLAYER_CONTROL', '播放器控制'),
  danmakuStream('DANMAKU_STREAM', '弹幕流'),
  danmakuMutation('DANMAKU_MUTATION', '弹幕改写'),
  playbackCdn('PLAYBACK_CDN', '播放 CDN'),
  recommendationCandidates('RECOMMENDATION_CANDIDATES', '推荐候选'),
  localHistoryRead('LOCAL_HISTORY_READ', '读取本地历史'),
  localFeedbackRead('LOCAL_FEEDBACK_READ', '读取本地反馈'),
  network('NETWORK', '网络访问'),
  pluginStorage('PLUGIN_STORAGE', '插件存储'),
  externalMediaPlayback('EXTERNAL_MEDIA_PLAYBACK', '外部媒体播放'),
  feedSource('FEED_SOURCE', '内容源');

  const PluginCapability(this.wireName, this.label);

  /// JSON 插件包中使用的全大写名称。
  final String wireName;

  /// 中文展示名。
  final String label;

  static PluginCapability? fromWireName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final capability in values) {
      if (capability.wireName == name) return capability;
    }
    return null;
  }
}

/// 插件能力清单（对应 BiliPai `PluginCapabilityManifest`）。
class PluginCapabilityManifest {
  const PluginCapabilityManifest({
    required this.pluginId,
    required this.displayName,
    required this.version,
    required this.entryPoint,
    required this.capabilities,
    this.apiVersion = 1,
  });

  final String pluginId;
  final String displayName;
  final String version;

  /// 内置插件为 Dart 类名；规则插件为 `json:<id>`。
  final String entryPoint;

  final Set<PluginCapability> capabilities;
  final int apiVersion;

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'displayName': displayName,
        'version': version,
        'apiVersion': apiVersion,
        'entryPoint': entryPoint,
        'capabilities': [
          for (final capability in capabilities) capability.wireName,
        ],
      };
}

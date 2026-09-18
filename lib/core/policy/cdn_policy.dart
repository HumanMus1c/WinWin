// Ported & enhanced from PiliPlus VideoUtils & BiliPai CdnOptimizationPolicy
// 负责 B 站视频/番剧音视频流的 CDN 智能优选与 MCDN 矿渣节点过滤。

import 'package:flutter/foundation.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/common/cdn_type.dart';

export 'package:winwin/models/common/cdn_type.dart';

/// CDN 优选与防频繁缓冲策略。
abstract final class CdnPolicy {
  static const _proxyTf = 'proxy-tf-all-ws.bilivideo.com';

  /// 官方 UPOS 镜像域名匹配规则（不含 302 重定向域）。
  static final _mirrorRegex = RegExp(
    r'^https?://(?:upos-\w+-(?!302)\w+|(?:upos|proxy)-tf-[^/]+)\.(?:bilivideo|akamaized)\.(?:com|net)/upgcxcode',
  );

  /// MCDN TF 接口规则。
  static final _mCdnTfRegex = RegExp(
    r'^https?://(?:(?:(?:\d{1,3}\.){3}\d{1,3}|[^/]+\.mcdn\.bilivideo\.(?:com|cn|net))(?:\:\d{1,5})?/v\d/resource)',
  );

  /// 纯 IP 匹配正则。
  static final _ipRegex = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

  /// 判断一个 URL 是否属于高风险或不稳定的 MCDN / PCDN 节点。
  static bool isMcdn(String url) {
    try {
      final uri = Uri.parse(url);
      return isMcdnUri(uri);
    } catch (_) {
      return false;
    }
  }

  /// 判断一个 [Uri] 是否属于 MCDN 节点。
  static bool isMcdnUri(Uri uri) {
    final host = uri.host.toLowerCase();
    // 1. 查询参数显式标明 os=mcdn 或含 mcdnid
    if (uri.queryParameters['os'] == 'mcdn' ||
        uri.queryParameters.containsKey('mcdnid')) {
      return true;
    }
    // 2. 域名包含 MCDN 特征（如 edge.mountaintoys.cn、*.mcdn.bilivideo.* 等）
    if (host.contains('mcdn') ||
        host.contains('pcdn') ||
        host.contains('mountaintoys.cn') ||
        host.contains('gotcha') ||
        _ipRegex.hasMatch(host)) {
      return true;
    }
    // 3. 非标端口（B 站官方 UPOS 均在 80/443 标准端口，MCDN 常用 4483/4484 等）
    if (uri.hasPort && uri.port != 80 && uri.port != 443) {
      return true;
    }
    return false;
  }

  /// 从给定的候选音视频 URL 列表中，结合用户 CDN 偏好与 MCDN 规避策略，
  /// 解析出最稳定、速度最优的所有可用播放 URL 候选列表（去重且按优质官方节点优先排序）。
  ///
  /// [urls]：通常为 `video.playUrls` 或 `audio.playUrls`（包含 baseUrl 及全部 backupUrl）。
  /// [service]：用户指定的 CDN偏好，若为 null 则读取 [Pref.defaultCDNService]。
  /// [isAudio]：是否为音频轨（若开启 [Pref.disableAudioCDN] 则不改写音频宿主）。
  static List<String> resolveAllUrls(
    Iterable<String> urls, {
    CDNService? service,
    bool isAudio = false,
  }) {
    if (urls.isEmpty) return const [];
    service ??= Pref.defaultCDNService;

    // 若用户显式选择 baseUrl，直通原样返回列表
    if (service == CDNService.baseUrl) {
      return urls.where((u) => u.isNotEmpty).toList();
    }

    final result = <String>[];
    final seen = <String>{};

    void addCandidate(String candidate) {
      if (candidate.isNotEmpty && seen.add(candidate)) {
        result.add(candidate);
      }
    }

    String? mcdnTf;
    String? mcdnUpgcxcode;
    String last = '';

    for (final url in urls) {
      if (url.isEmpty) continue;
      last = url;

      final Uri uri;
      try {
        uri = Uri.parse(url);
      } catch (_) {
        continue;
      }

      final isMcdnNode = isMcdnUri(uri);

      // 1. 匹配官方 UPOS 镜像
      if (_mirrorRegex.hasMatch(url)) {
        if (isMcdnNode) {
          // 极少数情况下官方镜像后缀带 os=mcdn，记下路径备用，继续寻找更干净的镜像
          mcdnUpgcxcode ??= url;
          continue;
        }

        // 命中纯净的官方镜像
        if (service == CDNService.backupUrl ||
            (isAudio && Pref.disableAudioCDN)) {
          addCandidate(url);
          continue;
        }

        // 用户指定了特定服务商 Host，替换并重置端口为 443（首选候选）
        final targetHost = service.host ?? CDNService.ali.host!;
        addCandidate(
          uri.replace(scheme: 'https', host: targetHost, port: 443).toString(),
        );
        // 同时注入对等高质量备选 UPOS 镜像与原始链接，为流卡死自愈提供完备的多 CDN 容灾候选
        final altHost = targetHost == CDNService.ali.host
            ? CDNService.cos.host!
            : CDNService.ali.host!;
        addCandidate(
          uri.replace(scheme: 'https', host: altHost, port: 443).toString(),
        );
        addCandidate(url);
        continue;
      }

      // 2. 匹配 MCDN TF 规则
      if (_mCdnTfRegex.hasMatch(url)) {
        mcdnTf ??= url;
        continue;
      }

      // 3. 记录包含 /upgcxcode/ 的备用链接（如来自 MCDN 节点的链接）
      if (url.contains('/upgcxcode/')) {
        if (isMcdnNode) {
          mcdnUpgcxcode ??= url;
          continue;
        }
        // 非 MCDN 但包含 /upgcxcode/（可能为 302 域或海外节点）
        if (service == CDNService.backupUrl) {
          addCandidate(url);
        } else {
          final targetHost = service.host ?? CDNService.ali.host!;
          addCandidate(
            uri.replace(scheme: 'https', host: targetHost, port: 443).toString(),
          );
          final altHost = targetHost == CDNService.ali.host
              ? CDNService.cos.host!
              : CDNService.ali.host!;
          addCandidate(
            uri.replace(scheme: 'https', host: altHost, port: 443).toString(),
          );
          addCandidate(url);
        }
        continue;
      }

      // 4. 百度云旧节点兜底
      if (url.contains('szbdyd.com')) {
        final hostname =
            uri.queryParameters['xy_usource'] ?? (service.host ?? CDNService.ali.host!);
        addCandidate(
          uri.replace(scheme: 'https', host: hostname, port: 443).toString(),
        );
        continue;
      }

      if (kDebugMode) {
        debugPrint('[CdnPolicy] Unknown CDN format: $url');
      }
    }

    // 若循环结束未命中纯净镜像：
    // 如果存在 /upgcxcode/（哪怕是 MCDN 返回的），重定向至官方镜像（默认阿里云 443 端口）彻底逃生
    if (result.isEmpty && mcdnUpgcxcode != null) {
      final targetHost = service.host ?? CDNService.ali.host!;
      try {
        final escaped = Uri.parse(mcdnUpgcxcode)
            .replace(scheme: 'https', host: targetHost, port: 443)
            .toString();
        addCandidate(escaped);
      } catch (_) {}
    }

    // 若存在 mcdnTf，经 proxy-tf-all-ws 转发
    if (result.isEmpty && mcdnTf != null) {
      addCandidate(
        Uri(
          scheme: 'https',
          host: _proxyTf,
          queryParameters: {'url': mcdnTf},
        ).toString(),
      );
    }

    if (result.isEmpty && last.isNotEmpty) {
      addCandidate(last);
    }

    return result;
  }

  /// 从给定的候选音视频 URL 列表中，结合用户 CDN 偏好与 MCDN 规避策略，
  /// 解析出首选播放 URL。
  ///
  /// [urls]：通常为 `video.playUrls` 或 `audio.playUrls`（包含 baseUrl 及全部 backupUrl）。
  /// [service]：用户指定的 CDN偏好，若为 null 则读取 [Pref.defaultCDNService]。
  /// [isAudio]：是否为音频轨（若开启 [Pref.disableAudioCDN] 则不改写音频宿主）。
  static String resolveUrl(
    Iterable<String> urls, {
    CDNService? service,
    bool isAudio = false,
  }) {
    final all = resolveAllUrls(urls, service: service, isAudio: isAudio);
    return all.isNotEmpty ? all.first : '';
  }
}

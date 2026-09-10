import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/policy/cdn_policy.dart';

void main() {
  group('CdnPolicy.isMcdn', () {
    test('正确识别真实日志中 mountaintoys MCDN 节点 (带 4483 端口及 os=mcdn)', () {
      const url =
          'https://qmvr62x.edge.mountaintoys.cn:4483/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123&os=mcdn&mcdnid=50061388';
      expect(CdnPolicy.isMcdn(url), isTrue);
    });

    test('正确识别带 os=mcdn 或 mcdnid 的 bilivideo 节点', () {
      const url =
          'https://upos-sz-mirrorcoso1.bilivideo.com/upgcxcode/44/07/213506144.m4s?e=123&os=mcdn';
      expect(CdnPolicy.isMcdn(url), isTrue);
    });

    test('正确识别非标端口 P2P 节点', () {
      const url =
          'https://upos-sz-mirrorali.bilivideo.com:4483/upgcxcode/44/07/213506144.m4s?e=123';
      expect(CdnPolicy.isMcdn(url), isTrue);
    });

    test('正确识别直接 IP 形式的 P2P 矿渣节点', () {
      const url =
          'http://112.29.155.23:4483/v1/resource/44/07/213506144.m4s?e=123';
      expect(CdnPolicy.isMcdn(url), isTrue);
    });

    test('识别官方纯净 UPOS 镜像为非 MCDN', () {
      const aliUrl =
          'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';
      const cosUrl =
          'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';
      const hwUrl =
          'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';
      expect(CdnPolicy.isMcdn(aliUrl), isFalse);
      expect(CdnPolicy.isMcdn(cosUrl), isFalse);
      expect(CdnPolicy.isMcdn(hwUrl), isFalse);
    });
  });

  group('CdnPolicy.resolveUrl', () {
    const mcdnUrl =
        'https://qmvr62x.edge.mountaintoys.cn:4483/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123&os=mcdn&mcdnid=50061388';
    const officialCosUrl =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';
    const officialAliUrl =
        'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';

    test('默认 backupUrl 模式下，自动过滤 baseUrl 中的 MCDN 并选用官方 backupUrl', () {
      final candidates = [mcdnUrl, officialCosUrl];
      final resolved = CdnPolicy.resolveUrl(candidates, service: CDNService.backupUrl);
      expect(resolved, equals(officialCosUrl));
    });

    test('全为 MCDN 矿渣节点时，自动通过官方阿里云 UPOS 镜像逃生并重置 443 端口', () {
      final candidates = [mcdnUrl];
      final resolved = CdnPolicy.resolveUrl(candidates, service: CDNService.backupUrl);
      final uri = Uri.parse(resolved);
      expect(uri.host, equals('upos-sz-mirrorali.bilivideo.com'));
      expect(uri.port, equals(443));
      expect(uri.path, contains('/upgcxcode/44/07/213506144/'));
      expect(uri.queryParameters['os'], equals('mcdn'));
    });

    test('指定阿里云服务时，改写 Host 并保持端口 443', () {
      final candidates = [officialCosUrl];
      final resolved = CdnPolicy.resolveUrl(candidates, service: CDNService.ali);
      final uri = Uri.parse(resolved);
      expect(uri.host, equals('upos-sz-mirrorali.bilivideo.com'));
      expect(uri.port, equals(443));
    });

    test('指定腾讯云服务时，改写 Host 并保持端口 443', () {
      final candidates = [officialAliUrl];
      final resolved = CdnPolicy.resolveUrl(candidates, service: CDNService.cos);
      final uri = Uri.parse(resolved);
      expect(uri.host, equals('upos-sz-mirrorcos.bilivideo.com'));
      expect(uri.port, equals(443));
    });

    test('显式选择 baseUrl 模式时，原样直通返回首个 URL', () {
      final candidates = [mcdnUrl, officialCosUrl];
      final resolved = CdnPolicy.resolveUrl(candidates, service: CDNService.baseUrl);
      expect(resolved, equals(mcdnUrl));
    });
  });

  group('CdnPolicy.resolveAllUrls', () {
    const mcdnUrl =
        'https://qmvr62x.edge.mountaintoys.cn:4483/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123&os=mcdn&mcdnid=50061388';
    const officialCosUrl =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';
    const officialAliUrl =
        'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';
    const officialHwUrl =
        'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/44/07/213506144/213506144-1-30080.m4s?e=123';

    test('过滤 MCDN 并返回所有纯净官方候选节点，去重并保持顺序', () {
      final candidates = [
        mcdnUrl,
        officialCosUrl,
        officialAliUrl,
        officialCosUrl, // 重复项
        officialHwUrl,
      ];
      final resolved = CdnPolicy.resolveAllUrls(
        candidates,
        service: CDNService.backupUrl,
      );
      expect(resolved.length, equals(3));
      expect(resolved[0], equals(officialCosUrl));
      expect(resolved[1], equals(officialAliUrl));
      expect(resolved[2], equals(officialHwUrl));
    });

    test('全为 MCDN 时，至少逃生返回一个纯净官方镜像候选', () {
      final candidates = [mcdnUrl];
      final resolved = CdnPolicy.resolveAllUrls(
        candidates,
        service: CDNService.backupUrl,
      );
      expect(resolved.length, equals(1));
      final uri = Uri.parse(resolved.first);
      expect(uri.host, equals('upos-sz-mirrorali.bilivideo.com'));
      expect(uri.port, equals(443));
    });
  });
}


// ignore_for_file: constant_identifier_names

/// 可用的 B 站 CDN 服务商类型。
enum CDNService {
  backupUrl('备用URL（推荐，自动过滤MCDN）'),
  ali('ali（阿里云，推荐国内极速）', 'upos-sz-mirrorali.bilivideo.com'),
  alib('alib（阿里云，VOD加速）', 'upos-sz-mirroralib.bilivideo.com'),
  alio1('alio1（阿里云海外）', 'upos-sz-mirroralio1.bilivideo.com'),
  cos('cos（腾讯云）', 'upos-sz-mirrorcos.bilivideo.com'),
  cosb('cosb（腾讯云，VOD加速）', 'upos-sz-mirrorcosb.bilivideo.com'),
  coso1('coso1（腾讯云海外）', 'upos-sz-mirrorcoso1.bilivideo.com'),
  hw('hw（华为云）', 'upos-sz-mirrorhw.bilivideo.com'),
  hwb('hwb（华为云，VOD加速）', 'upos-sz-mirrorhwb.bilivideo.com'),
  hw_08c('08c（华为云，融合CDN）', 'upos-sz-mirror08c.bilivideo.com'),
  hw_08h('08h（华为云，融合CDN）', 'upos-sz-mirror08h.bilivideo.com'),
  hw_08ct('08ct（华为云，融合CDN）', 'upos-sz-mirror08ct.bilivideo.com'),
  tf_hw('tf_hw（华为云）', 'upos-tf-all-hw.bilivideo.com'),
  tf_tx('tf_tx（腾讯云）', 'upos-tf-all-tx.bilivideo.com'),
  akamai('akamai（Akamai海外）', 'upos-hz-mirrorakam.akamaized.net'),
  baseUrl('基础URL（不推荐，含P2P/MCDN）'),
  ;

  const CDNService(this.desc, [this.host]);

  final String desc;
  final String? host;
}

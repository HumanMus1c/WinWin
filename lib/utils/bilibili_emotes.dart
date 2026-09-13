/// 哔哩哔哩官方常用表情对照表与解析工具。
///
/// 覆盖官方全套高频表情 CDN 直链，支持将直播间互动文本中的 `[xxx]` 标识
/// 精确转换为对应的 WebP/PNG 图标。
abstract final class BilibiliEmotes {
  /// 官方默认高频表情映射表（键包含中括号，如 `[doge]`）。
  static const Map<String, String> defaultEmotes = {
    '[doge]': 'https://i0.hdslb.com/bfs/emote/3087d273a78ccaff4bb1e9972e2ba2a7583c9f11.png',
    '[dog]': 'https://i0.hdslb.com/bfs/emote/3087d273a78ccaff4bb1e9972e2ba2a7583c9f11.png',
    '[笑哭]': 'https://i0.hdslb.com/bfs/emote/c3043ba94babf824dea03ce500d0e73763bf4f40.png',
    '[妙啊]': 'https://i0.hdslb.com/bfs/emote/b4cb77159d58614a9b787b91b1cd22a81f383535.png',
    '[点赞]': 'https://i0.hdslb.com/bfs/emote/1a67265993913f4c35d15a6028a30724e83e7d35.png',
    '[星星眼]': 'https://i0.hdslb.com/bfs/emote/63c9d1a31c0da745b61cdb35e0ecb28635675db2.png',
    '[微笑]': 'https://i0.hdslb.com/bfs/emote/685612eadc33f6bc233776c6241813385844f182.png',
    '[吃瓜]': 'https://i0.hdslb.com/bfs/emote/4191ce3c44c2b3df8fd97c33f85d3ab15f4f3c84.png',
    '[打call]': 'https://i0.hdslb.com/bfs/emote/431432c43da3ee5aab5b0e4f8931953e649e9975.png',
    '[OK]': 'https://i0.hdslb.com/bfs/emote/4683fd9ffc925fa6423110979d7dcac5eda297f4.png',
    '[大哭]': 'https://i0.hdslb.com/bfs/emote/2caafee2e5db4db72104650d87810cc2c123fc86.png',
    '[辣眼睛]': 'https://i0.hdslb.com/bfs/emote/35d62c496d1e4ea9e091243fa812866f5fecc101.png',
    '[滑稽]': 'https://i0.hdslb.com/bfs/emote/d15121545a99ac46774f1f4465b895fe2d1411c3.png',
    '[喜极而泣]': 'https://i0.hdslb.com/bfs/emote/485a7e0c01c2d70707daae53bee4a9e2e31ef1ed.png',
    '[呲牙]': 'https://i0.hdslb.com/bfs/emote/b5a5898491944a4268360f2e7a84623149672eb6.png',
    '[歪嘴]': 'https://i0.hdslb.com/bfs/emote/4384050fbab0586259acdd170b510fe262f08a17.png',
    '[调皮]': 'https://i0.hdslb.com/bfs/emote/8290b7308325e3179d2154327c85640af1528617.png',
    '[嗑瓜子]': 'https://i0.hdslb.com/bfs/emote/28a91da1685d90124cfeead74622e1ebb417c0eb.png',
    '[藏狐]': 'https://i0.hdslb.com/bfs/emote/ba0937ef6f3ccca85e2e0047e6263f3b4da37201.png',
    '[脱单doge]': 'https://i0.hdslb.com/bfs/emote/bf7e00ecab02171f8461ee8cf439c73db9797748.png',
    '[笑]': 'https://i0.hdslb.com/bfs/emote/81edf17314cea3b48674312b4364df44d5c01f17.png',
    '[给心心]': 'https://i0.hdslb.com/bfs/emote/1597302b98827463f5b75c7cac1f29ea6ce572c4.png',
    '[比心]': 'https://i0.hdslb.com/bfs/emote/1597302b98827463f5b75c7cac1f29ea6ce572c4.png',
    '[脸红]': 'https://i0.hdslb.com/bfs/emote/0922c375da40e6b69002bd89b858572f424dcfca.png',
    '[嘟嘟]': 'https://i0.hdslb.com/bfs/emote/abd7404537d8162720ccbba9e0a8cdf75547e07a.png',
    '[哦呼]': 'https://i0.hdslb.com/bfs/emote/362bded07ea5434886271d23fa25f5d85d8af06c.png',
    '[喜欢]': 'https://i0.hdslb.com/bfs/emote/8a10a4d73a89f665feff3d46ca56e83dc68f9eb8.png',
    '[酸了]': 'https://i0.hdslb.com/bfs/emote/92b1c8cbceea3ae0e8e32253ea414783e8ba7806.png',
    '[害羞]': 'https://i0.hdslb.com/bfs/emote/9d2ec4e1fbd6cb1b4d12d2bbbdd124ccb83ddfda.png',
    '[嫌弃]': 'https://i0.hdslb.com/bfs/emote/de4c0783aaa60ec03de0a2b90858927bfad7154b.png',
    '[疑惑]': 'https://i0.hdslb.com/bfs/emote/b7840db4b1f9f4726b7cb23c0972720c1698d661.png',
    '[偷笑]': 'https://i0.hdslb.com/bfs/emote/6c49d226e76c42cd8002abc47b3112bc5a92f66a.png',
    '[惊讶]': 'https://i0.hdslb.com/bfs/emote/f8e9a59cad52ae1a19622805696a35f0a0d853f3.png',
    '[捂脸]': 'https://i0.hdslb.com/bfs/emote/6921bb43f0c634870b92f4a8ad41dada94a5296d.png',
    '[阴险]': 'https://i0.hdslb.com/bfs/emote/ba8d5f8e7d136d59aab52c40fd3b8a43419eb03c.png',
    '[呆]': 'https://i0.hdslb.com/bfs/emote/33ad6000d9f9f168a0976bc60937786f239e5d8c.png',
    '[抠鼻]': 'https://i0.hdslb.com/bfs/emote/cb89184c97e3f6d50acfd7961c313ce50360d70f.png',
    '[大笑]': 'https://i0.hdslb.com/bfs/emote/ca94ad1c7e6dac895eb5b33b7836b634c614d1c0.png',
    '[惊喜]': 'https://i0.hdslb.com/bfs/emote/0afecaf3a3499479af946f29749e1a6c285b6f65.png',
    '[无语]': 'https://i0.hdslb.com/bfs/emote/44667b7d9349957e903b1b62cb91fb9b13720f04.png',
    '[鼓掌]': 'https://i0.hdslb.com/bfs/emote/895d1fc616b4b6c830cf96012880818c0e1de00d.png',
    '[尴尬]': 'https://i0.hdslb.com/bfs/emote/cb321684ed5ce6eacdc2699092ab8fe7679e4fda.png',
    '[傲娇]': 'https://i0.hdslb.com/bfs/emote/010540d0f61220a0db4922e4a679a1d8eca94f4e.png',
    '[委屈]': 'https://i0.hdslb.com/bfs/emote/d2f26cbdd6c96960320af03f5514c5b524990840.png',
    '[疼]': 'https://i0.hdslb.com/bfs/emote/905fd9a99ec316e353b9bd4ecd49a5f0a301eabf.png',
    '[冷]': 'https://i0.hdslb.com/bfs/emote/cb0ebbd0668640f07ebfc0e03f7a18a8cd00b4ed.png',
    '[热]': 'https://i0.hdslb.com/bfs/emote/4e58a2a6f5f1580ac33df2d2cf7ecad7d9ab3635.png',
    '[生病]': 'https://i0.hdslb.com/bfs/emote/0f25ce04ae1d7baf98650986454c634f6612cb76.png',
    '[生气]': 'https://i0.hdslb.com/bfs/emote/3195714219c4b582a4fb02033dd1519913d0246d.png',
    '[再见]': 'https://i0.hdslb.com/bfs/emote/14b2d6a505b262d4999ab46014e262b9a7008cf3.png',
    '[蹲蹲]': 'https://i0.hdslb.com/bfs/emote/878f1dfac79622050f730d1fee5f7b1a55951c74.png',
    '[保佑]': 'https://i0.hdslb.com/bfs/emote/13db09b531495c64390be107127e974e6efebff6.png',
    '[2333]': 'https://i0.hdslb.com/bfs/emote/a9638c4149fa8a5991873fb2ef4ea42c55db70f6.png',
  };

  /// 常用快捷选择表情列表（用于弹幕输入框表情选择器）。
  static const List<String> popularEmotes = [
    '[doge]',
    '[妙啊]',
    '[点赞]',
    '[打call]',
    '[笑哭]',
    '[星星眼]',
    '[微笑]',
    '[吃瓜]',
    '[滑稽]',
    '[喜极而泣]',
    '[给心心]',
    '[呲牙]',
    '[捂脸]',
    '[酸了]',
    '[大哭]',
    '[OK]',
    '[傲娇]',
    '[害羞]',
    '[偷笑]',
    '[惊讶]',
    '[鼓掌]',
    '[调皮]',
    '[生病]',
    '[委屈]',
    '[生气]',
    '[无语]',
    '[疑惑]',
    '[再见]',
  ];

  /// 查询表情代码对应的 URL。
  ///
  /// 优先使用传入的 [customEmotes]（来自直播 WebSocket extra['emots']），
  /// 若未命中则回退至官方内置对照表 [defaultEmotes]。
  static String? getEmoteUrl(String code, [Map<String, String>? customEmotes]) {
    if (customEmotes != null && customEmotes.containsKey(code)) {
      return customEmotes[code];
    }
    return defaultEmotes[code];
  }

  /// 匹配 `[xxx]` 格式的表情代码。
  static final RegExp emotePattern = RegExp(r'\[[^\]]+\]');
}

// 图标视觉对照生成器（阶段5e-L5 配套工具）
//
// 单一数据源（AppIcons 语义 × 状态）产出：
//  ① docs/icon-sheets/*.png        分节 PNG 拼图（生产同链路实渲染）
//  ② docs/icon-sheets/*.svg        分节 SVG 全真矢量拼图
//  ③ docs/icon-sheets/icons/*.svg  单图标 SVG（现用 + 曾用 Material 双份）
//  ④ docs/icon-sheets/tables/*.md  对照表格（曾用/现用图片并排，供文档嵌入）
//
// 字形轮廓来源（tools/glyph_outline_export.py 预生成，fontTools）：
//   cupertino_glyph_paths.g.dart（回退字形）/ material_glyph_paths.g.dart（曾用）
//
// 运行：flutter test test/tools/icon_sheet_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_icons.dart';

import 'cupertino_glyph_paths.g.dart';
import 'material_glyph_paths.g.dart';

const _outDir = 'docs/icon-sheets';
const _boundaryKey = Key('sheet');
const _iconBoundaryKey = Key('icon');

const _ink = '#111111';
const _labelInk = '#333333';

Future<void> _loadFont(String family, List<String> candidates) async {
  ByteData? data;
  for (final path in candidates) {
    try {
      data = await rootBundle.load(path);
      break;
    } catch (_) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          data = ByteData.view(Uint8List.fromList(bytes).buffer);
          break;
        }
      } catch (_) {}
    }
  }
  if (data == null) return;
  final loader = FontLoader(family)..addFont(Future.value(data));
  await loader.load();
}

class _Cell {
  const _Cell(
    this.label,
    this.glyph, {
    this.old,
    this.usage = '',
    this.glyphText = '',
  });

  final String label;
  final IconData glyph;

  /// 迁移前使用的 Material 字形（L3 前 M3 分支 / L5 归一记录）。
  final IconData? old;
  final String usage;
  final String glyphText;

  String get key =>
      label.replaceAll('(', '-').replaceAll(')', '').replaceAll(' ', '')
          .replaceAll(RegExp(r'-+$'), '');
  Widget get widget => AppIcon(glyph, size: 32);
}

class _Section {
  const _Section(this.file, this.title, this.cells);
  final String file;
  final String title;
  final List<_Cell> cells;
}

Widget _pngCell(_Cell c) => SizedBox(
      width: 118,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          c.widget,
          const SizedBox(height: 6),
          Text(
            c.label,
            style: const TextStyle(
              fontFamily: 'SheetCJK',
              fontSize: 11,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

Widget _pngSheet(_Section s) => RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        width: 1060,
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title,
              style: const TextStyle(
                fontFamily: 'SheetCJK',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
                spacing: 18,
                runSpacing: 18,
                children: s.cells.map(_pngCell).toList()),
          ],
        ),
      ),
    );

// ─────────────────────────── SVG 生成 ───────────────────────────

String _f(double v) => v.toStringAsFixed(1);

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// 落地文件（Windows 防御：外部进程——编辑器/索引器/杀软——可能持有
/// 内存映射句柄导致 errno 1224；内容相同则跳过写入，否则重试退避）。
void _writeText(File f, String content) {
  try {
    if (f.existsSync() && f.readAsStringSync() == content) return;
  } catch (_) {}
  Object? last;
  for (var i = 0; i < 5; i++) {
    try {
      f.writeAsStringSync(content);
      return;
    } catch (e) {
      last = e;
      sleep(const Duration(milliseconds: 150));
    }
  }
  throw last!;
}

void _writeBytes(File f, List<int> bytes) {
  Object? last;
  for (var i = 0; i < 5; i++) {
    try {
      f.writeAsBytesSync(bytes);
      return;
    } catch (e) {
      last = e;
      sleep(const Duration(milliseconds: 150));
    }
  }
  throw last!;
}

/// 单图标 PNG 捕获（22×22 逻辑画布、透明底、1x 输出——行内尺寸精确）。
Future<Uint8List?> _captureIconPng(
    WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: _iconBoundaryKey,
          child: SizedBox(
            width: 22,
            height: 22,
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_iconBoundaryKey),
  );
  for (var i = 0; i < 3; i++) {
    final data = await tester.runAsync(() async {
      try {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return bytes;
      } catch (_) {
        return null;
      }
    });
    if (data != null) return data.buffer.asUint8List();
    await tester.pump(const Duration(milliseconds: 60));
  }
  return null;
}

/// 把 ui.Path 展平为 SVG path 数据（曲线按弧长采样，display 尺寸下不可辨）。
String _flatten(ui.Path path, double step) {
  final sb = StringBuffer();
  for (final metric in path.computeMetrics()) {
    final len = metric.length;
    if (len <= 0) continue;
    final n = (len / step).ceil().clamp(8, 4000);
    final pts = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = metric.getTangentForOffset(len * i / n);
      if (t != null) pts.add(t.position);
    }
    if (pts.isEmpty) continue;
    sb.write('M${_f(pts.first.dx)} ${_f(pts.first.dy)}');
    for (var i = 1; i < pts.length; i++) {
      sb.write('L${_f(pts[i].dx)} ${_f(pts[i].dy)}');
    }
    sb.write('Z');
  }
  return sb.toString();
}

class _GlyphSvg {
  const _GlyphSvg(this.viewBox, this.body);
  final String viewBox;
  final String body;
}

/// 把图标字形渲染为 SVG 主体（viewBox + path 内容）。
_GlyphSvg? _glyphSvg(IconData glyph) {
  final vector = miuixVectorForGlyph(glyph);
  if (vector != null) {
    final vw = vector.viewport.width;
    final vh = vector.viewport.height;
    final step = (math.min(vw, vh) / 220).clamp(0.15, 8.0);
    final body = StringBuffer();
    for (final spec in vector.paths) {
      final path = spec.build();
      final d = _flatten(path, step);
      if (d.isEmpty) continue;
      final rule = path.fillType == ui.PathFillType.evenOdd
          ? ' fill-rule="evenodd"'
          : '';
      final g = spec.groupTransform;
      final transform = g == null
          ? ''
          : ' transform="matrix(${_f(g.storage[0])} ${_f(g.storage[1])} '
              '${_f(g.storage[4])} ${_f(g.storage[5])} '
              '${_f(g.storage[12])} ${_f(g.storage[13])})"';
      if (spec.style == PaintingStyle.stroke) {
        final cap = switch (spec.strokeCap) {
          StrokeCap.round => 'round',
          StrokeCap.square => 'square',
          StrokeCap.butt => 'butt',
        };
        body.write('<path d="$d"$transform fill="none" stroke="$_ink" '
            'stroke-width="${_f(spec.strokeWidth == 0 ? 1 : spec.strokeWidth)}" '
            'stroke-linecap="$cap"'
            '${spec.alpha < 1 ? ' stroke-opacity="${_f(spec.alpha)}"' : ''}/>');
      } else {
        body.write('<path d="$d"$transform fill="$_ink"$rule'
            '${spec.alpha < 1 ? ' fill-opacity="${_f(spec.alpha)}"' : ''}/>');
      }
    }
    return _GlyphSvg('0 0 ${_f(vw)} ${_f(vh)}', body.toString());
  }

  final baked = kCupertinoGlyphPaths[glyph.codePoint];
  if (baked == null) return null;
  return _GlyphSvg(
      '-150 -150 1300 1300', '<path d="$baked" fill="$_ink"/>');
}

/// 迁移前 Material 字形（kMaterialGlyphPaths 预生成轮廓）。
_GlyphSvg? _oldGlyphSvg(IconData glyph) {
  final baked = kMaterialGlyphPaths[glyph.codePoint];
  if (baked == null) return null;
  return _GlyphSvg(
      '-150 -150 1300 1300', '<path d="$baked" fill="$_ink"/>');
}

String _standaloneSvg(_GlyphSvg g, {double size = 48}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
    'viewBox="${g.viewBox}">${g.body}</svg>';

/// 矢量名（从 MiuixVectorIcon.name 提取短名，如 `extended.home.regular` → home）。
String _vectorText(IconData glyph) {
  final vector = miuixVectorForGlyph(glyph);
  if (vector == null) return '—';
  if (vector.name.startsWith('builtin.')) return '内置矢量';
  final parts = vector.name.split('.');
  final src = parts.first;
  final name = parts.length >= 2 ? parts[1] : vector.name;
  final suffix = switch (src) {
    'os4' => '（OS4）',
    'basic' => '（basic）',
    _ => '',
  };
  return '$name$suffix';
}

const _cellW = 118.0;
const _cellH = 78.0;
const _gapX = 18.0;
const _gapY = 18.0;
const _pad = 24.0;
const _sheetW = 1060.0;
const _iconSize = 32.0;

String _svgSheet(_Section s) {
  final perRow = ((_sheetW - _pad * 2 + _gapX) / (_cellW + _gapX)).floor();
  final rows = (s.cells.length / perRow).ceil();
  final titleH = 34.0;
  final h = _pad * 2 + titleH + rows * _cellH + (rows - 1) * _gapY;

  final sb = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${_f(_sheetW)}" height="${_f(h)}" '
        'viewBox="0 0 ${_f(_sheetW)} ${_f(h)}">')
    ..write('<rect width="100%" height="100%" fill="#ffffff"/>')
    ..write('<text x="$_pad" y="${_pad + 22}" font-size="18" '
        'font-weight="bold" fill="#000" '
        'font-family="Microsoft YaHei, PingFang SC, SimHei, sans-serif">'
        '${_escape(s.title)}</text>');

  for (var i = 0; i < s.cells.length; i++) {
    final c = s.cells[i];
    final cx = _pad + (i % perRow) * (_cellW + _gapX);
    final cy = _pad + titleH + (i ~/ perRow) * (_cellH + _gapY);
    final g = _glyphSvg(c.glyph);
    if (g != null) {
      sb.write('<svg x="${_f(cx + (_cellW - _iconSize) / 2)}" y="${_f(cy)}" '
          'width="$_iconSize" height="$_iconSize" '
          'viewBox="${g.viewBox}">${g.body}</svg>');
    }
    sb.write('<text x="${_f(cx + _cellW / 2)}" y="${_f(cy + _iconSize + 20)}" '
        'font-size="11" fill="$_labelInk" text-anchor="middle" '
        'font-family="Consolas, Menlo, monospace">${_escape(c.label)}</text>');
  }
  sb.write('</svg>');
  return sb.toString();
}

/// 对照表格（曾用 Material / 现用最终 图片并排）。
String _tableMarkdown(_Section s) {
  final sb = StringBuffer()
    ..write('| 语义 | 使用位置 | 曾用（Material） | 现用（最终视觉） | '
        'Cupertino 字形 | 矢量 | 状态 |\n')
    ..write('|---|---|---|---|---|---|---|\n');
  for (final c in s.cells) {
    // 图片引用为「文档相对路径」（docs/ 下的总表直接可用）；
    // PNG = 编辑器预览全兼容版；SVG 全真矢量版同 key 并列存放。
    final oldImg = c.old == null
        ? '—'
        : '![曾用](icon-sheets/icons/${c.key}-old.png)';
    final nowImg = '![现用](icon-sheets/icons/${c.key}.png)';
    final status = miuixVectorForGlyph(c.glyph) != null ? '✅' : '⚠️';
    sb.write('| `${c.label}` | ${c.usage} | $oldImg | $nowImg | '
        '${c.glyphText.isEmpty ? '—' : '`${c.glyphText}`'} | '
        '${_vectorText(c.glyph)} | $status |\n');
  }
  return sb.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('packages/cupertino_icons/CupertinoIcons', [
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      'C:/Users/SilverT1ger/AppData/Local/Pub/Cache/hosted/pub.dev/'
          'cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
    ]);
    // 曾用 Material 字形（单图标 PNG 直渲染）。
    await _loadFont('MaterialIcons', [
      'D:/flutter/bin/cache/artifacts/material_fonts/'
          'materialicons-regular.otf',
    ]);
    await _loadFont('SheetCJK', ['C:/Windows/Fonts/simhei.ttf']);
  });

  final sections = <_Section>[
    _Section('01-navigation.png', '01 顶层导航 · Navigation', [
      _Cell('back()', AppIcons.back(),
          old: Icons.arrow_back,
          usage: '全局返回（AppBackButton）',
          glyphText: 'chevron_back'),
      _Cell('home()', AppIcons.home(),
          old: Icons.home_outlined,
          usage: '底栏/侧栏「首页」',
          glyphText: 'house'),
      _Cell('home(sel)', AppIcons.home(selected: true),
          old: Icons.home,
          usage: '底栏/侧栏「首页」选中',
          glyphText: 'house_fill'),
      _Cell('dynamic()', AppIcons.dynamic(),
          old: Icons.notifications_outlined,
          usage: '底栏/侧栏「动态」',
          glyphText: 'bell'),
      _Cell('dynamic(sel)', AppIcons.dynamic(selected: true),
          old: Icons.notifications,
          usage: '底栏/侧栏「动态」选中',
          glyphText: 'bell_fill'),
      _Cell('history()', AppIcons.history(),
          old: Icons.history_outlined,
          usage: '底栏/侧栏「历史」',
          glyphText: 'clock'),
      _Cell('history(sel)', AppIcons.history(selected: true),
          old: Icons.history,
          usage: '底栏/侧栏「历史」选中',
          glyphText: 'clock_fill'),
      _Cell('whisper()', AppIcons.whisper(),
          old: Icons.chat_bubble_outline,
          usage: '底栏/侧栏「消息」+ 动态评论数',
          glyphText: 'chat_bubble_2'),
      _Cell('whisper(sel)', AppIcons.whisper(selected: true),
          old: Icons.chat_bubble,
          usage: '底栏/侧栏「消息」选中',
          glyphText: 'chat_bubble_2_fill'),
      _Cell('profile()', AppIcons.profile(),
          old: Icons.person_outlined,
          usage: '底栏/侧栏「我的」+ 头像占位',
          glyphText: 'person'),
      _Cell('profile(sel)', AppIcons.profile(selected: true),
          old: Icons.person,
          usage: '底栏/侧栏「我的」选中',
          glyphText: 'person_fill'),
    ]),
    _Section('02-video-actions.png', '02 视频互动行 · Video Actions', [
      _Cell('like()', AppIcons.like(),
          old: Icons.thumb_up_outlined,
          usage: '视频点赞',
          glyphText: 'hand_thumbsup'),
      _Cell('like(on)', AppIcons.like(active: true),
          old: Icons.thumb_up,
          usage: '视频点赞（已赞）',
          glyphText: 'hand_thumbsup_fill'),
      _Cell('coin()', AppIcons.coin(),
          old: Icons.monetization_on_outlined,
          usage: '投币',
          glyphText: 'money_dollar_circle'),
      _Cell('coin(on)', AppIcons.coin(active: true),
          old: Icons.monetization_on,
          usage: '投币（已投）',
          glyphText: 'money_dollar_circle_fill'),
      _Cell('favorite()', AppIcons.favorite(),
          old: Icons.star_border,
          usage: '收藏',
          glyphText: 'star'),
      _Cell('favorite(on)', AppIcons.favorite(active: true),
          old: Icons.star,
          usage: '收藏（已藏）',
          glyphText: 'star_fill'),
      _Cell('dislike()', AppIcons.dislike(),
          old: Icons.thumb_down_outlined,
          usage: '点踩',
          glyphText: 'hand_thumbsdown'),
      _Cell('dislike(on)', AppIcons.dislike(active: true),
          old: Icons.thumb_down,
          usage: '点踩（已踩）',
          glyphText: 'hand_thumbsdown_fill'),
      _Cell('share()', AppIcons.share(),
          old: Icons.share_outlined,
          usage: '分享',
          glyphText: 'share'),
      _Cell('watchLater()', AppIcons.watchLater(),
          old: Icons.watch_later_outlined,
          usage: '稍后再看',
          glyphText: 'clock'),
      _Cell('watchLater(on)', AppIcons.watchLater(active: true),
          old: Icons.watch_later,
          usage: '稍后再看（已加）',
          glyphText: 'clock_fill'),
    ]),
    _Section('03-dyn-actions.png', '03 动态互动条 · Dyn Actions', [
      _Cell('reply()', AppIcons.reply(),
          old: Icons.reply,
          usage: '转发/回复',
          glyphText: 'reply'),
      _Cell('whisper()', AppIcons.whisper(),
          old: Icons.chat_bubble_outline,
          usage: '评论',
          glyphText: 'chat_bubble_2'),
      _Cell('like()', AppIcons.like(),
          old: Icons.thumb_up_outlined,
          usage: '点赞',
          glyphText: 'hand_thumbsup'),
    ]),
    _Section('04-comments.png', '04 评论区 · Comments', [
      _Cell('like(on)', AppIcons.like(active: true),
          old: Icons.thumb_up,
          usage: '评论点赞',
          glyphText: 'hand_thumbsup_fill'),
      _Cell('dislike()', AppIcons.dislike(),
          old: Icons.thumb_down_outlined,
          usage: '评论点踩',
          glyphText: 'hand_thumbsdown'),
      _Cell('reply()', AppIcons.reply(),
          old: Icons.reply,
          usage: '评论回复',
          glyphText: 'reply'),
      _Cell('expandMore()', AppIcons.expandMore(),
          old: Icons.expand_more,
          usage: '展开更多回复/排序',
          glyphText: 'chevron_down'),
      _Cell('chevronUp()', AppIcons.chevronUp(),
          old: Icons.expand_less,
          usage: '楼中楼折叠',
          glyphText: 'chevron_up'),
      _Cell('chevronDown()', AppIcons.chevronDown(),
          old: Icons.expand_more,
          usage: '展开箭头',
          glyphText: 'chevron_down'),
    ]),
    _Section('05-player.png', '05 播放器与面板 · Player', [
      _Cell('play()', AppIcons.play(),
          old: Icons.play_arrow_outlined,
          usage: '播放',
          glyphText: 'play'),
      _Cell('play(on)', AppIcons.play(active: true),
          old: Icons.play_arrow,
          usage: '播放（激活）',
          glyphText: 'play_fill'),
      _Cell('pause()', AppIcons.pause(),
          old: Icons.pause_circle_outline,
          usage: '暂停',
          glyphText: 'pause'),
      _Cell('pause(on)', AppIcons.pause(active: true),
          old: Icons.pause,
          usage: '暂停（激活）',
          glyphText: 'pause_fill'),
      _Cell('replay()', AppIcons.replay(),
          old: Icons.replay,
          usage: '重播',
          glyphText: 'restart'),
      _Cell('fastForward()', AppIcons.fastForward(),
          old: Icons.fast_forward,
          usage: '快进',
          glyphText: 'forward_fill'),
      _Cell('fastRewind()', AppIcons.fastRewind(),
          old: Icons.fast_rewind,
          usage: '快退',
          glyphText: 'backward_fill'),
      _Cell('volumeUp()', AppIcons.volumeUp(),
          old: Icons.volume_up,
          usage: '音量 — 大',
          glyphText: 'speaker_3_fill'),
      _Cell('volumeDown()', AppIcons.volumeDown(),
          old: Icons.volume_down,
          usage: '音量 — 小',
          glyphText: 'speaker_1_fill'),
      _Cell('volumeOff()', AppIcons.volumeOff(),
          old: Icons.volume_off,
          usage: '静音',
          glyphText: 'speaker_slash_fill'),
      _Cell('fullscreen()', AppIcons.fullscreen(),
          old: Icons.fullscreen,
          usage: '全屏',
          glyphText: 'fullscreen'),
      _Cell('fullscreen(on)', AppIcons.fullscreen(active: true),
          old: Icons.fullscreen_exit,
          usage: '退出全屏',
          glyphText: 'fullscreen_exit'),
      _Cell('inAppFullscreen()', AppIcons.inAppFullscreen(),
          old: Icons.crop_square_outlined,
          usage: '网页全屏',
          glyphText: 'square'),
      _Cell('pip()', AppIcons.pip(),
          old: Icons.picture_in_picture_alt,
          usage: '画中画',
          glyphText: 'tv'),
      _Cell('danmaku()', AppIcons.danmaku(),
          old: Icons.chat_bubble_outline,
          usage: '弹幕开关',
          glyphText: 'chat_bubble'),
      _Cell('danmaku(on)', AppIcons.danmaku(active: true),
          old: Icons.chat_bubble,
          usage: '弹幕开关（开）',
          glyphText: 'chat_bubble_fill'),
      _Cell('sendDanmaku()', AppIcons.sendDanmaku(),
          old: Icons.comment_outlined,
          usage: '发送弹幕',
          glyphText: 'bubble_left'),
      _Cell('danmakuTune()', AppIcons.danmakuTune(),
          old: Icons.tune,
          usage: '弹幕设置',
          glyphText: 'slider_horizontal_3'),
      _Cell('subtitle()', AppIcons.subtitle(),
          old: Icons.closed_caption_outlined,
          usage: '字幕开关',
          glyphText: 'captions_bubble'),
      _Cell('subtitle(on)', AppIcons.subtitle(active: true),
          old: Icons.closed_caption,
          usage: '字幕开关（开）',
          glyphText: 'captions_bubble_fill'),
      _Cell('chapter()', AppIcons.chapter(),
          old: Icons.bookmarks_outlined,
          usage: '章节',
          glyphText: 'bookmark'),
      _Cell('chapter(on)', AppIcons.chapter(active: true),
          old: Icons.bookmarks,
          usage: '章节（展开）',
          glyphText: 'bookmark_fill'),
      _Cell('lock()', AppIcons.lock(),
          old: Icons.lock,
          usage: '全屏锁定',
          glyphText: 'lock_fill'),
      _Cell('lockOutline()', AppIcons.lockOutline(),
          old: Icons.lock_outline,
          usage: '解锁',
          glyphText: 'lock'),
      _Cell('pin()', AppIcons.pin(),
          old: Icons.vertical_align_top,
          usage: '置顶',
          glyphText: 'pin_fill'),
      _Cell('pin(on)', AppIcons.pin(active: true),
          old: Icons.vertical_align_bottom,
          usage: '取消置顶',
          glyphText: 'pin_slash_fill'),
      _Cell('moreOptions()', AppIcons.moreOptions(),
          old: Icons.more_vert,
          usage: '更多选项（会话/用户空间）',
          glyphText: 'ellipsis'),
      _Cell('more()', AppIcons.more(),
          old: Icons.more_vert,
          usage: '更多（通用）',
          glyphText: 'ellipsis'),
    ]),
    _Section('06-common.png', '06 通用控件 · Common', [
      _Cell('search()', AppIcons.search(),
          old: Icons.search,
          usage: '搜索框（首页/搜索页）',
          glyphText: 'search'),
      _Cell('clear()', AppIcons.clear(),
          old: Icons.clear,
          usage: '清除/关闭',
          glyphText: 'clear'),
      _Cell('settings()', AppIcons.settings(),
          old: Icons.settings_outlined,
          usage: '设置入口',
          glyphText: 'settings'),
      _Cell('refresh()', AppIcons.refresh(),
          old: Icons.refresh,
          usage: '刷新',
          glyphText: 'refresh'),
      _Cell('download()', AppIcons.download(),
          old: Icons.download_outlined,
          usage: '下载/保存图片',
          glyphText: 'arrow_down_to_line'),
      _Cell('delete()', AppIcons.delete(),
          old: Icons.delete_outline,
          usage: '删除/清理',
          glyphText: 'delete'),
      _Cell('filter()', AppIcons.filter(),
          old: Icons.filter_list,
          usage: '排序/筛选',
          glyphText: 'slider_horizontal_3'),
      _Cell('check()', AppIcons.check(),
          old: Icons.check,
          usage: '勾选（多选/成功）',
          glyphText: 'checkmark'),
      _Cell('chevronForward()', AppIcons.chevronForward(),
          old: Icons.chevron_right,
          usage: '前进箭头（列表行/个人页）',
          glyphText: 'chevron_forward'),
      _Cell('radio(off)', AppIcons.radio(selected: false),
          old: Icons.radio_button_unchecked,
          usage: '单选框（SelectDialog）',
          glyphText: 'circle'),
      _Cell('radio(on)', AppIcons.radio(selected: true),
          old: Icons.radio_button_checked,
          usage: '单选框（选中）',
          glyphText: 'check_mark_circled_solid'),
      _Cell('block()', AppIcons.block(),
          old: Icons.block,
          usage: '屏蔽/封禁',
          glyphText: 'slash_circle'),
      _Cell('error()', AppIcons.error(),
          old: Icons.error_outline,
          usage: '错误/告警',
          glyphText: 'exclamationmark_circle'),
      _Cell('notificationsOff()', AppIcons.notificationsOff(),
          old: Icons.notifications_off_outlined,
          usage: '免打扰（关）',
          glyphText: 'bell_slash'),
      _Cell('notificationsOff(on)', AppIcons.notificationsOff(active: true),
          old: Icons.notifications_active_outlined,
          usage: '免打扰（开）',
          glyphText: 'bell_fill'),
    ]),
    _Section('07-metadata.png', '07 元数据行 · Metadata', [
      _Cell('viewCount()', AppIcons.viewCount(),
          old: Icons.play_circle_outline,
          usage: '播放量',
          glyphText: 'play_circle'),
      _Cell('danmakuCount()', AppIcons.danmakuCount(),
          old: Icons.subtitles_outlined,
          usage: '弹幕数',
          glyphText: 'captions_bubble'),
      _Cell('duration()', AppIcons.duration(),
          old: Icons.schedule_outlined,
          usage: '时长',
          glyphText: 'clock'),
      _Cell('calendar()', AppIcons.calendar(),
          old: Icons.calendar_today_outlined,
          usage: '发布日期',
          glyphText: 'calendar'),
    ]),
    _Section('08-l5-additions.png', '08 L5 新增语义 · L5 Additions', [
      _Cell('folder()', AppIcons.folder(),
          old: Icons.folder_outlined, usage: '收藏夹/公开私密', glyphText: 'folder'),
      _Cell('copy()', AppIcons.copy(),
          old: Icons.copy, usage: '复制 UID/链接', glyphText: 'doc_on_doc'),
      _Cell('link()', AppIcons.link(),
          old: Icons.link, usage: '打开链接', glyphText: 'link'),
      _Cell('info()', AppIcons.info(),
          old: Icons.info_outline, usage: '关于/开源协议', glyphText: 'info'),
      _Cell('send()', AppIcons.send(),
          old: Icons.send, usage: '发送/私信', glyphText: 'paperplane'),
      _Cell('image()', AppIcons.image(),
          old: Icons.image_outlined, usage: '相册/图片', glyphText: 'photo'),
      _Cell('people()', AppIcons.people(),
          old: Icons.people_outline, usage: '用户群组', glyphText: 'person_2'),
      _Cell('mail()', AppIcons.mail(),
          old: Icons.mail_outline, usage: '私信', glyphText: 'mail'),
      _Cell('call()', AppIcons.call(),
          old: Icons.phone, usage: '客服', glyphText: 'phone'),
      _Cell('location()', AppIcons.location(),
          old: Icons.near_me_outlined, usage: '定位（IP 属地）', glyphText: 'location'),
      _Cell('timer()', AppIcons.timer(),
          old: Icons.timer, usage: '定时（稍后提醒）', glyphText: 'timer'),
      _Cell('recording()', AppIcons.recording(),
          old: Icons.fiber_manual_record, usage: '录制中（LIVE 点）', glyphText: 'circle_fill'),
      _Cell('undo()', AppIcons.undo(),
          old: Icons.undo, usage: '撤销', glyphText: 'arrow_uturn_left'),
      _Cell('palette()', AppIcons.palette(),
          old: Icons.palette_outlined, usage: '主题/彩色弹幕', glyphText: 'paintbrush'),
      _Cell('add()', AppIcons.add(),
          old: Icons.add, usage: '关注（+ 按钮）', glyphText: 'add'),
      _Cell('eye()', AppIcons.eye(),
          old: Icons.remove_red_eye_outlined,
          usage: '浏览/阅读数',
          glyphText: 'eye'),
    ]),
  ];

  testWidgets('生成 PNG/SVG 拼图 + 单图标切分 + 对照表格', (tester) async {
    Directory(_outDir).createSync(recursive: true);
    final iconsDir = Directory('$_outDir/icons');
    if (iconsDir.existsSync()) {
      for (final f in iconsDir.listSync()) {
        try {
          f.deleteSync();
        } catch (_) {
          // 被外部句柄占用时忽略（后续同内容跳过 / 覆写重试兜底）。
        }
      }
    }
    iconsDir.createSync(recursive: true);
    Directory('$_outDir/tables').createSync(recursive: true);

    var iconCount = 0;
    var oldCount = 0;

    for (final section in sections) {
      // ① PNG：生产同链路实渲染。
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: _pngSheet(section)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_boundaryKey),
      );
      // 并行测试负载下 toImage 偶发失败（返回空）：重试三次加固。
      Uint8List? pngBytes;
      for (var attempt = 0; attempt < 3 && pngBytes == null; attempt++) {
        final data = await tester.runAsync(() async {
          try {
            final image = await boundary.toImage(pixelRatio: 2.0);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            return bytes;
          } catch (_) {
            return null;
          }
        });
        pngBytes = data?.buffer.asUint8List();
        if (pngBytes == null) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }
      expect(pngBytes, isNotNull, reason: '${section.file} PNG 渲染失败');
      final pngFile = File('$_outDir/${section.file}');
      _writeBytes(pngFile, pngBytes!);
      expect(pngFile.lengthSync(), greaterThan(1000),
          reason: '${section.file} PNG 落盘异常');

      // ② SVG 拼图。
      final svg = _svgSheet(section);
      expect(svg.contains('<path'), isTrue,
          reason: '${section.file} SVG 无路径内容');
      _writeText(File('$_outDir/${section.file.replaceAll('.png', '.svg')}'),
          svg);

      // ③ 单图标切分（现用 + 曾用；SVG 全真矢量 + PNG 编辑器兼容版）。
      for (final c in section.cells) {
        final now = _glyphSvg(c.glyph);
        expect(now, isNotNull, reason: '${c.label} 现用字形无 SVG');
        _writeText(File('$_outDir/icons/${c.key}.svg'),
            _standaloneSvg(now!, size: 22));
        iconCount++;
        if (c.old != null) {
          final old = _oldGlyphSvg(c.old!);
          expect(old, isNotNull,
              reason: '${c.label} 曾用字形无轮廓（检查 material_glyph_paths）');
          _writeText(File('$_outDir/icons/${c.key}-old.svg'),
              _standaloneSvg(old!, size: 22));
          oldCount++;
        }
        final nowPng = await _captureIconPng(
            tester, AppIcon(c.glyph, size: 22));
        expect(nowPng, isNotNull, reason: '${c.label} 现用 PNG 失败');
        _writeBytes(File('$_outDir/icons/${c.key}.png'), nowPng!);
        if (c.old != null) {
          final oldPng = await _captureIconPng(
              tester, Icon(c.old!, size: 22, color: const Color(0xFF111111)));
          expect(oldPng, isNotNull, reason: '${c.label} 曾用 PNG 失败');
          _writeBytes(File('$_outDir/icons/${c.key}-old.png'), oldPng!);
        }
      }

      // ④ 对照表格。
      _writeText(
          File('$_outDir/tables/${section.file.replaceAll('.png', '.md')}'),
          _tableMarkdown(section));
    }

    expect(iconCount, greaterThan(80));
    expect(oldCount, greaterThan(70));
  });
}

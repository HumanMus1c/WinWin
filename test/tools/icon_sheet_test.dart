// 图标视觉对照生成器（阶段5e-L5 配套工具）
//
// 同一份语义数据（AppIcons）同时产出两套对照资源到 `docs/icon-sheets/`：
//  ① PNG 拼图 —— 生产同链路渲染（AppIcon→MiuixIcon/Cupertino 字体回退）；
//  ② SVG 拼图 —— 全真矢量（Miuix 矢量 path 展平 + Cupertino 字形轮廓提取），
//     供 `docs/图标体系对照总表-2026-10-05.md` 内嵌（Markdown 本体无法渲染
//     图标字体与矢量，SVG/GitHub 可正常显示静态 path）。
//
// Cupertino 轮廓由 `tools/glyph_outline_export.py`（fontTools）预生成为
// `cupertino_glyph_paths.g.dart`（em=1000，y 轴已翻转）。
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

const _outDir = 'docs/icon-sheets';
const _boundaryKey = Key('sheet');

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
  const _Cell(this.label, this.glyph);
  final String label;
  final IconData glyph;

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

/// 把 ui.Path 展平为 SVG path 数据（曲线按弧长采样，display 尺寸下不可辨）。
String _flatten(ui.Path path, double step) {
  final sb = StringBuffer();
  for (final metric in path.computeMetrics()) {
    final len = metric.length;
    if (len <= 0) continue;
    final n = (len / step).ceil().clamp(8, 4000);
    Offset? first;
    final pts = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = metric.getTangentForOffset(len * i / n);
      if (t != null) pts.add(t.position);
    }
    if (pts.isEmpty) continue;
    first = pts.first;
    sb.write('M${_f(first.dx)} ${_f(first.dy)}');
    for (var i = 1; i < pts.length; i++) {
      sb.write('L${_f(pts[i].dx)} ${_f(pts[i].dy)}');
    }
    sb.write('Z');
  }
  return sb.toString();
}

String? _svgIcon(IconData glyph, double x, double y, double size) {
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
      final type = path.fillType;
      final rule = type == ui.PathFillType.evenOdd
          ? ' fill-rule="evenodd"'
          : '';
      final transform = spec.groupTransform == null
          ? ''
          : ' transform="matrix(${_f(spec.groupTransform!.storage[0])} '
              '${_f(spec.groupTransform!.storage[1])} '
              '${_f(spec.groupTransform!.storage[4])} '
              '${_f(spec.groupTransform!.storage[5])} '
              '${_f(spec.groupTransform!.storage[12])} '
              '${_f(spec.groupTransform!.storage[13])})"';
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
    return '<svg x="${_f(x)}" y="${_f(y)}" width="$size" height="$size" '
        'viewBox="0 0 ${_f(vw)} ${_f(vh)}">$body</svg>';
  }

  final baked = kCupertinoGlyphPaths[glyph.codePoint];
  if (baked == null) return null;
  return '<svg x="${_f(x)}" y="${_f(y)}" width="$size" height="$size" '
      'viewBox="-150 -150 1300 1300">'
      '<path d="$baked" fill="$_ink"/></svg>';
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
    final icon = _svgIcon(c.glyph, cx + (_cellW - _iconSize) / 2, cy, _iconSize);
    if (icon != null) sb.write(icon);
    sb.write('<text x="${_f(cx + _cellW / 2)}" y="${_f(cy + _iconSize + 20)}" '
        'font-size="11" fill="$_labelInk" text-anchor="middle" '
        'font-family="Consolas, Menlo, monospace">${_escape(c.label)}</text>');
  }
  sb.write('</svg>');
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
    await _loadFont('SheetCJK', ['C:/Windows/Fonts/simhei.ttf']);
  });

  final sections = <_Section>[
    _Section('01-navigation.png', '01 顶层导航 · Navigation', [
      _Cell('back()', AppIcons.back()),
      _Cell('home()', AppIcons.home()),
      _Cell('home(sel)', AppIcons.home(selected: true)),
      _Cell('dynamic()', AppIcons.dynamic()),
      _Cell('dynamic(sel)', AppIcons.dynamic(selected: true)),
      _Cell('history()', AppIcons.history()),
      _Cell('history(sel)', AppIcons.history(selected: true)),
      _Cell('whisper()', AppIcons.whisper()),
      _Cell('whisper(sel)', AppIcons.whisper(selected: true)),
      _Cell('profile()', AppIcons.profile()),
      _Cell('profile(sel)', AppIcons.profile(selected: true)),
    ]),
    _Section('02-video-actions.png', '02 视频互动行 · Video Actions', [
      _Cell('like()', AppIcons.like()),
      _Cell('like(on)', AppIcons.like(active: true)),
      _Cell('coin()', AppIcons.coin()),
      _Cell('coin(on)', AppIcons.coin(active: true)),
      _Cell('favorite()', AppIcons.favorite()),
      _Cell('favorite(on)', AppIcons.favorite(active: true)),
      _Cell('dislike()', AppIcons.dislike()),
      _Cell('dislike(on)', AppIcons.dislike(active: true)),
      _Cell('share()', AppIcons.share()),
      _Cell('watchLater()', AppIcons.watchLater()),
      _Cell('watchLater(on)', AppIcons.watchLater(active: true)),
    ]),
    _Section('03-dyn-actions.png', '03 动态互动条 · Dyn Actions', [
      _Cell('reply()', AppIcons.reply()),
      _Cell('whisper()', AppIcons.whisper()),
      _Cell('like()', AppIcons.like()),
    ]),
    _Section('04-comments.png', '04 评论区 · Comments', [
      _Cell('like(on)', AppIcons.like(active: true)),
      _Cell('dislike()', AppIcons.dislike()),
      _Cell('reply()', AppIcons.reply()),
      _Cell('expandMore()', AppIcons.expandMore()),
      _Cell('chevronUp()', AppIcons.chevronUp()),
      _Cell('chevronDown()', AppIcons.chevronDown()),
    ]),
    _Section('05-player.png', '05 播放器与面板 · Player', [
      _Cell('play()', AppIcons.play()),
      _Cell('play(on)', AppIcons.play(active: true)),
      _Cell('pause()', AppIcons.pause()),
      _Cell('pause(on)', AppIcons.pause(active: true)),
      _Cell('replay()', AppIcons.replay()),
      _Cell('fastForward()', AppIcons.fastForward()),
      _Cell('fastRewind()', AppIcons.fastRewind()),
      _Cell('volumeUp()', AppIcons.volumeUp()),
      _Cell('volumeDown()', AppIcons.volumeDown()),
      _Cell('volumeOff()', AppIcons.volumeOff()),
      _Cell('fullscreen()', AppIcons.fullscreen()),
      _Cell('fullscreen(on)', AppIcons.fullscreen(active: true)),
      _Cell('inAppFullscreen()', AppIcons.inAppFullscreen()),
      _Cell('pip()', AppIcons.pip()),
      _Cell('danmaku()', AppIcons.danmaku()),
      _Cell('danmaku(on)', AppIcons.danmaku(active: true)),
      _Cell('sendDanmaku()', AppIcons.sendDanmaku()),
      _Cell('danmakuTune()', AppIcons.danmakuTune()),
      _Cell('subtitle()', AppIcons.subtitle()),
      _Cell('subtitle(on)', AppIcons.subtitle(active: true)),
      _Cell('chapter()', AppIcons.chapter()),
      _Cell('chapter(on)', AppIcons.chapter(active: true)),
      _Cell('lock()', AppIcons.lock()),
      _Cell('lockOutline()', AppIcons.lockOutline()),
      _Cell('pin()', AppIcons.pin()),
      _Cell('pin(on)', AppIcons.pin(active: true)),
      _Cell('moreOptions()', AppIcons.moreOptions()),
      _Cell('more()', AppIcons.more()),
    ]),
    _Section('06-common.png', '06 通用控件 · Common', [
      _Cell('search()', AppIcons.search()),
      _Cell('clear()', AppIcons.clear()),
      _Cell('settings()', AppIcons.settings()),
      _Cell('refresh()', AppIcons.refresh()),
      _Cell('download()', AppIcons.download()),
      _Cell('delete()', AppIcons.delete()),
      _Cell('filter()', AppIcons.filter()),
      _Cell('check()', AppIcons.check()),
      _Cell('chevronForward()', AppIcons.chevronForward()),
      _Cell('radio(off)', AppIcons.radio(selected: false)),
      _Cell('radio(on)', AppIcons.radio(selected: true)),
      _Cell('block()', AppIcons.block()),
      _Cell('error()', AppIcons.error()),
      _Cell('notificationsOff()', AppIcons.notificationsOff()),
      _Cell('notificationsOff(on)', AppIcons.notificationsOff(active: true)),
    ]),
    _Section('07-metadata.png', '07 元数据行 · Metadata', [
      _Cell('viewCount()', AppIcons.viewCount()),
      _Cell('danmakuCount()', AppIcons.danmakuCount()),
      _Cell('duration()', AppIcons.duration()),
      _Cell('calendar()', AppIcons.calendar()),
    ]),
    _Section('08-l5-additions.png', '08 L5 新增语义 · L5 Additions', [
      _Cell('folder()', AppIcons.folder()),
      _Cell('copy()', AppIcons.copy()),
      _Cell('link()', AppIcons.link()),
      _Cell('info()', AppIcons.info()),
      _Cell('send()', AppIcons.send()),
      _Cell('image()', AppIcons.image()),
      _Cell('people()', AppIcons.people()),
      _Cell('mail()', AppIcons.mail()),
      _Cell('call()', AppIcons.call()),
      _Cell('location()', AppIcons.location()),
      _Cell('timer()', AppIcons.timer()),
      _Cell('recording()', AppIcons.recording()),
      _Cell('undo()', AppIcons.undo()),
      _Cell('palette()', AppIcons.palette()),
      _Cell('add()', AppIcons.add()),
      _Cell('eye()', AppIcons.eye()),
    ]),
  ];

  testWidgets('生成 PNG + SVG 图标视觉对照（docs/icon-sheets）', (tester) async {
    Directory(_outDir).createSync(recursive: true);

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
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data;
      });
      expect(bytes, isNotNull, reason: '${section.file} PNG 渲染失败');
      final pngFile = File('$_outDir/${section.file}');
      pngFile.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(pngFile.lengthSync(), greaterThan(1000),
          reason: '${section.file} PNG 落盘异常');

      // ② SVG：全真矢量（Miuix path 展平 + Cupertino 轮廓提取）。
      final svg = _svgSheet(section);
      expect(svg.contains('<path'), isTrue,
          reason: '${section.file} SVG 无路径内容');
      final svgFile =
          File('$_outDir/${section.file.replaceAll('.png', '.svg')}');
      svgFile.writeAsStringSync(svg);
      expect(svgFile.lengthSync(), greaterThan(2000),
          reason: '${section.file} SVG 落盘异常');
    }
  });
}

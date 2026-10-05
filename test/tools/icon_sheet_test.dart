// 图标视觉对照图生成器（阶段5e-L5 配套工具）
//
// 用途：把 `AppIcons` 全部语义的**最终渲染视觉**（Miuix 矢量 / Cupertino 回退）
// 渲染为 PNG 拼图，输出到 `docs/icon-sheets/`，供
// `docs/图标体系对照总表-2026-10-05.md` 内嵌（Markdown 本身无法渲染这两套
// 图标字体，只能内嵌实渲染图）。
//
// 每次运行会重建全部 PNG（内容确定）；运行：flutter test test/tools/icon_sheet_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_icons.dart';

const _outDir = 'docs/icon-sheets';
const _boundaryKey = Key('sheet');

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
  const _Cell(this.label, this.icon);
  final String label;
  final Widget icon;
}

class _Section {
  const _Section(this.file, this.title, this.cells);
  final String file;
  final String title;
  final List<_Cell> cells;
}

Widget _cell(_Cell c) => SizedBox(
      width: 118,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          c.icon,
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

Widget _sheet(_Section s) => RepaintBoundary(
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
                children: s.cells.map(_cell).toList()),
          ],
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Cupertino 私有字形字体（回退图标实渲染所需）。
    await _loadFont('packages/cupertino_icons/CupertinoIcons', [
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      'C:/Users/SilverT1ger/AppData/Local/Pub/Cache/hosted/pub.dev/'
          'cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
    ]);
    // 中文标注（系统黑体；缺失时标注降级为方块，不影响图标渲染）。
    await _loadFont('SheetCJK', ['C:/Windows/Fonts/simhei.ttf']);
  });

  final sections = <_Section>[
    _Section('01-navigation.png', '01 顶层导航 · Navigation', [
      _Cell('back()', AppIcon(AppIcons.back(), size: 32)),
      _Cell('home()', AppIcon(AppIcons.home(), size: 32)),
      _Cell('home(sel)', AppIcon(AppIcons.home(selected: true), size: 32)),
      _Cell('dynamic()', AppIcon(AppIcons.dynamic(), size: 32)),
      _Cell('dynamic(sel)', AppIcon(AppIcons.dynamic(selected: true), size: 32)),
      _Cell('history()', AppIcon(AppIcons.history(), size: 32)),
      _Cell('history(sel)', AppIcon(AppIcons.history(selected: true), size: 32)),
      _Cell('whisper()', AppIcon(AppIcons.whisper(), size: 32)),
      _Cell('whisper(sel)', AppIcon(AppIcons.whisper(selected: true), size: 32)),
      _Cell('profile()', AppIcon(AppIcons.profile(), size: 32)),
      _Cell('profile(sel)', AppIcon(AppIcons.profile(selected: true), size: 32)),
    ]),
    _Section('02-video-actions.png', '02 视频互动行 · Video Actions', [
      _Cell('like()', AppIcon(AppIcons.like(), size: 32)),
      _Cell('like(on)', AppIcon(AppIcons.like(active: true), size: 32)),
      _Cell('coin()', AppIcon(AppIcons.coin(), size: 32)),
      _Cell('coin(on)', AppIcon(AppIcons.coin(active: true), size: 32)),
      _Cell('favorite()', AppIcon(AppIcons.favorite(), size: 32)),
      _Cell('favorite(on)', AppIcon(AppIcons.favorite(active: true), size: 32)),
      _Cell('dislike()', AppIcon(AppIcons.dislike(), size: 32)),
      _Cell('dislike(on)', AppIcon(AppIcons.dislike(active: true), size: 32)),
      _Cell('share()', AppIcon(AppIcons.share(), size: 32)),
      _Cell('watchLater()', AppIcon(AppIcons.watchLater(), size: 32)),
      _Cell('watchLater(on)', AppIcon(AppIcons.watchLater(active: true), size: 32)),
    ]),
    _Section('03-dyn-actions.png', '03 动态互动条 · Dyn Actions', [
      _Cell('reply()', AppIcon(AppIcons.reply(), size: 32)),
      _Cell('whisper()', AppIcon(AppIcons.whisper(), size: 32)),
      _Cell('like()', AppIcon(AppIcons.like(), size: 32)),
    ]),
    _Section('04-comments.png', '04 评论区 · Comments', [
      _Cell('like(on)', AppIcon(AppIcons.like(active: true), size: 32)),
      _Cell('dislike()', AppIcon(AppIcons.dislike(), size: 32)),
      _Cell('reply()', AppIcon(AppIcons.reply(), size: 32)),
      _Cell('expandMore()', AppIcon(AppIcons.expandMore(), size: 32)),
      _Cell('chevronUp()', AppIcon(AppIcons.chevronUp(), size: 32)),
      _Cell('chevronDown()', AppIcon(AppIcons.chevronDown(), size: 32)),
    ]),
    _Section('05-player.png', '05 播放器与面板 · Player', [
      _Cell('play()', AppIcon(AppIcons.play(), size: 32)),
      _Cell('play(on)', AppIcon(AppIcons.play(active: true), size: 32)),
      _Cell('pause()', AppIcon(AppIcons.pause(), size: 32)),
      _Cell('pause(on)', AppIcon(AppIcons.pause(active: true), size: 32)),
      _Cell('replay()', AppIcon(AppIcons.replay(), size: 32)),
      _Cell('fastForward()', AppIcon(AppIcons.fastForward(), size: 32)),
      _Cell('fastRewind()', AppIcon(AppIcons.fastRewind(), size: 32)),
      _Cell('volumeUp()', AppIcon(AppIcons.volumeUp(), size: 32)),
      _Cell('volumeDown()', AppIcon(AppIcons.volumeDown(), size: 32)),
      _Cell('volumeOff()', AppIcon(AppIcons.volumeOff(), size: 32)),
      _Cell('fullscreen()', AppIcon(AppIcons.fullscreen(), size: 32)),
      _Cell('fullscreen(on)', AppIcon(AppIcons.fullscreen(active: true), size: 32)),
      _Cell('inAppFullscreen()', AppIcon(AppIcons.inAppFullscreen(), size: 32)),
      _Cell('pip()', AppIcon(AppIcons.pip(), size: 32)),
      _Cell('danmaku()', AppIcon(AppIcons.danmaku(), size: 32)),
      _Cell('danmaku(on)', AppIcon(AppIcons.danmaku(active: true), size: 32)),
      _Cell('sendDanmaku()', AppIcon(AppIcons.sendDanmaku(), size: 32)),
      _Cell('danmakuTune()', AppIcon(AppIcons.danmakuTune(), size: 32)),
      _Cell('subtitle()', AppIcon(AppIcons.subtitle(), size: 32)),
      _Cell('subtitle(on)', AppIcon(AppIcons.subtitle(active: true), size: 32)),
      _Cell('chapter()', AppIcon(AppIcons.chapter(), size: 32)),
      _Cell('chapter(on)', AppIcon(AppIcons.chapter(active: true), size: 32)),
      _Cell('lock()', AppIcon(AppIcons.lock(), size: 32)),
      _Cell('lockOutline()', AppIcon(AppIcons.lockOutline(), size: 32)),
      _Cell('pin()', AppIcon(AppIcons.pin(), size: 32)),
      _Cell('pin(on)', AppIcon(AppIcons.pin(active: true), size: 32)),
      _Cell('moreOptions()', AppIcon(AppIcons.moreOptions(), size: 32)),
      _Cell('more()', AppIcon(AppIcons.more(), size: 32)),
    ]),
    _Section('06-common.png', '06 通用控件 · Common', [
      _Cell('search()', AppIcon(AppIcons.search(), size: 32)),
      _Cell('clear()', AppIcon(AppIcons.clear(), size: 32)),
      _Cell('settings()', AppIcon(AppIcons.settings(), size: 32)),
      _Cell('refresh()', AppIcon(AppIcons.refresh(), size: 32)),
      _Cell('download()', AppIcon(AppIcons.download(), size: 32)),
      _Cell('delete()', AppIcon(AppIcons.delete(), size: 32)),
      _Cell('filter()', AppIcon(AppIcons.filter(), size: 32)),
      _Cell('check()', AppIcon(AppIcons.check(), size: 32)),
      _Cell('chevronForward()', AppIcon(AppIcons.chevronForward(), size: 32)),
      _Cell('radio(off)', AppIcon(AppIcons.radio(selected: false), size: 32)),
      _Cell('radio(on)', AppIcon(AppIcons.radio(selected: true), size: 32)),
      _Cell('block()', AppIcon(AppIcons.block(), size: 32)),
      _Cell('error()', AppIcon(AppIcons.error(), size: 32)),
      _Cell('notificationsOff()',
          AppIcon(AppIcons.notificationsOff(), size: 32)),
      _Cell('notificationsOff(on)',
          AppIcon(AppIcons.notificationsOff(active: true), size: 32)),
    ]),
    _Section('07-metadata.png', '07 元数据行 · Metadata', [
      _Cell('viewCount()', AppIcon(AppIcons.viewCount(), size: 32)),
      _Cell('danmakuCount()', AppIcon(AppIcons.danmakuCount(), size: 32)),
      _Cell('duration()', AppIcon(AppIcons.duration(), size: 32)),
      _Cell('calendar()', AppIcon(AppIcons.calendar(), size: 32)),
    ]),
    _Section('08-l5-additions.png', '08 L5 新增语义 · L5 Additions', [
      _Cell('folder()', AppIcon(AppIcons.folder(), size: 32)),
      _Cell('copy()', AppIcon(AppIcons.copy(), size: 32)),
      _Cell('link()', AppIcon(AppIcons.link(), size: 32)),
      _Cell('info()', AppIcon(AppIcons.info(), size: 32)),
      _Cell('send()', AppIcon(AppIcons.send(), size: 32)),
      _Cell('image()', AppIcon(AppIcons.image(), size: 32)),
      _Cell('people()', AppIcon(AppIcons.people(), size: 32)),
      _Cell('mail()', AppIcon(AppIcons.mail(), size: 32)),
      _Cell('call()', AppIcon(AppIcons.call(), size: 32)),
      _Cell('location()', AppIcon(AppIcons.location(), size: 32)),
      _Cell('timer()', AppIcon(AppIcons.timer(), size: 32)),
      _Cell('recording()', AppIcon(AppIcons.recording(), size: 32)),
      _Cell('undo()', AppIcon(AppIcons.undo(), size: 32)),
      _Cell('palette()', AppIcon(AppIcons.palette(), size: 32)),
      _Cell('add()', AppIcon(AppIcons.add(), size: 32)),
      _Cell('eye()', AppIcon(AppIcons.eye(), size: 32)),
    ]),
  ];

  testWidgets('生成图标视觉对照 PNG 拼图（docs/icon-sheets）', (tester) async {
    Directory(_outDir).createSync(recursive: true);

    for (final section in sections) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: _sheet(section)),
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
      expect(bytes, isNotNull, reason: '${section.file} 渲染失败');
      final file = File('$_outDir/${section.file}');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(1000),
          reason: '${section.file} 落盘异常');
    }
  });
}

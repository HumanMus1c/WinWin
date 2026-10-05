// Miuix 风格新美术（阶段5e-L5-6）——⚠️ 待补 16 语义（25 字形）的自绘矢量。
//
// 设计语言对齐 flutter_miuix 扩展集：24 视口、实心填充为主、几何圆角、
// 统一笔画宽度（1.8）、笔帽圆头；双态字形以 描边↔实心 或 同形（颜色区分）
// 表达。与内置等价轮廓（app_icons_builtin.g.dart）可逐枚对照挑选。
//
// 接入点：`app_icons.dart _builtinVectorFor()` — 美术优先，等价轮廓兜底。
import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_miuix/miuix.dart';

const Size _vp = Size(24, 24);

MiuixVectorIcon _icon(String name, List<MiuixVectorPath> paths) =>
    MiuixVectorIcon(
      name: 'art.$name.regular',
      viewport: _vp,
      intrinsicSize: const Size(24, 24),
      paths: paths,
    );

MiuixVectorPath _fill(ui.Path Function() build, {double alpha = 1.0}) =>
    MiuixVectorPath(build: build, style: PaintingStyle.fill, alpha: alpha);

MiuixVectorPath _stroke(ui.Path Function() build, [double width = 1.8]) =>
    MiuixVectorPath(
      build: build,
      style: PaintingStyle.stroke,
      strokeWidth: width,
      strokeCap: StrokeCap.round,
    );

ui.Path Function() _evenOdd(ui.Path Function() build) =>
    () => build()..fillType = ui.PathFillType.evenOdd;

// ── 点赞 / 点踩（点踩 = 同形纵向镜像） ─────────────────────────────

ui.Path _thumbPath() {
  final p = ui.Path();
  // 袖口
  p.addRRect(ui.RRect.fromRectAndRadius(
      const Rect.fromLTRB(2.3, 10.6, 5.3, 20.8), const Radius.circular(1.1)));
  // 手掌 + 拇指
  p.moveTo(6.4, 10.9);
  p.quadraticBezierTo(8.4, 8.6, 9.9, 5.0);
  p.quadraticBezierTo(10.3, 4.0, 11.4, 4.2);
  p.quadraticBezierTo(12.9, 4.4, 12.9, 6.0);
  p.quadraticBezierTo(12.9, 6.9, 12.6, 8.1);
  p.lineTo(12.3, 9.6);
  p.lineTo(16.5, 9.6);
  p.quadraticBezierTo(18.6, 9.6, 18.3, 11.6);
  p.lineTo(17.4, 18.4);
  p.quadraticBezierTo(17.1, 20.8, 14.7, 20.8);
  p.lineTo(6.4, 20.8);
  p.close();
  return p;
}

MiuixVectorIcon _thumbsUp() => _icon('thumbUp', [_fill(_thumbPath)]);

MiuixVectorIcon _thumbsDown() => _icon('thumbDown', [
      MiuixVectorPath(
        build: _thumbPath,
        style: PaintingStyle.fill,
        groupTransform: Matrix4.identity()
          ..translateByDouble(0, 24, 0, 1)
          ..scaleByDouble(1, -1, 1, 1),
      ),
    ]);

// ── 投币（¥ 硬币） ───────────────────────────────────────────────

MiuixVectorIcon _coin() => _icon('coin', [
      _stroke(() => ui.Path()
        ..addOval(const Rect.fromLTRB(4.2, 4.2, 19.8, 19.8)), 1.9),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(12.0, 7.6)
          ..lineTo(9.0, 11.4);
        return p;
      }, 1.7),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(12.0, 7.6)
          ..lineTo(15.0, 11.4);
        return p;
      }, 1.7),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(12.0, 10.8)
          ..lineTo(12.0, 16.6);
        return p;
      }, 1.7),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(9.5, 12.6)
          ..lineTo(14.5, 12.6);
        return p;
      }, 1.7),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(9.5, 14.5)
          ..lineTo(14.5, 14.5);
        return p;
      }, 1.7),
    ]);

// ── 单人剪影（描边 / 实心） ───────────────────────────────────────

ui.Path _personFilledPath() {
  final p = ui.Path();
  p.addOval(const Rect.fromLTRB(8.7, 4.2, 15.3, 10.8));
  p.addRRect(ui.RRect.fromRectAndCorners(
    const Rect.fromLTRB(4.6, 12.6, 19.4, 20.4),
    topLeft: const Radius.circular(5.4),
    topRight: const Radius.circular(5.4),
    bottomLeft: const Radius.circular(1.0),
    bottomRight: const Radius.circular(1.0),
  ));
  return p;
}

MiuixVectorIcon _personOutline() => _icon('person', [
      _stroke(() => ui.Path()
        ..addOval(const Rect.fromLTRB(8.9, 4.6, 15.1, 10.8))),
      _stroke(() => ui.Path()
        ..addRRect(ui.RRect.fromRectAndCorners(
          const Rect.fromLTRB(5.4, 13.4, 18.6, 20.2),
          topLeft: const Radius.circular(5.0),
          topRight: const Radius.circular(5.0),
          bottomLeft: const Radius.circular(1.0),
          bottomRight: const Radius.circular(1.0),
        ))),
    ]);

MiuixVectorIcon _personFilled() =>
    _icon('personFill', [_fill(_personFilledPath)]);

// ── 全屏 / 退出全屏（四角框） ─────────────────────────────────────

MiuixVectorIcon _fullscreen() => _icon('fullscreen', [
      _stroke(() {
        final p = ui.Path()
          ..moveTo(4.4, 9.2)
          ..lineTo(4.4, 6.6)
          ..quadraticBezierTo(4.4, 4.4, 6.6, 4.4)
          ..lineTo(9.2, 4.4);
        return p;
      }),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(14.8, 4.4)
          ..lineTo(17.4, 4.4)
          ..quadraticBezierTo(19.6, 4.4, 19.6, 6.6)
          ..lineTo(19.6, 9.2);
        return p;
      }),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(4.4, 14.8)
          ..lineTo(4.4, 17.4)
          ..quadraticBezierTo(4.4, 19.6, 6.6, 19.6)
          ..lineTo(9.2, 19.6);
        return p;
      }),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(19.6, 14.8)
          ..lineTo(19.6, 17.4)
          ..quadraticBezierTo(19.6, 19.6, 17.4, 19.6)
          ..lineTo(14.8, 19.6);
        return p;
      }),
    ]);

MiuixVectorIcon _fullscreenExit() => _icon('fullscreenExit', [
      _stroke(() {
        final p = ui.Path()
          ..moveTo(9.4, 4.4)
          ..lineTo(9.4, 6.7)
          ..quadraticBezierTo(9.4, 8.9, 7.2, 8.9)
          ..lineTo(4.4, 8.9);
        return p;
      }),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(14.6, 4.4)
          ..lineTo(14.6, 6.7)
          ..quadraticBezierTo(14.6, 8.9, 16.8, 8.9)
          ..lineTo(19.6, 8.9);
        return p;
      }),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(9.4, 19.6)
          ..lineTo(9.4, 17.3)
          ..quadraticBezierTo(9.4, 15.1, 7.2, 15.1)
          ..lineTo(4.4, 15.1);
        return p;
      }),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(14.6, 19.6)
          ..lineTo(14.6, 17.3)
          ..quadraticBezierTo(14.6, 15.1, 16.8, 15.1)
          ..lineTo(19.6, 15.1);
        return p;
      }),
    ]);

// ── 网页全屏（方框 描边/实心） ────────────────────────────────────

MiuixVectorIcon _squareOutline() => _icon('square', [
      _stroke(() => ui.Path()
        ..addRRect(ui.RRect.fromRectAndRadius(
            const Rect.fromLTRB(5.2, 5.2, 18.8, 18.8),
            const Radius.circular(3.4)))),
    ]);

MiuixVectorIcon _squareFilled() => _icon('squareFill', [
      _fill(() => ui.Path()
        ..addRRect(ui.RRect.fromRectAndRadius(
            const Rect.fromLTRB(5.2, 5.2, 18.8, 18.8),
            const Radius.circular(3.4)))),
    ]);

// ── 画中画 ────────────────────────────────────────────────────────

MiuixVectorIcon _pip() => _icon('pip', [
      _stroke(() => ui.Path()
        ..addRRect(ui.RRect.fromRectAndRadius(
            const Rect.fromLTRB(3.0, 5.0, 21.0, 18.6),
            const Radius.circular(2.8)))),
      _fill(() => ui.Path()
        ..addRRect(ui.RRect.fromRectAndRadius(
            const Rect.fromLTRB(12.6, 11.4, 19.8, 16.4),
            const Radius.circular(1.4)))),
    ]);

// ── 音量小（喇叭 + 单弧） ─────────────────────────────────────────

ui.Path _speakerBody() {
  final p = ui.Path();
  p.moveTo(3.6, 9.6);
  p.lineTo(6.9, 9.6);
  p.lineTo(11.0, 5.9);
  p.quadraticBezierTo(12.2, 4.9, 12.2, 6.4);
  p.lineTo(12.2, 17.6);
  p.quadraticBezierTo(12.2, 19.1, 11.0, 18.1);
  p.lineTo(6.9, 14.4);
  p.lineTo(3.6, 14.4);
  p.quadraticBezierTo(2.4, 14.4, 2.4, 13.2);
  p.lineTo(2.4, 10.8);
  p.quadraticBezierTo(2.4, 9.6, 3.6, 9.6);
  p.close();
  return p;
}

MiuixVectorIcon _volumeDown() => _icon('volumeDown', [
      _fill(_speakerBody),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(15.4, 9.8)
          ..quadraticBezierTo(17.2, 12.0, 15.4, 14.2);
        return p;
      }, 1.9),
    ]);

// ── 快退（双三角） ────────────────────────────────────────────────

MiuixVectorIcon _backward() => _icon('backward', [
      _fill(() {
        final p = ui.Path()
          ..moveTo(12.2, 7.0)
          ..lineTo(19.9, 12.0)
          ..lineTo(12.2, 17.0)
          ..close();
        return p;
      }),
      _fill(() {
        final p = ui.Path()
          ..moveTo(4.1, 7.0)
          ..lineTo(11.8, 12.0)
          ..lineTo(4.1, 17.0)
          ..close();
        return p;
      }),
    ]);

// ── 字幕（气泡 + 横线 描边/实心挖空） ────────────────────────────

MiuixVectorIcon _captionsOutline() => _icon('captions', [
      _stroke(() => ui.Path()
        ..addRRect(ui.RRect.fromRectAndRadius(
            const Rect.fromLTRB(2.8, 5.4, 21.2, 18.6),
            const Radius.circular(3.2)))),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(6.6, 14.6)
          ..lineTo(11.0, 14.6);
        return p;
      }, 1.7),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(13.0, 14.6)
          ..lineTo(17.4, 14.6);
        return p;
      }, 1.7),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(7.6, 9.6)
          ..lineTo(16.4, 9.6);
        return p;
      }, 1.7),
    ]);

MiuixVectorIcon _captionsFilled() => _icon('captionsFill', [
      _fill(_evenOdd(() {
        final p = ui.Path()
          ..addRRect(ui.RRect.fromRectAndRadius(
              const Rect.fromLTRB(2.8, 5.4, 21.2, 18.6),
              const Radius.circular(3.2)))
          ..addRRect(ui.RRect.fromRectAndRadius(
              const Rect.fromLTRB(6.6, 13.8, 11.0, 15.4),
              const Radius.circular(0.8)))
          ..addRRect(ui.RRect.fromRectAndRadius(
              const Rect.fromLTRB(13.0, 13.8, 17.4, 15.4),
              const Radius.circular(0.8)))
          ..addRRect(ui.RRect.fromRectAndRadius(
              const Rect.fromLTRB(7.6, 8.8, 16.4, 10.4),
              const Radius.circular(0.8)));
        return p;
      })),
    ]);

// ── 章节（书签 描边/实心） ───────────────────────────────────────

ui.Path _bookmarkPath() {
  final p = ui.Path();
  p.moveTo(7.3, 4.6);
  p.lineTo(16.7, 4.6);
  p.quadraticBezierTo(18.4, 4.6, 18.4, 6.3);
  p.lineTo(18.4, 18.6);
  p.quadraticBezierTo(18.4, 19.9, 17.3, 19.2);
  p.lineTo(12.0, 15.6);
  p.lineTo(6.7, 19.2);
  p.quadraticBezierTo(5.6, 19.9, 5.6, 18.6);
  p.lineTo(5.6, 6.3);
  p.quadraticBezierTo(5.6, 4.6, 7.3, 4.6);
  p.close();
  return p;
}

MiuixVectorIcon _bookmarkOutline() =>
    _icon('bookmark', [_stroke(_bookmarkPath)]);

MiuixVectorIcon _bookmarkFilled() =>
    _icon('bookmarkFill', [_fill(_bookmarkPath)]);

// ── 单选框（圆圈 / 圆圈点） ──────────────────────────────────────

MiuixVectorIcon _radioOff() => _icon('radioOff', [
      _stroke(() => ui.Path()
        ..addOval(const Rect.fromLTRB(4.9, 4.9, 19.1, 19.1)), 1.9),
    ]);

MiuixVectorIcon _radioOn() => _icon('radioOn', [
      _stroke(() => ui.Path()
        ..addOval(const Rect.fromLTRB(4.9, 4.9, 19.1, 19.1)), 1.9),
      _fill(() => ui.Path()
        ..addOval(const Rect.fromLTRB(8.4, 8.4, 15.6, 15.6))),
    ]);

// ── 错误（实心圆挖空感叹号） ─────────────────────────────────────

MiuixVectorIcon _alert() => _icon('alert', [
      _fill(_evenOdd(() {
        final p = ui.Path()
          ..addOval(const Rect.fromLTRB(3.9, 3.9, 20.1, 20.1))
          ..addRRect(ui.RRect.fromRectAndRadius(
              const Rect.fromLTRB(11.1, 7.0, 12.9, 13.8),
              const Radius.circular(0.9)))
          ..addOval(const Rect.fromLTRB(10.9, 15.6, 13.1, 17.8));
        return p;
      })),
    ]);

// ── 播放量（实心圆挖空三角） ─────────────────────────────────────

MiuixVectorIcon _playCircle() => _icon('playCircle', [
      _fill(_evenOdd(() {
        final p = ui.Path()
          ..addOval(const Rect.fromLTRB(3.7, 3.7, 20.3, 20.3))
          ..moveTo(10.2, 8.3)
          ..lineTo(16.4, 12.0)
          ..lineTo(10.2, 15.7)
          ..close();
        return p;
      })),
    ]);

// ── 日历 ─────────────────────────────────────────────────────────

MiuixVectorIcon _calendarArt() => _icon('calendar', [
      _stroke(() => ui.Path()
        ..addRRect(ui.RRect.fromRectAndRadius(
            const Rect.fromLTRB(3.6, 5.4, 20.4, 20.4),
            const Radius.circular(3.0)))),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(8.2, 3.4)
          ..lineTo(8.2, 6.6);
        return p;
      }, 1.8),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(15.8, 3.4)
          ..lineTo(15.8, 6.6);
        return p;
      }, 1.8),
      _fill(() => ui.Path()
        ..addOval(const Rect.fromLTRB(7.1, 11.6, 9.7, 14.2))),
      _fill(() => ui.Path()
        ..addOval(const Rect.fromLTRB(14.3, 11.6, 16.9, 14.2))),
    ]);

// ── 免打扰（铃铛 + 斜杠） ────────────────────────────────────────

ui.Path _bellPath() {
  final p = ui.Path();
  p.moveTo(12.0, 3.4);
  p.quadraticBezierTo(7.3, 3.4, 7.3, 9.0);
  p.quadraticBezierTo(7.3, 13.4, 5.9, 15.3);
  p.quadraticBezierTo(5.2, 16.2, 6.3, 16.2);
  p.lineTo(17.7, 16.2);
  p.quadraticBezierTo(18.8, 16.2, 18.1, 15.3);
  p.quadraticBezierTo(16.7, 13.4, 16.7, 9.0);
  p.quadraticBezierTo(16.7, 3.4, 12.0, 3.4);
  p.close();
  return p;
}

MiuixVectorIcon _bellSlash() => _icon('bellSlash', [
      _fill(_bellPath),
      _fill(() {
        final p = ui.Path();
        p.addRRect(ui.RRect.fromRectAndRadius(
            const Rect.fromLTRB(10.3, 18.0, 13.7, 19.3),
            const Radius.circular(0.65)));
        return p;
      }),
      _stroke(() {
        final p = ui.Path()
          ..moveTo(4.6, 4.4)
          ..lineTo(19.4, 19.6);
        return p;
      }, 2.0),
    ]);

// ── 字形 → 新美术 映射 ───────────────────────────────────────────

MiuixVectorIcon? _artFor(IconData glyph) {
  final cp = glyph.codePoint;
  return switch (cp) {
    _ when cp == CupertinoIcons.hand_thumbsup.codePoint => _thumbsUp(),
    _ when cp == CupertinoIcons.hand_thumbsup_fill.codePoint => _thumbsUp(),
    _ when cp == CupertinoIcons.hand_thumbsdown.codePoint => _thumbsDown(),
    _ when cp == CupertinoIcons.hand_thumbsdown_fill.codePoint =>
      _thumbsDown(),
    _ when cp == CupertinoIcons.money_dollar_circle.codePoint => _coin(),
    _ when cp == CupertinoIcons.money_dollar_circle_fill.codePoint => _coin(),
    _ when cp == CupertinoIcons.person.codePoint => _personOutline(),
    _ when cp == CupertinoIcons.person_fill.codePoint => _personFilled(),
    _ when cp == CupertinoIcons.fullscreen.codePoint => _fullscreen(),
    _ when cp == CupertinoIcons.fullscreen_exit.codePoint => _fullscreenExit(),
    _ when cp == CupertinoIcons.square.codePoint => _squareOutline(),
    _ when cp == CupertinoIcons.square_fill.codePoint => _squareFilled(),
    _ when cp == CupertinoIcons.tv.codePoint => _pip(),
    _ when cp == CupertinoIcons.speaker_1_fill.codePoint => _volumeDown(),
    _ when cp == CupertinoIcons.backward_fill.codePoint => _backward(),
    _ when cp == CupertinoIcons.captions_bubble.codePoint => _captionsOutline(),
    _ when cp == CupertinoIcons.captions_bubble_fill.codePoint =>
      _captionsFilled(),
    _ when cp == CupertinoIcons.bookmark.codePoint => _bookmarkOutline(),
    _ when cp == CupertinoIcons.bookmark_fill.codePoint => _bookmarkFilled(),
    _ when cp == CupertinoIcons.circle.codePoint => _radioOff(),
    _ when cp == CupertinoIcons.check_mark_circled_solid.codePoint =>
      _radioOn(),
    _ when cp == CupertinoIcons.exclamationmark_circle.codePoint => _alert(),
    _ when cp == CupertinoIcons.play_circle.codePoint => _playCircle(),
    _ when cp == CupertinoIcons.calendar.codePoint => _calendarArt(),
    _ when cp == CupertinoIcons.bell_slash.codePoint => _bellSlash(),
    _ => null,
  };
}

final Map<int, MiuixVectorIcon> _artCache = {};

/// 查询新美术（无对应返回 null；缓存实例）。
MiuixVectorIcon? miuixArtIconFor(IconData glyph) {
  final icon = _artFor(glyph);
  if (icon == null) return null;
  return _artCache.putIfAbsent(glyph.codePoint, () => icon);
}

# -*- coding: utf-8 -*-
"""字形轮廓提取器（阶段5e-L5 文档配套工具）

一次提取两套「回退/历史字形」的矢量轮廓，输出 Dart 常量表（em=1000，y 轴翻转，
SVG 坐标系）：

1. Cupertino（回退字形）      → test/tools/cupertino_glyph_paths.g.dart
   源：cupertino_icons 包 CupertinoIcons.ttf（MIT, Vladimir Kharlampidi）
2. Material（迁移前曾用字形） → test/tools/material_glyph_paths.g.dart
   源：Flutter SDK materialfonts/materialicons-regular.otf（Apache-2.0）

依赖：pip install fonttools
运行：python tools/glyph_outline_export.py
"""
import glob
import os
import re
import sys

from fontTools.misc.transform import Transform
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

CACHE = os.path.join(os.environ.get("LOCALAPPDATA", ""),
                     "Pub", "Cache", "hosted", "pub.dev")

# ── 1. Cupertino 回退字形（对照表 ⚠️ 区） ─────────────────────────────
CUPERTINO_WANTED = [
    "person", "person_fill",
    "hand_thumbsup", "hand_thumbsup_fill",
    "hand_thumbsdown", "hand_thumbsdown_fill",
    "money_dollar_circle", "money_dollar_circle_fill",
    "backward_fill", "speaker_1_fill",
    "fullscreen", "fullscreen_exit",
    "square", "square_fill", "tv",
    "captions_bubble", "captions_bubble_fill",
    "bookmark", "bookmark_fill",
    "check_mark_circled_solid", "circle",
    "exclamationmark_circle", "play_circle", "calendar", "bell_slash",
    # B7-c3 补丁：导航未选中/填充语义回退（Miuix 素材集缺线条对应）。
    "house", "clock", "chat_bubble_2", "bell_fill",
]

# ── 2. Material 历史字形（L3 前双分支 + L5 归一记录，共 84 个） ────────
MATERIAL_WANTED = [
    "arrow_back",
    "home", "home_outlined",
    "notifications", "notifications_outlined",
    "history", "history_outlined",
    "chat_bubble", "chat_bubble_outline",
    "person", "person_outlined",
    "thumb_up", "thumb_up_outlined",
    "thumb_down", "thumb_down_outlined",
    "monetization_on", "monetization_on_outlined",
    "star", "star_border",
    "share_outlined",
    "watch_later", "watch_later_outlined",
    "reply",
    "expand_more", "expand_less",
    "search", "clear",
    "more_vert",
    "settings_outlined",
    "refresh",
    "download_outlined",
    "delete_outline",
    "filter_list",
    "check",
    "chevron_right",
    "play_arrow", "play_arrow_outlined",
    "pause", "pause_circle_outline",
    "replay",
    "fast_forward", "fast_rewind",
    "lock", "lock_outline",
    "volume_up", "volume_down", "volume_off",
    "fullscreen", "fullscreen_exit",
    "crop_square", "crop_square_outlined",
    "picture_in_picture_alt",
    "comment_outlined",
    "tune",
    "closed_caption", "closed_caption_outlined",
    "bookmarks", "bookmarks_outlined",
    "vertical_align_top", "vertical_align_bottom",
    "notifications_off_outlined", "notifications_active_outlined",
    "radio_button_checked", "radio_button_unchecked",
    "block",
    "error_outline",
    "play_circle_outline",
    "subtitles_outlined",
    "schedule_outlined",
    "calendar_today_outlined",
    "folder_outlined",
    "copy", "link", "info_outline", "send", "image_outlined",
    "people_outline", "mail_outline", "phone", "near_me_outlined",
    "timer", "fiber_manual_record", "undo", "palette_outlined",
    "add", "remove_red_eye_outlined",
]


def parse_codepoints(icons_path: str, wanted) -> dict:
    src = open(icons_path, encoding="utf-8").read()
    found = {}
    for m in re.finditer(
            r"static const IconData (\w+)\s*=\s*IconData\(\s*0x([0-9a-fA-F]+)",
            src):
        if m.group(1) in wanted:
            found[m.group(1)] = int(m.group(2), 16)
    missing = [n for n in wanted if n not in found]
    if missing:
        print(f"{icons_path} 缺少字形：{missing}", file=sys.stderr)
        sys.exit(1)
    return found


def export(ttf_path: str, codepoints: dict, out_path: str, header: str) -> None:
    font = TTFont(ttf_path)
    upm = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    scale = 1000.0 / upm

    lines = [header, "",
             "/// 码点 → SVG 轮廓路径（多轮廓以空格分隔；em=1000，y 轴已翻转）。",
             "const Map<int, String> " + (
                 "kCupertinoGlyphPaths" if "cupertino" in out_path
                 else "kMaterialGlyphPaths") + " = {"]
    for name, cp in codepoints.items():
        gname = cmap.get(cp)
        if gname is None:
            print(f"cmap 无码点 0x{cp:x} ({name})", file=sys.stderr)
            sys.exit(1)
        pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.1f}")
        glyph_set[gname].draw(TransformPen(
            pen, Transform(scale, 0, 0, -scale, 0, 1000)))
        d = pen.getCommands()
        if not d:
            print(f"字形 {name} 路径为空", file=sys.stderr)
            sys.exit(1)
        lines.append(f"  0x{cp:x}: '{d}',")
    lines.append("};")
    lines.append("")
    open(out_path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"OK: {len(codepoints)} 字形 (upm={upm}) → {out_path}")


# ── 3. 内置矢量补齐（⚠️ 待补 16 语义 → 项目自有 MiuixVectorIcon 数据） ──
# 轮廓与 Cupertino 回退字形等价（零视觉变更），但统一走矢量管线、脱离字体依赖。
BUILTIN_WANTED = [
    "hand_thumbsup", "hand_thumbsup_fill",
    "hand_thumbsdown", "hand_thumbsdown_fill",
    "money_dollar_circle", "money_dollar_circle_fill",
    "person", "person_fill",
    "fullscreen", "fullscreen_exit",
    "square", "square_fill", "tv",
    "speaker_1_fill", "backward_fill",
    "captions_bubble", "captions_bubble_fill",
    "chat_bubble", "chat_bubble_fill",
    "bookmark", "bookmark_fill",
    "circle", "check_mark_circled_solid",
    "exclamationmark_circle", "play_circle", "calendar", "bell_slash",
]


def expand_hv(d: str) -> str:
    """规范化为 M/L/Q/C/Z 绝对命令（miuixParsePath 仅支持这些）。

    处理两件事：① H/V 简写展开为 L；② 隐式参数续行（如 ``M x y x y`` →
    第二对坐标按 L 处理、``L``/``Q``/``C`` 的重复参数组同理）。
    """
    toks = d.split()
    out = []
    i = 0
    cx = cy = sx = sy = 0.0
    n = len(toks)

    def is_num(t: str) -> bool:
        try:
            float(t)
            return True
        except ValueError:
            return False

    while i < n:
        cmd = toks[i]
        i += 1
        if cmd in ("M", "L"):
            first = cmd == "M"
            while i + 1 < n and is_num(toks[i]):
                x, y = float(toks[i]), float(toks[i + 1])
                i += 2
                if first:
                    cx, cy = sx, sy = x, y
                    out += ["M", f"{x:.1f}", f"{y:.1f}"]
                    first = False
                else:
                    cx, cy = x, y
                    out += ["L", f"{x:.1f}", f"{y:.1f}"]
        elif cmd == "Q":
            while i + 3 < n and is_num(toks[i]):
                x1, y1, x, y = (float(v) for v in toks[i:i + 4])
                i += 4
                cx, cy = x, y
                out += ["Q", f"{x1:.1f}", f"{y1:.1f}", f"{x:.1f}", f"{y:.1f}"]
        elif cmd == "C":
            while i + 5 < n and is_num(toks[i]):
                x1, y1, x2, y2, x, y = (float(v) for v in toks[i:i + 6])
                i += 6
                cx, cy = x, y
                out += ["C", f"{x1:.1f}", f"{y1:.1f}", f"{x2:.1f}",
                        f"{y2:.1f}", f"{x:.1f}", f"{y:.1f}"]
        elif cmd == "H":
            while i < n and is_num(toks[i]):
                cx = float(toks[i])
                i += 1
                out += ["L", f"{cx:.1f}", f"{cy:.1f}"]
        elif cmd == "V":
            while i < n and is_num(toks[i]):
                cy = float(toks[i])
                i += 1
                out += ["L", f"{cx:.1f}", f"{cy:.1f}"]
        elif cmd == "Z":
            cx, cy = sx, sy
            out += ["Z"]
        else:
            raise ValueError(
                f"未知命令 {cmd!r} @ {i - 1}/{n}: "
                f"{toks[max(0, i - 5):i + 5]}")
    return " ".join(out)


def main() -> int:
    # Cupertino
    ttf = glob.glob(os.path.join(
        CACHE, "cupertino_icons-*", "assets", "CupertinoIcons.ttf"))
    icons = glob.glob(os.path.join(
        CACHE, "cupertino_ui-*", "lib", "src", "icons.dart"))
    if not ttf or not icons:
        print("找不到 cupertino_icons/cupertino_ui", file=sys.stderr)
        return 1
    export(
        ttf[0], parse_codepoints(icons[0], CUPERTINO_WANTED),
        os.path.join("test", "tools", "cupertino_glyph_paths.g.dart"),
        "// GENERATED — 由 tools/glyph_outline_export.py 生成，勿手改。\n"
        "// 来源：cupertino_icons (MIT, Vladimir Kharlampidi) CupertinoIcons.ttf")

    # 内置矢量补齐（lib/：coords 平移 +150 → viewport 0..1300，避免 tint
    # saveLayer 边界裁剪；绘制路径与 Cupertino 回退字形等价）。
    font = TTFont(ttf[0])
    upm = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    scale = 1000.0 / upm
    builtin_lines = [
        "// GENERATED — 由 tools/glyph_outline_export.py 生成，勿手改。",
        "// 来源：cupertino_icons (MIT, Vladimir Kharlampidi) CupertinoIcons.ttf",
        "// 用途：⚠️ 待补语义的内置矢量轮廓（等价回退字形，脱离字体依赖）。",
        "// 坐标：em=1000 平移 +150，y 轴翻转；viewport 1300×1300。",
        "",
        "/// Cupertino 码点 → 内置矢量路径（项目自有 MiuixVectorIcon 数据源）。",
        "const Map<int, String> kBuiltinIconPaths = {",
    ]
    for name in BUILTIN_WANTED:
        cp = parse_codepoints(icons[0], [name])[name]
        gname = cmap.get(cp)
        pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.1f}")
        glyph_set[gname].draw(TransformPen(
            pen, Transform(scale, 0, 0, -scale, 150, 1150)))
        d = pen.getCommands()
        if not d:
            print(f"内置字形 {name} 路径为空", file=sys.stderr)
            return 1
        # miuixParsePath 要求命令字母独立成 token（空格分隔）且仅 M/L/Q/C/Z：
        # fontTools 输出为 "M643.2 717.4Q..." 粘连格式并带 H/V 简写，此处规范化。
        d = " ".join(re.sub(r"([A-Za-z])", r" \1 ", d).split())
        d = expand_hv(d)
        builtin_lines.append(f"  0x{cp:x}: '{d}',")
    builtin_lines.append("};")
    builtin_lines.append("")
    builtin_path = os.path.join("lib", "theme", "app_icons_builtin.g.dart")
    open(builtin_path, "w", encoding="utf-8", newline="\n").write(
        "\n".join(builtin_lines))
    print(f"OK: {len(BUILTIN_WANTED)} 内置字形 → {builtin_path}")

    # Material
    m_icons = glob.glob(os.path.join(
        CACHE, "material_ui-*", "lib", "src", "icons.dart"))
    flutter_root = os.path.dirname(os.path.dirname(
        os.path.abspath(glob.glob(os.path.join(
            CACHE, "material_ui-*"))[0]).split(os.sep)[0]))
    # 依次尝试常见 SDK 位置（含 FLUTTER_ROOT 环境变量）。
    fonts = []
    env_root = os.environ.get("FLUTTER_ROOT")
    if env_root:
        fonts += glob.glob(os.path.join(
            env_root, "bin", "cache", "artifacts", "material_fonts",
            "materialicons-regular.otf"))
    fonts += glob.glob("D:/flutter/bin/cache/artifacts/material_fonts/"
                       "materialicons-regular.otf")
    if not m_icons or not fonts:
        print("找不到 material_ui icons.dart 或 MaterialIcons 字体",
              file=sys.stderr)
        return 1
    export(
        fonts[0], parse_codepoints(m_icons[0], MATERIAL_WANTED),
        os.path.join("test", "tools", "material_glyph_paths.g.dart"),
        "// GENERATED — 由 tools/glyph_outline_export.py 生成，勿手改。\n"
        "// 来源：Flutter SDK materialicons-regular.otf (Apache-2.0)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

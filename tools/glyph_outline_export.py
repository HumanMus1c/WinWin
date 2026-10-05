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

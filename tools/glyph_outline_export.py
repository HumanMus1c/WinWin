# -*- coding: utf-8 -*-
"""Cupertino 私有区码点 → SVG 轮廓路径提取器（阶段5e-L5 文档配套工具）

从 `cupertino_icons` 包的 TTF 中提取指定字形的矢量轮廓（含复合字形），
以 y 轴翻转为 SVG 坐标系（em=1000）后输出 Dart 常量表：
    test/tools/cupertino_glyph_paths.g.dart

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

# 本项目对照表中需要矢量化（Cupertino 回退）的 25 个字形
WANTED = [
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

CACHE = os.path.join(os.environ.get("LOCALAPPDATA", ""),
                     "Pub", "Cache", "hosted", "pub.dev")


def main() -> int:
    ttf_matches = glob.glob(os.path.join(CACHE, "cupertino_icons-*",
                                         "assets", "CupertinoIcons.ttf"))
    icons_matches = glob.glob(os.path.join(CACHE, "cupertino_ui-*",
                                           "lib", "src", "icons.dart"))
    if not ttf_matches or not icons_matches:
        print("找不到 cupertino_icons/cupertino_ui 资源", file=sys.stderr)
        return 1
    ttf_path, icons_path = ttf_matches[0], icons_matches[0]

    src = open(icons_path, encoding="utf-8").read()
    codepoints = {}
    for m in re.finditer(
            r"static const IconData (\w+)\s*=\s*IconData\(\s*0x([0-9a-fA-F]+)",
            src):
        if m.group(1) in WANTED:
            codepoints[m.group(1)] = int(m.group(2), 16)
    missing = [n for n in WANTED if n not in codepoints]
    if missing:
        print("icons.dart 缺少字形：", missing, file=sys.stderr)
        return 1

    font = TTFont(ttf_path)
    upm = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    scale = 1000.0 / upm

    lines = [
        "// GENERATED — 由 tools/glyph_outline_export.py 生成，勿手改。",
        "// 来源：cupertino_icons (MIT, Vladimir Kharlampidi) CupertinoIcons.ttf",
        "// 坐标：em=1000，y 轴已翻转为 SVG 坐标系（原点在 em 顶部）。",
        "",
        "/// Cupertino 码点 → SVG 轮廓路径（多轮廓以空格分隔）。",
        "const Map<int, String> kCupertinoGlyphPaths = {",
    ]
    for name in WANTED:
        cp = codepoints[name]
        gname = cmap.get(cp)
        if gname is None:
            print(f"cmap 无码点 0x{cp:x} ({name})", file=sys.stderr)
            return 1
        pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.1f}")
        # x' = x*scale；y' = 1000 - y*scale（翻转并平移到 em 顶部）
        glyph_set[gname].draw(TransformPen(
            pen, Transform(scale, 0, 0, -scale, 0, 1000)))
        d = pen.getCommands()
        if not d:
            print(f"字形 {name} 路径为空", file=sys.stderr)
            return 1
        lines.append(f"  0x{cp:x}: '{d}',")
    lines.append("};")
    lines.append("")

    out_path = os.path.join("test", "tools", "cupertino_glyph_paths.g.dart")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    open(out_path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"OK: {len(WANTED)} 字形 → {out_path} (upm={upm})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# -*- coding: utf-8 -*-
"""B 站官网公开素材导入器（阶段5e-L5-8，A+B）

来源（他人公开抓取的**官网素材**）：
1. `molefish3614/bilifont`（MIT，2020 主站 iconfont 提取）——A 组
2. `dashuchufang/bili_icon_pack` 的 `vanfont.ttf`（官网视频详情页图标字体）——B 组

处理：fontTools 提取轮廓 → 按字形 bbox 归一化（等比适配 870 盒、居中于
960 视口，与 Material Symbols 视觉重量对齐）→ y 轴翻转 → 绝对 M/L/Q/C/Z
（空格分隔，适配 miuixParsePath）。

输出：lib/theme/app_icons_bili.g.dart（按本项目 Cupertino 调色板码点索引）
运行：python tools/bili_site_assets_import.py
"""
import glob
import io
import os
import re
import sys
import urllib.request

from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

CACHE = os.path.join(os.environ.get("LOCALAPPDATA", ""),
                     "Pub", "Cache", "hosted", "pub.dev")

VANFONT_URL = ("https://raw.githubusercontent.com/dashuchufang/"
               "bili_icon_pack/master/vanfont.ttf")
BILIFONT_URL = ("https://raw.githubusercontent.com/molefish3614/"
                "bilifont/master/src/iconfont.ttf")

# 目标：本项目字形名 → (字体, 码点)
# vanfont = 官网视频详情页（B 组）；bilifont = 主站 iconfont（A 组）
#
# 注：官网字体多为**单形**（无 off 描边/on 实心对）。双态语义
# （点赞/点踩/投币/收藏）保留 Material Symbols 官方双态对（L5-7）；
# 本层仅覆盖**单态**语义，避免常态失去描边版/造型歧义（如 usemo≠硬币）。
TARGETS = {
    # 互动行（单态）
    "share": ("van", 0xE70F),                  # videodetails_share 分享
    # 元数据行
    "play_circle": ("van", 0xE6E6),            # info_playnumber 播放数
    # 通用
    "arrow_down_to_line": ("van", 0xE744),     # download 下载
    # A 组（bilifont 主站）
    "search": ("bili", 0xE635),                # general_search 搜索
    "folder": ("bili", 0xE730),                # icon_dingdao_shoucangjia 收藏夹
    # 弹幕数（经载体字形 Icons.subtitles_outlined，码点 0xf3fd）
    "carrier_subtitles_outlined": ("van", 0xE6E7),  # info_barragenumber 弹幕数
}

CARRIER_SUBTITLES_OUTLINED = 0xF3FD  # material Icons.subtitles_outlined（实测码点）

NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"


def expand_hv(d: str) -> str:
    """规范化为 M/L/Q/C/Z 绝对命令（miuixParsePath 子集）。

    处理 H/V 简写与隐式参数续行（如 ``M x y x y`` → 第二对按 L）。
    """
    toks = d.split()
    out = []
    i = 0
    cx = cy = sx = sy = 0.0
    n = len(toks)

    def is_num(t):
        try:
            float(t)
            return True
        except ValueError:
            return False

    while i < n:
        cmd = toks[i]; i += 1
        if cmd in ("M", "L"):
            first = cmd == "M"
            while i + 1 < n and is_num(toks[i]):
                x, y = float(toks[i]), float(toks[i + 1]); i += 2
                if first:
                    cx, cy = sx, sy = x, y
                    out += ["M", f"{x:.1f}", f"{y:.1f}"]
                    first = False
                else:
                    cx, cy = x, y
                    out += ["L", f"{x:.1f}", f"{y:.1f}"]
        elif cmd == "Q":
            while i + 3 < n and is_num(toks[i]):
                x1, y1, x, y = (float(v) for v in toks[i:i + 4]); i += 4
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
                cx = float(toks[i]); i += 1
                out += ["L", f"{cx:.1f}", f"{cy:.1f}"]
        elif cmd == "V":
            while i < n and is_num(toks[i]):
                cy = float(toks[i]); i += 1
                out += ["L", f"{cx:.1f}", f"{cy:.1f}"]
        elif cmd == "Z":
            cx, cy = sx, sy
            out += ["Z"]
        else:
            raise ValueError(f"未知命令 {cmd!r} @ {i - 1}/{n}")
    return " ".join(out)


def fetch(url: str) -> TTFont:
    with urllib.request.urlopen(url, timeout=60) as resp:
        return TTFont(io.BytesIO(resp.read()))


def extract(font: TTFont, cp: int) -> str:
    cmap = font.getBestCmap()
    gname = cmap.get(cp)
    if gname is None:
        raise ValueError(f"字体缺少码点 U+{cp:04X}")
    gs = font.getGlyphSet()
    bpen = BoundsPen(gs)
    gs[gname].draw(bpen)
    if not bpen.bounds:
        raise ValueError(f"字形 U+{cp:04X} 无轮廓")
    x0, y0, x1, y1 = bpen.bounds
    s = 870.0 / max(x1 - x0, y1 - y0)
    # 等比缩放适配 870 盒、居中于 960 视口；y 轴翻转（字体 y-up → SVG y-down）
    transform = Transform(s, 0, 0, -s,
                          480 - s * (x0 + x1) / 2,
                          480 + s * (y0 + y1) / 2)
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.1f}")
    gs[gname].draw(TransformPen(pen, transform))
    d = pen.getCommands()
    # 归一化为 miuixParsePath 子集（空格分隔、命令独立 token、H/V→L）
    d = " ".join(re.sub(r"([A-Za-z])", r" \1 ", d).split())
    return expand_hv(d)


def main() -> int:
    icons = glob.glob(os.path.join(CACHE, "cupertino_ui-*", "lib", "src",
                                   "icons.dart"))
    if not icons:
        print("找不到 cupertino_ui", file=sys.stderr)
        return 1
    src = open(icons[0], encoding="utf-8").read()
    cp_by_name = {}
    for m in re.finditer(
            r"static const IconData (\w+)\s*=\s*IconData\(\s*0x([0-9a-fA-F]+)",
            src):
        cp_by_name.setdefault(m.group(1), int(m.group(2), 16))

    van = fetch(VANFONT_URL)
    bili = fetch(BILIFONT_URL)
    fonts = {"van": van, "bili": bili}

    lines = [
        "// GENERATED — 由 tools/bili_site_assets_import.py 生成，勿手改。",
        "// 来源：B站官网公开素材——bilifont（MIT，主站 iconfont）A 组 +",
        "// bili_icon_pack/vanfont（官网视频详情页图标字体）B 组。",
        "// 坐标：viewport 960×960（bbox 归一化居中），绝对值 M/L/Q/C/Z。",
        "",
        "/// 本项目字形码点 → B 站官网矢量路径。",
        "const Map<int, String> kBiliSiteIconPaths = {",
    ]
    count = 0
    for name, (fam, cp) in TARGETS.items():
        if name.startswith("carrier_"):
            key = CARRIER_SUBTITLES_OUTLINED
        else:
            if name not in cp_by_name:
                print(f"缺少 Cupertino 字形 {name}", file=sys.stderr)
                return 1
            key = cp_by_name[name]
        d = extract(fonts[fam], cp)
        lines.append(f"  0x{key:x}: '{d}',")
        count += 1
        print(f"OK  {name:<28} <- {fam} U+{cp:04X}")
    lines.append("};")
    lines.append("")
    out = os.path.join("lib", "theme", "app_icons_bili.g.dart")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"\ntotal={count} → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

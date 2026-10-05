# -*- coding: utf-8 -*-
"""B 站官网 BDC/界面图标字体导入器（阶段5e-L5-10）

来源：B 站官网各页面加载的 svg-next 图标字体（官方设计组件）：

1. 消息中心：https://message.bilibili.com/ → BDC-erj847ivanq.css/.ttf
2. 稍后再看：https://www.bilibili.com/watchlater/list → BDC-lc2pwexdhd8.css/.ttf
3. 空间页：https://space.bilibili.com/2 → freshspace-zpjpp3aqht.css/.ttf
4. 视频页稍后再看图标：官方页面内联 SVG（video-watchlater-icon）

处理：字体轮廓 → bbox 归一化（等比适配 870 盒、居中于 960 视口）→
y 轴翻转 → 绝对 M/L/Q/C/Z（空格分隔，适配 miuixParsePath）。
内联 SVG 走同一归一化后直接输出（evenodd 以 "eo|" 前缀标注）。

输出：lib/theme/app_icons_bdc.g.dart（按本项目调色板码点索引）
运行：python tools/bili_bdc_icons_import.py
"""
import glob
import gzip
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
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")

BDC_MSG = ("https://s1.hdslb.com/bfs/svg-next/font/2024-08-21/"
           "BDC-erj847ivanq")
BDC_WL = ("https://s1.hdslb.com/bfs/svg-next/font/2024-06-06/"
          "BDC-lc2pwexdhd8")
FSP = ("https://s1.hdslb.com/bfs/svg-next/font/2025-10-27/"
       "freshspace-zpjpp3aqht")
VIDEO_URL = "https://www.bilibili.com/video/BV17x411w7KC/"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

FONTS = {"msg": BDC_MSG, "wl": BDC_WL, "fsp": FSP}

# (本项目字形名, 包, 来源字体, 来源类名)
# 来源字体 "svg" = 官方页面内联 SVG（按 class 关键词提取）
ENTRIES = [
    # ── 视频互动 6 按钮 ──
    ("hand_thumbsup", "cupertino", "msg", "sic-BDC-hand_thumbsup_line"),
    ("hand_thumbsup_fill", "cupertino", "msg", "sic-BDC-hand_thumbsup_fill"),
    ("hand_thumbsdown", "cupertino", "msg", "sic-BDC-hand_thumbsdown_line"),
    ("hand_thumbsdown_fill", "cupertino", "msg",
     "sic-BDC-hand_thumbsdown_fill"),
    ("money_dollar_circle", "cupertino", "msg", "sic-BDC-coin_text_line"),
    ("money_dollar_circle_fill", "cupertino", "msg",
     "sic-BDC-coin_text_fill"),
    ("star", "cupertino", "msg", "sic-BDC-star_favorite_line"),
    ("star_fill", "cupertino", "msg", "sic-BDC-star_favorite_fill"),
    ("share", "cupertino", "msg", "sic-BDC-arrow_share_line"),
    ("time", "cupertino", "svg", "video-watchlater-icon"),
    # ── 评论区 / 动态 / 消息中心互动 ──
    ("reply", "cupertino", "msg", "sic-BDC-bubble_chat_line"),
    ("chat_bubble_text", "cupertino", "msg", "sic-BDC-bubble_comment_line"),
    ("arrow_2_circlepath", "cupertino", "msg", "sic-BDC-arrow_cycle_line"),
    ("chevron_down", "cupertino", "msg", "sic-BDC-arrow_expand_line"),
    ("chevron_up", "cupertino", "msg", "sic-BDC-arrow_collapse_line"),
    ("alternate_email_rounded", "material", "msg", "sic-BDC-at_line"),
    ("campaign_outlined", "material", "msg", "sic-BDC-speaker_notice_line"),
    # ── 空间 / 收藏夹 / 历史 / 稍后再看 按钮 ──
    ("add", "cupertino", "fsp", "sic-BDC-plus_add_line"),
    ("checkmark", "cupertino", "fsp", "sic-BDC-checkmark_line"),
    ("lock", "cupertino", "fsp", "sic-BDC-lock_locked_line"),
    ("lock_fill", "cupertino", "fsp", "sic-BDC-lock_locked_fill"),
    ("refresh", "cupertino", "fsp", "sic-BDC-arrow_refresh_line"),
    ("eye", "cupertino", "fsp", "sic-BDC-eye_browse_line"),
    ("doc_on_doc", "cupertino", "fsp", "sic-BDC-copy_line"),
    ("delete", "cupertino", "fsp", "sic-BDC-trash_delete_line"),
    ("folder", "cupertino", "fsp", "sic-fsp-fav_line"),
    ("ellipsis", "cupertino", "wl", "sic-BDC-more_horizontal_fill"),
    ("mail", "cupertino", "msg", "sic-BDC-envelope_message_line"),
    ("slash_circle", "cupertino", "msg", "sic-BDC-person_blacklist_line"),
]

NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"


def expand_hv(d: str) -> str:
    """规范化为 M/L/Q/C/Z 绝对命令（miuixParsePath 子集）。"""
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
            raise ValueError(f"未知命令 {cmd!r}")
    return " ".join(out)


def fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={
        "User-Agent": UA, "Accept-Encoding": "identity"})
    with urllib.request.urlopen(req, timeout=90) as resp:
        raw = resp.read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    return raw


def fetch_text(url: str) -> str:
    return fetch_bytes(url).decode("utf-8", errors="replace")


def parse_classes(css: str):
    """类名 → 码点（兼容单/双引号 content）。"""
    m = {}
    for mm in re.finditer(
            r"\.(sic-[\w-]+)::after[^}]*content:\s*['\"]\\(e[0-9a-fA-F]{3,6})"
            r"['\"]", css):
        m.setdefault(mm.group(1), int(mm.group(2), 16))
    return m


def font_extract(font: TTFont, cp: int) -> str:
    gname = font.getBestCmap().get(cp)
    if gname is None:
        raise ValueError(f"字体缺少码点 U+{cp:04X}")
    gs = font.getGlyphSet()
    bpen = BoundsPen(gs)
    gs[gname].draw(bpen)
    if not bpen.bounds:
        raise ValueError(f"字形 U+{cp:04X} 无轮廓")
    x0, y0, x1, y1 = bpen.bounds
    s = 870.0 / max(x1 - x0, y1 - y0)
    tr = Transform(s, 0, 0, -s,
                   480 - s * (x0 + x1) / 2, 480 + s * (y0 + y1) / 2)
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.1f}")
    gs[gname].draw(TransformPen(pen, tr))
    d = pen.getCommands()
    d = " ".join(re.sub(r"([A-Za-z])", r" \1 ", d).split())
    return expand_hv(d)


def normalize_svg_path(d: str) -> str:
    """SVG path（可能含相对/H/V/S/T）→ 绝对 → bbox 归一化居中 960。"""
    toks = re.findall(r"[MmLlHhVvCcSsQqTtAaZz]|" + NUM, d)
    if any(t in "Aa" for t in toks):
        raise ValueError("pathData 含弧线命令")
    out = []
    x = y = sx = sy = 0.0
    px = py = 0.0
    prev = ""
    i = 0

    def num():
        nonlocal i
        v = float(toks[i]); i += 1
        return v

    while i < len(toks):
        t = toks[i]
        if re.fullmatch(r"[MmLlHhVvCcSsQqTtZz]", t):
            cmd = t; i += 1
        else:
            cmd = {"M": "L", "m": "l"}.get(prev, prev)
        rel = cmd.islower()
        c = cmd.upper()
        if c == "Z":
            out.append("Z"); x, y = sx, sy; prev = cmd; continue
        first = True
        while i < len(toks) and re.fullmatch(NUM, toks[i]):
            if c == "M":
                nx, ny = num(), num()
                if rel:
                    nx, ny = x + nx, y + ny
                x, y = nx, ny
                if first:
                    sx, sy = x, y; out += ["M", f"{x:.1f}", f"{y:.1f}"]
                else:
                    out += ["L", f"{x:.1f}", f"{y:.1f}"]
            elif c == "L":
                nx, ny = num(), num()
                if rel:
                    nx, ny = x + nx, y + ny
                x, y = nx, ny; out += ["L", f"{x:.1f}", f"{y:.1f}"]
            elif c == "H":
                nx = num(); x = x + nx if rel else nx
                out += ["L", f"{x:.1f}", f"{y:.1f}"]
            elif c == "V":
                ny = num(); y = y + ny if rel else ny
                out += ["L", f"{x:.1f}", f"{y:.1f}"]
            elif c in ("C", "S"):
                if c == "C":
                    x1, y1, x2, y2, nx, ny = (num() for _ in range(6))
                else:
                    x1, y1 = x, y
                    x2, y2, nx, ny = (num() for _ in range(4))
                if rel:
                    x1, y1, x2, y2, nx, ny = (x + x1, y + y1, x + x2, y + y2,
                                              x + nx, y + ny)
                if c == "S":
                    x1, y1 = (2 * x - px, 2 * y - py) \
                        if prev.upper() in "CS" else (x, y)
                x, y = nx, ny; px, py = x2, y2
                out += ["C", f"{x1:.1f}", f"{y1:.1f}", f"{x2:.1f}",
                        f"{y2:.1f}", f"{x:.1f}", f"{y:.1f}"]
            elif c in ("Q", "T"):
                if c == "Q":
                    x1, y1, nx, ny = (num() for _ in range(4))
                else:
                    x1, y1 = x, y
                    nx, ny = num(), num()
                if rel:
                    x1, y1, nx, ny = x + x1, y + y1, x + nx, y + ny
                if c == "T":
                    x1, y1 = (2 * x - px, 2 * y - py) \
                        if prev.upper() in "QT" else (x, y)
                x, y = nx, ny; px, py = x1, y1
                out += ["Q", f"{x1:.1f}", f"{y1:.1f}", f"{x:.1f}", f"{y:.1f}"]
            first = False; prev = cmd
        prev = cmd
    merged = " ".join(out)
    xs, ys = [], []
    toks2 = merged.split()
    j = 0
    while j < len(toks2):
        c2 = toks2[j]; j += 1
        for _ in range({"M": 1, "L": 1, "Q": 2, "C": 3}.get(c2, 0)):
            xs.append(float(toks2[j])); ys.append(float(toks2[j + 1])); j += 2
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    s = 870.0 / max(x1 - x0, y1 - y0, 1e-6)
    tx, ty = 480 - s * (x0 + x1) / 2, 480 - s * (y0 + y1) / 2
    k = 0
    out2 = []
    while k < len(toks2):
        c3 = toks2[k]; k += 1
        out2.append(c3)
        for _ in range({"M": 1, "L": 1, "Q": 2, "C": 3}.get(c3, 0)):
            xx = float(toks2[k]); yy = float(toks2[k + 1]); k += 2
            out2 += [f"{s * xx + tx:.1f}", f"{s * yy + ty:.1f}"]
    return " ".join(out2)


def parse_palette_codepoints():
    """解析 cupertino_ui 与 material_ui 的 icons.dart → 名称到码点。"""
    cps = {"cupertino": {}, "material": {}}
    for kind, pkg_glob, _ in (("cupertino", "cupertino_ui-*", None),
                              ("material", "material_ui-*", None)):
        files = glob.glob(os.path.join(CACHE, pkg_glob, "lib", "src",
                                       "icons.dart"))
        if not files:
            print(f"找不到 {pkg_glob}", file=sys.stderr)
            return None
        src = open(files[0], encoding="utf-8").read()
        for m in re.finditer(
                r"static const IconData (\w+)\s*=\s*[\s\S]{0,40}?0x([0-9a-fA-F]+)",
                src):
            cps[kind].setdefault(m.group(1), int(m.group(2), 16))
    return cps


def render_dom(url: str) -> str:
    """Edge 无头渲染后 dump 完整 DOM（SSR 空壳图标由 JS 注入）。"""
    import subprocess
    p = subprocess.run(
        [EDGE, "--headless=new", "--disable-gpu",
         "--virtual-time-budget=15000", "--dump-dom", url],
        capture_output=True, timeout=180)
    if p.returncode != 0 or not p.stdout:
        raise RuntimeError(f"Edge dump-dom 失败 rc={p.returncode}")
    return p.stdout.decode("utf-8", errors="replace")


def main() -> int:
    cps = parse_palette_codepoints()
    if cps is None:
        return 1

    fonts = {}
    classes = {}
    for key, base in FONTS.items():
        css = fetch_text(base + ".css")
        ttf = fetch_bytes(base + ".ttf")
        fonts[key] = TTFont(__import__("io").BytesIO(ttf))
        classes[key] = parse_classes(css)
        print(f"FONT {key}: classes={len(classes[key])}")

    svg_page = render_dom(VIDEO_URL) if any(
        e[2] == "svg" for e in ENTRIES) else None

    lines = [
        "// GENERATED — 由 tools/bili_bdc_icons_import.py 生成，勿手改。",
        "// 来源：B 站官网 svg-next 图标字体（消息中心/稍后再看/空间页）",
        "//   + 视频页内联 SVG（官方设计组件 BDC / freshspace）。",
        "// 坐标：viewport 960×960（bbox 归一化居中），绝对值 M/L/Q/C/Z；",
        "// \"eo|\" 前缀 = evenodd 填充。",
        "",
        "/// 本项目字形码点 → B 站官网 BDC 图标矢量路径。",
        "const Map<int, String> kBDCIconPaths = {",
    ]
    count = 0
    for name, kind, fam, cls in ENTRIES:
        cp = cps[kind].get(name)
        if cp is None:
            print(f"缺少 {kind} 字形 {name}", file=sys.stderr)
            return 1
        if fam == "svg":
            if svg_page is None:
                print("缺少页面 HTML", file=sys.stderr)
                return 1
            m = re.search(
                r"<svg[^>]*" + re.escape(cls) + r"[^>]*>(.*?)</svg>",
                svg_page, re.S)
            if not m:
                print(f"未找到 SVG {cls}", file=sys.stderr)
                return 1
            d = None
            eo = False
            for pm in re.finditer(r"<path\b([^>]*?)/?>", m.group(1)):
                attrs = pm.group(1)
                dm = re.search(r'\bd="([^"]+)"', attrs)
                if dm:
                    d = dm.group(1)
                    eo = "evenodd" in attrs
                    break
            if d is None:
                print(f"SVG {cls} 无 path", file=sys.stderr)
                return 1
            data = ("eo|" if eo else "") + normalize_svg_path(d)
            note = f"svg:{cls}"
        else:
            font_cp = classes[fam].get(cls)
            if font_cp is None:
                print(f"类名缺失 {cls} @ {fam}", file=sys.stderr)
                return 1
            data = font_extract(fonts[fam], font_cp)
            note = f"{fam}:U+{font_cp:04X}"
        lines.append(f"  0x{cp:x}: '{data}',")
        count += 1
        print(f"OK  {name:<28} <- {cls} [{note}]")
    lines.append("};")
    lines.append("")
    out = os.path.join("lib", "theme", "app_icons_bdc.g.dart")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"\ntotal={count} → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

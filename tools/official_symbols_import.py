# -*- coding: utf-8 -*-
"""官方图标导入器（阶段5e-L5-7）

把两处**官方美术**引入项目矢量管线，仅覆盖 L5-6 手绘的 27 个字形
（"仅换自绘部分"）：

1. BiliPai 本地 VectorDrawable（Material Symbols 官方图集，Apache-2.0）
   → D:/Documents/GitHub/BiliPai/app/src/main/res/drawable/ms_*.xml
2. Google Material Symbols 官方仓库（补 BiliPai 未携带的缺口）
   → raw.githubusercontent.com/google/material-design-icons（rounded 风格）

处理：相对/绝对命令、隐式续行、S/T 平滑曲线 → 统一为绝对 M/L/Q/C/Z（空格
分隔，适配 miuixParsePath）；Google SVG 的 y 轴（viewBox 0 -960）平移 +960。

输出：lib/theme/app_icons_official.g.dart（码点 → 归一化路径，viewport 960）。

依赖：仅标准库（urllib）。
运行：python tools/official_symbols_import.py
"""
import glob
import os
import re
import sys
import urllib.request
from xml.etree import ElementTree

CACHE = os.path.join(os.environ.get("LOCALAPPDATA", ""),
                     "Pub", "Cache", "hosted", "pub.dev")
BILIPAI_DRAWABLE = ("D:/Documents/GitHub/BiliPai/app/src/main/res/drawable")
GOOGLE_RAW = ("https://raw.githubusercontent.com/google/material-design-icons/"
              "master/symbols/web/{name}/materialsymbolsrounded/"
              "{name}_24px.svg")

# 字形名（Cupertino 常量名） → 来源候选列表：
#   ("local", "<drawable 前缀>") | ("net", "<symbol 名>", "<回退名>...")
SOURCES = {
    "hand_thumbsup": [("local", "ms_thumb_up_off_alt_24")],
    "hand_thumbsup_fill": [("local", "ms_thumb_up_fill_24")],
    "hand_thumbsdown": [("net", "thumb_down")],
    "hand_thumbsdown_fill": [("net", "thumb_down")],
    "money_dollar_circle": [("net", "monetization_on"), ("net", "paid"),
                            ("net", "toll")],
    "money_dollar_circle_fill": [("net", "monetization_on"), ("net", "paid")],
    "person": [("local", "ms_person_24")],
    "person_fill": [("local", "ms_person_fill_24")],
    "fullscreen": [("local", "ms_fullscreen_24")],
    "fullscreen_exit": [("local", "ms_fullscreen_exit_24")],
    "square": [("local", "ms_open_in_full_24")],
    "square_fill": [("local", "ms_open_in_full_24")],
    "tv": [("local", "ms_picture_in_picture_24")],
    "speaker_1_fill": [("net", "volume_down")],
    "backward_fill": [("net", "fast_rewind")],
    "chat_bubble": [("net", "chat_bubble"), ("net", "chat")],
    "chat_bubble_fill": [("net", "chat")],
    "captions_bubble": [("local", "ms_subtitles_off_24")],
    "captions_bubble_fill": [("local", "ms_subtitles_24")],
    "bookmark": [("local", "ms_collections_bookmark_24")],
    "bookmark_fill": [("local", "ms_collections_bookmark_fill_24")],
    "circle": [("net", "radio_button_unchecked")],
    "check_mark_circled_solid": [("net", "radio_button_checked")],
    "exclamationmark_circle": [("local", "ms_warning_24"),
                               ("local", "ms_report_problem_24")],
    "play_circle": [("local", "ms_play_circle_24")],
    "calendar": [("local", "ms_calendar_month_24")],
    "bell_slash": [("net", "notifications_off")],
}

NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"


def parse_codepoints(icons_path, wanted):
    src = open(icons_path, encoding="utf-8").read()
    found = {}
    for m in re.finditer(
            r"static const IconData (\w+)\s*=\s*IconData\(\s*0x([0-9a-fA-F]+)",
            src):
        if m.group(1) in wanted:
            found[m.group(1)] = int(m.group(2), 16)
    missing = [n for n in wanted if n not in found]
    if missing:
        print(f"icons.dart 缺少：{missing}", file=sys.stderr)
        sys.exit(1)
    return found


def normalize_commands(d: str, y_offset: float) -> str:
    """相对/绝对 + 隐式续行 + S/T 平滑曲线 → 绝对 M/L/Q/C/Z（空格分隔）。"""
    toks = re.findall(r"[MmLlHhVvCcSsQqTtAaZz]|" + NUM, d)
    if any(t in "Aa" for t in toks):
        raise ValueError("pathData 含弧线命令（当前导入器未支持）")
    out = []
    x = y = sx = sy = 0.0      # 当前点 / 子路径起点
    px = py = 0.0              # 上一控制点（S/T 反射用）
    prev = ""
    i = 0

    def num():
        nonlocal i
        v = float(toks[i]); i += 1
        return v

    def emit(cmd, pts):
        out.append(cmd)
        out.extend(f"{v + (y_offset if k % 2 == 1 else 0):.1f}"
                   for k, v in enumerate(pts))

    while i < len(toks):
        t = toks[i]
        if re.fullmatch(r"[MmLlHhVvCcSsQqTtZz]", t):
            cmd = t; i += 1
        else:
            # 隐式续行：沿用上一条命令（M→L）
            cmd = {"M": "L", "m": "l"}.get(prev, prev)
        rel = cmd.islower()
        c = cmd.upper()
        if c == "Z":
            x, y = sx, sy
            out.append("Z")
            prev = cmd
            continue
        first = True
        while i < len(toks) and re.fullmatch(NUM, toks[i]):
            if c == "M":
                nx, ny = num(), num()
                if rel:
                    nx, ny = x + nx, y + ny
                x, y = nx, ny
                if first:
                    sx, sy = x, y
                    emit("M", (x, y))
                else:
                    emit("L", (x, y))
            elif c == "L":
                nx, ny = num(), num()
                if rel:
                    nx, ny = x + nx, y + ny
                x, y = nx, ny
                emit("L", (x, y))
            elif c == "H":
                nx = num()
                x = x + nx if rel else nx
                emit("L", (x, y))
            elif c == "V":
                ny = num()
                y = y + ny if rel else ny
                emit("L", (x, y))
            elif c in ("C", "S"):
                if c == "C":
                    x1, y1, x2, y2, nx, ny = (num() for _ in range(6))
                else:
                    x1, y1 = x, y
                    x2, y2, nx, ny = (num() for _ in range(4))
                if rel:
                    x1, y1 = x + x1, y + y1
                    x2, y2 = x + x2, y + y2
                    nx, ny = x + nx, y + ny
                if c == "S":
                    if prev.upper() in ("C", "S"):
                        x1, y1 = 2 * x - px, 2 * y - py
                    else:
                        x1, y1 = x, y
                x, y = nx, ny
                px, py = x2, y2
                emit("C", (x1, y1, x2, y2, x, y))
            elif c in ("Q", "T"):
                if c == "Q":
                    x1, y1, nx, ny = (num() for _ in range(4))
                else:
                    x1, y1 = x, y
                    nx, ny = num(), num()
                if rel:
                    x1, y1 = x + x1, y + y1
                    nx, ny = x + nx, y + ny
                if c == "T":
                    if prev.upper() in ("Q", "T"):
                        x1, y1 = 2 * x - px, 2 * y - py
                    else:
                        x1, y1 = x, y
                x, y = nx, ny
                px, py = x1, y1
                emit("Q", (x1, y1, x, y))
            first = False
            prev = cmd
        prev = cmd
    return " ".join(out)


def from_local(name: str) -> str:
    path = os.path.join(BILIPAI_DRAWABLE, f"{name}.xml")
    root = ElementTree.parse(path).getroot()
    d = root.find("{http://schemas.android.com/apk/res/android}path")
    if d is None:
        paths = root.iter("path")
        d = next(paths)
    return d.attrib["{http://schemas.android.com/apk/res/android}pathData"]


def from_net(name: str) -> str:
    url = GOOGLE_RAW.format(name=name)
    with urllib.request.urlopen(url, timeout=30) as resp:
        svg = resp.read().decode("utf-8")
    m = re.search(r'<path d="([^"]+)"', svg)
    if not m:
        raise ValueError(f"{name}: SVG 无 path")
    return m.group(1)


def main() -> int:
    icons = glob.glob(os.path.join(CACHE, "cupertino_ui-*", "lib", "src",
                                   "icons.dart"))
    if not icons:
        print("找不到 cupertino_ui", file=sys.stderr)
        return 1
    cps = parse_codepoints(icons[0], SOURCES.keys())

    entries = []
    unresolved = []
    for glyph, candidates in SOURCES.items():
        raw = None
        used = None
        for cand in candidates:
            try:
                if cand[0] == "local":
                    raw = from_local(cand[1])
                    y_off = 0.0        # Android VD：y 已向下、0..960
                else:
                    raw = from_net(cand[1])
                    y_off = 960.0      # Google SVG：viewBox 0 -960 960 960
                used = cand[1]
                break
            except Exception as e:  # noqa: BLE001
                continue
        if raw is None:
            unresolved.append(glyph)
            continue
        d = normalize_commands(raw, y_off)
        entries.append((cps[glyph], glyph, used, d))
        print(f"OK  {glyph:<26} <- {used}")

    lines = [
        "// GENERATED — 由 tools/official_symbols_import.py 生成，勿手改。",
        "// 来源：Material Symbols（Google，Apache-2.0）——"
        "本地 BiliPai VectorDrawable + 官方仓库补缺。",
        "// 坐标：viewport 960×960（Android 值域），绝对值 M/L/Q/C/Z 空格分隔。",
        "",
        "/// Cupertino 码点 → 官方矢量路径（L5-6 手绘的替代美术）。",
        "const Map<int, String> kOfficialIconPaths = {",
    ]
    for cp, _glyph, _used, d in entries:
        lines.append(f"  0x{cp:x}: '{d}',")
    lines.append("};")
    lines.append("")
    out = os.path.join("lib", "theme", "app_icons_official.g.dart")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"\nresolved={len(entries)}/{len(SOURCES)} → {out}")
    if unresolved:
        print(f"未解决（保留现自绘）：{unresolved}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

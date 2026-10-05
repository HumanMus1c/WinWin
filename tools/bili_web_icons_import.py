# -*- coding: utf-8 -*-
"""B 站官网 Web 端公开素材导入器（阶段5e-L5-9）

来源：**直接抓取官网页面**随服务端渲染下发的内联 SVG（真实官方美术）：
1. 视频详情页 https://www.bilibili.com/video/BV17x411w7KC/
   — 互动栏（video-like/coin/fav/share-icon）、元数据（view-icon）
2. 首页 https://www.bilibili.com/
   — 视频卡片统计图标（bili-video-card__stats--icon：播放量/弹幕数）

处理：SVG path（含相对/H/V/S/T 命令）→ 绝对 M/L/Q/C/Z（复用官方管线
normalize_commands）→ 全子路径合并 → bbox 归一化（等比 870 盒、居中于
960 视口，与其它层视觉重量对齐；SVG 为 y 向下坐标系，不做翻转）。
evenodd 图标以 "eo|" 前缀标注，运行时以 PathFillType.evenOdd 绘制。

输出：lib/theme/app_icons_web.g.dart（按本项目 Cupertino 调色板码点索引）
运行：python tools/bili_web_icons_import.py
"""
import glob
import os
import re
import sys
import urllib.request

VIDEO_URL = "https://www.bilibili.com/video/BV17x411w7KC/"
HOME_URL = "https://www.bilibili.com/"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
CACHE = os.path.join(os.environ.get("LOCALAPPDATA", ""),
                     "Pub", "Cache", "hosted", "pub.dev")

# 本项目字形名 → (页面, svg class 关键词, 第几个匹配, 来源模式)
# 来源模式："http" = 直接抓 SSR HTML；"render" = Edge 无头渲染后 dump DOM
# （部分图标 SSR 为空壳，运行时由 JS 注入）。
# 说明：官网互动按钮**无双态变体**（同形变色）；本层按"官网观感优先"接入：
#   · 点赞激活态 = 官网页实心拇指（常态描边保留官方 off_alt，满足常态描边要求）
#   · 投币       = 官网 ¥ 硬币（描边造型，两态同形，与官网一致）
#   · 分享/播放量/弹幕数 = 官网单形图标
TARGETS = {
    "hand_thumbsup_fill": (VIDEO_URL, "video-like-icon", 0, "http"),
    "money_dollar_circle": (VIDEO_URL, "video-coin-icon", 0, "http"),
    "money_dollar_circle_fill": (VIDEO_URL, "video-coin-icon", 0, "http"),
    "share": (VIDEO_URL, "video-share-icon", 0, "http"),
    "play_circle": (VIDEO_URL, "view-icon", 0, "render"),
    "carrier_subtitles_outlined":
        (HOME_URL, "bili-video-card__stats--icon", 1, "render"),
}

CARRIER_SUBTITLES_OUTLINED = 0xF3FD  # material Icons.subtitles_outlined

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"


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


def walk_abs(d: str, fn):
    """遍历绝对 M/L/Q/C/Z 路径，对每个坐标调用 fn(x, y)（用于 bbox 与变换）。

    返回重建后的路径字符串（坐标以 fn 返回值替换，保留 1 位小数）。
    """
    toks = d.split()
    out = []
    i = 0
    while i < len(toks):
        cmd = toks[i]; i += 1
        out.append(cmd)
        pairs = {"M": 1, "L": 1, "Q": 2, "C": 3}.get(cmd, 0)
        for _ in range(pairs):
            x = float(toks[i]); y = float(toks[i + 1]); i += 2
            out.append(f"{fn(x, y)[0]:.1f}")
            out.append(f"{fn(x, y)[1]:.1f}")
    return " ".join(out)


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Accept-Encoding": "identity",  # 尽量请求未压缩（服务器可能忽略）
    })
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
    if raw[:2] == b"\x1f\x8b":          # gzip 魔数兜底
        import gzip
        raw = gzip.decompress(raw)
    return raw.decode("utf-8", errors="replace")


def extract_svgs(html: str):
    """提取全部 <svg> 块 → [{cls, paths:[(d, evenodd)]}]。"""
    svgs = []
    for m in re.finditer(r"<svg\b([^>]*)>(.*?)</svg>", html, re.S):
        attrs, inner = m.group(1), m.group(2)
        cls = re.search(r'class="([^"]*)"', attrs)
        paths = []
        for p in re.finditer(r"<path\b([^>]*?)/?>", inner):
            a = p.group(1)
            d = re.search(r'\bd="([^"]+)"', a)
            if not d:
                continue
            eo = ("evenodd" in a) or ('fill="none"' in a)
            if 'fill="none"' in a:
                continue  # 描边型 path 不支持（官网当前图标均为填充型）
            paths.append((d.group(1), eo))
        if paths:
            svgs.append({"cls": cls.group(1) if cls else "", "paths": paths})
    return svgs


def pick(svgs, keyword: str, index: int):
    hits = [s for s in svgs if keyword in s["cls"]]
    if len(hits) <= index:
        raise ValueError(f"未找到 svg class 含 {keyword!r} 的第 {index} 个")
    return hits[index]


def render_dom(url: str) -> str:
    """Edge 无头渲染后 dump 完整 DOM（SSR 空壳图标由 JS 注入）。"""
    import subprocess
    args = [EDGE, "--headless=new", "--disable-gpu",
            "--virtual-time-budget=12000", "--dump-dom", url]
    p = subprocess.run(args, capture_output=True, timeout=180)
    if p.returncode != 0 or not p.stdout:
        raise RuntimeError(f"Edge dump-dom 失败 rc={p.returncode}")
    return p.stdout.decode("utf-8", errors="replace")


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

    pages = {}

    def svgs_of(url: str, mode: str):
        key = f"{mode}:{url}"
        if key not in pages:
            html = fetch(url) if mode == "http" else render_dom(url)
            pages[key] = html
            print(f"{mode.upper():<6} {url} → svg 块 {len(extract_svgs(html))}")
        return extract_svgs(pages[key])

    lines = [
        "// GENERATED — 由 tools/bili_web_icons_import.py 生成，勿手改。",
        "// 来源：B 站官网 Web 端页面内联 SVG（视频详情页互动栏/元数据 + 首页卡片统计）。",
        "// 坐标：viewport 960×960（bbox 归一化居中），绝对值 M/L/Q/C/Z；",
        "// \"eo|\" 前缀 = evenodd 填充（PathFillType.evenOdd）。",
        "",
        "/// 本项目字形码点 → B 站官网 Web 端矢量路径。",
        "const Map<int, String> kWebIconPaths = {",
    ]
    count = 0
    for name, (url, keyword, idx, mode) in TARGETS.items():
        if name.startswith("carrier_"):
            key = CARRIER_SUBTITLES_OUTLINED
        else:
            if name not in cp_by_name:
                print(f"缺少 Cupertino 字形 {name}", file=sys.stderr)
                return 1
            key = cp_by_name[name]
        svg = pick(svgs_of(url, mode), keyword, idx)
        abs_parts = [normalize_commands(d, 0.0) for d, _ in svg["paths"]]
        merged = " ".join(abs_parts)
        xs, ys = [], []

        def collect(x, y, xs=xs, ys=ys):
            xs.append(x); ys.append(y)
            return x, y

        walk_abs(merged, collect)
        x0, x1 = min(xs), max(xs)
        y0, y1 = min(ys), max(ys)
        s = 870.0 / max(x1 - x0, y1 - y0, 1e-6)
        tx = 480 - s * (x0 + x1) / 2
        ty = 480 - s * (y0 + y1) / 2
        d = walk_abs(merged, lambda x, y: (s * x + tx, s * y + ty))
        eo = any(e for _, e in svg["paths"])
        data = ("eo|" if eo else "") + d
        lines.append(f"  0x{key:x}: '{data}',")
        count += 1
        print(f"OK  {name:<28} <- [{keyword} #{idx}]"
              f"{' [evenodd]' if eo else ''} subpaths={len(svg['paths'])}")
    lines.append("};")
    lines.append("")
    out = os.path.join("lib", "theme", "app_icons_web.g.dart")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"\ntotal={count} → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

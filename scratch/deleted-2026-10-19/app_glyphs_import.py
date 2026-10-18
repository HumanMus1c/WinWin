# AI生成
# -*- coding: utf-8 -*-
"""b7-d 图标载体去库：生成项目自有字形表 `lib/theme/app_glyphs.g.dart`。

背景：`lib/theme/app_icons.dart`（87 处）与 `lib/common/widgets/level_icon.dart`
（2 处）仍以 `Icons.xx` 作为字形载体，是 material_ui 库级退役闸门（lib import=0）
的最后两处字形残点。这些 `Icons.xx` 是 material_ui 的 IconData **常量**，
`AppIcon` 经 `miuixVectorForGlyph(codePoint)` 查矢量层；codePoint 一旦改变
即导致矢量层失配 + 回退字形错位。

因此本生成器从 material_ui 的 `icons.dart` **原样抄录** 这些常量的
`(codePoint, fontFamily: 'MaterialIcons')`，产出**零视觉变化**的项目自有载体：
- codePoint 完全相同 → Miuix/B站/官方美术矢量层命中结果不变；
- fontFamily 仍为 'MaterialIcons'（Flutter SDK 自带该字体，与 material_ui 无关）
  → 未命中矢量的字形回退渲染与现状逐像素一致。

运行：python tools/app_glyphs_import.py
输出：lib/theme/app_glyphs.g.dart
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MU_ICONS = os.path.join(
    os.environ.get("LOCALAPPDATA", ""), "Pub", "Cache", "hosted",
    "pub.flutter-io.cn", "material_ui-1.5.0", "lib", "src", "icons.dart")
if not os.path.isfile(MU_ICONS):
    MU_ICONS = os.path.join(
        os.environ.get("LOCALAPPDATA", ""), "Pub", "Cache", "hosted",
        "pub.dev", "material_ui-1.5.0", "lib", "src", "icons.dart")

SOURCES = [
    os.path.join(ROOT, "lib", "theme", "app_icons.dart"),
    os.path.join(ROOT, "lib", "common", "widgets", "level_icon.dart"),
]
OUT = os.path.join(ROOT, "lib", "theme", "app_glyphs.g.dart")

# --- 1. material_ui 常量名 → codePoint（容忍定义跨行） ---
icons = {}
with open(MU_ICONS, encoding="utf-8") as f:
    txt = f.read()
for m in re.finditer(
        r"static const IconData (\w+) = IconData\(\s*(0x[0-9a-fA-F]+)", txt):
    icons[m.group(1)] = int(m.group(2), 16)

# --- 2. 源码中真实引用（剥离注释后再取词，规避文档注释里的 `Icons.xxx`） ---
def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    s = re.sub(r"//[^\n]*", "", s)
    return s

names = set()
for path in SOURCES:
    with open(path, encoding="utf-8") as f:
        body = strip_comments(f.read())
    names.update(re.findall(r"(?<![A-Za-z0-9_])(?:Icons|AppGlyphs)\.(\w+)", body))

missing = sorted(n for n in names if n not in icons)
if missing:
    raise SystemExit("未在 material_ui 找到定义：%s" % missing)

ordered = sorted(names)

# --- 3. 生成 ---
lines = [
    "// GENERATED — 由 tools/app_glyphs_import.py 生成，勿手改。",
    "// 来源：material_ui 1.5.0 lib/src/icons.dart 常量的 (codePoint, fontFamily)",
    "// 原样抄录（b7-d 载体去库）。codePoint 与 fontFamily 均保持与 material 一致，",
    "// 故矢量层命中与回退渲染结果逐像素不变；仅解除对 material_ui 的 import 依赖。",
    "//",
    "// ignore_for_file: constant_identifier_names",
    "",
    "import 'package:flutter/widgets.dart';",
    "",
    "/// 项目自有字形载体（b7-d）。命名与 material `Icons` 逐一同名，便于对照审计。",
    "abstract final class AppGlyphs {",
]
for n in ordered:
    cp = icons[n]
    lines.append(
        "  static const IconData %s = IconData(0x%x, fontFamily: 'MaterialIcons');"
        % (n, cp))
lines.append("}")
lines.append("")

with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))

print("字形数：%d" % len(ordered))
print("输出：%s" % OUT)
for n in ordered:
    print("  %-34s 0x%05x" % (n, icons[n]))
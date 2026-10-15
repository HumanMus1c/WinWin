# B7 毛玻璃面板「边缘无渐变」收口 —— MiuixOverlayPanel / MiuixFrostedSurface

- 日期：2026-10-16
- 基线：`89b9f9b`（main clean）
- 触发：CVO 实机反馈「MiuixOverlayPanel 四周边缘观感不一致」，要求「先去除四周模糊渐变，再按推荐方向修复」

## 一、根因（代码 + 截图逐像素实测）

### 1. 代码侧
`MiuixOverlayPanel` 的边缘由三层材质叠出，且口径分散：

- 外层 `Container`：`borderRadius:12`（只为投影）+ `boxShadow(offset (0,4), blur 16)`
- 中层 `ClipRRect(12)` → `BackdropFilter(blur σ=16)`
- 内层 `Container`：`color = base×0.85`、`borderRadius:12`、`border:1px`（暗 `white α0.12` / 亮 `black α0.08`）

问题：
- **圆角半径写了三处（12/12/12）**，1px 描边画在 `ClipRRect` 同半径的内边界上，易被抗锯齿吞掉 → 四边「有的有线、有的没有」。
- **1px 描边太弱**（α0.12 白压在已与背景混合的底上，理论仅 +~20），撑不起稳定边线。
- **投影 `offset (0,4)` 天生不对称**：仅下边有投影。

### 2. 截图实测（401×338，Pillow/numpy 逐像素剖面）
四条边的垂直/水平剖面**都没有清晰的 1px 亮线**，全是平滑渐变，宽度 ≈ 3σ = 48px（恰好是 `BackdropFilter` 模糊核可见扩散范围）：

| 边 | 取样 | 过渡 | 跨度 |
|---|---|---|---|
| 左 | y=170 | 73 → 47 | Δ26 / ~37px |
| 右 | y=170 | 47 → 118 | Δ~71 / ~50px |
| 上 | x=120 | 89 → 50 | Δ39 / ~35px |
| 下 | x=120 | 41 → 63 | Δ22 / ~36px |

即：**边缘可见度完全由 `BackdropFilter` 的「边界夹断渐变」决定** —— 模糊核在面板边界被 clamp，把面板外侧的亮/暗背景「拖」进可视区；因背景（视频画面）四边明暗不同，四条边的渗色幅度差 3 倍以上 → 四处观感不一致，四角更像两段叠加。

### 3. 附加放大因素
调用方（弹幕样式 / 表情 / 右键 / 文本操作）均用 `Fade + ScaleTransition(0.92→1)` 且锚点为**某个角**；非整数倍率下逐帧重栅格化，1px 描边与圆角落到不同亚像素相位，动画期「一边清晰一边发虚」更明显。

## 二、改动

### 1. 去边缘模糊渐变（核心，`MiuixFrostedSurface._edgeSafeFrost`）
把模糊层向**外扩 `3σ`（=48px）**，伸到 `ClipRRect` 裁剪区之外，让「边界夹断渐变」整体落在可见区外：

```
ClipRRect(radius)
  └ Stack(clipBehavior: Clip.none)
      ├ Positioned(-bleed,-bleed,-bleed,-bleed) → BackdropFilter(blur σ) → ColoredBox(α0.85)
      └ child                      // 非定位子，决定 Stack 尺寸 = 可见面板尺寸
```

可视四条边因此变成**清晰的硬边**，面板内部毛玻璃不变。

### 2. 描边移出裁剪层 + 提高对比（推荐方向 #1/#2）
描边改由面板档外层 `Container.foregroundDecoration` 画（前景层，不被 `ClipRRect` 抗锯齿吞掉），α 由 `0.12/0.08` 上调到 `0.18/0.12`。全宽档仍只画底边 1px。

### 3. 圆角单一来源（推荐方向 #3）
`MiuixOverlayPanel` 不再自持材质，改为**复用 `MiuixFrostedSurface`**（半径默认 12、blur 16、投影/描边/边缘无渐变单点承担），只在其上补标题行与内边距。

### 4. 保留项（有意不动）
- **4px 下投影**：是既定设计（浮层需要下投影），不做对称化。
- **对角缩放动画锚点**：是既定交互（贴触发器对角展开），保留。

## 三、影响面
- `lib/common/widgets/miuix_frosted_surface.dart`：材质单一来源；`AppTabBar`（分类标签条/按钮行）同步获得「边缘无渐变 + 描边更清晰」。
- `lib/common/widgets/miuix_overlay_panel.dart`：材质改走共享件，外观要素不变。
- 弹幕样式面板 / 表情面板 / 右键菜单 / 文本操作菜单：无调用签名变化。

## 四、复验步骤
1. 视频页点「弹幕样式」按钮 → 面板展开：四边应为**清晰硬边**，不再有朝背景拖尾的模糊渐变；四边一致。
2. 打开表情面板、右键菜单、文本选中菜单：四边观感一致。
3. 空间页/结果页标签条（`AppTabBar`）：滚动内容从其后经过仍呈模糊，标签条四边为硬边、描边清晰。
4. 亮/暗主题各看一次：描边可见且一致。

## 五、验证
- `flutter analyze`（两文件）：**No issues found**。
- Debug 构建：**√ Built** `build\windows\x64\runner\Debug\winwin.exe`（54.7s）。
- Release：Dart/AOT 编译完成（114.7s），仅在拷贝 `WebView2Loader.dll` 时失败——被**正在运行的 winwin(PID 32616)** 锁定其 Release 输出目录（环境占用，非代码问题）；未结束该进程。
# flutter_miuix 复测补修轮（Toast 回退 / 经验条满格）复盘 — 2026-10-03

> 五要素结构。触发：批次1 复测反馈（Toast 未 Miuix 化；经验条不可见）。

## 一、分析根因

1. **Toast 恒落 M3 分支**：无 context 路径（`showAppSnackBar`——网络错误等主路径）
   经 `messenger.context` 传入；ScaffoldMessenger 位于 `MaterialApp.builder` 链
   **之上**，取不到 `UiStyleScope`，而 `InheritedUiStyle.of` 设计为静默回退
   `material3` → 恒 M3 分支。且 miuix 分支沿用 MD3 反色深卡配色，观感无差别
   （双重原因叠加成"没变化"）。
2. **经验条不可见**：LV6/上限未知（`nextExp=null`，界面"6.3万/–"）时——
   profile 页 `progress=null` → `AppProgressBar` 按 0 渲染**空轨道**（复测截图）；
   用户空间页 `LevelExpBar` 在 `isMax` 时**直接不渲染进度条** → "看不到"。

## 二、设计修复

- `InheritedUiStyle` 新增 `maybeOf`（无作用域返回 null；`of` 保持原回退语义）；
  `app_messenger` 风格解析改为 `maybeOf(context) ?? UiStyleNotifier.instance.value`
  （全局来源，运行时与作用域始终同步）。
- Toast miuix 卡片：改用桥接调色板（浅色 `surfaceContainer` 底 +
  `onSurfaceContainer` 文字——MIUI 通知条语言；按 `Theme.brightness` 选暗色
  调色板）；`_measureCardWidth` 改为按分支实际文本样式测量。
- profile 页：进度 = 常规 `curExp/nextExp`（clamp 1.0）；满级/上限未知且有经验值
  → 1.0 满格。
- `LevelExpBar`：移除 `if (!isMax)` 隐藏；始终显示进度条（isMax 时 progress 即 1.0）。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **127/127 通过**（+1：无 context 路径回退 notifier 回归） |
| 双构建 | `windows --debug` ✅ / `--release` ✅（Release 待用户关闭 winwin.exe 后补跑通过） |

### 实机验证（待做）

- [ ] 1. 触发网络错误类 Toast（无 context 路径）：应为 Miuix 浅色通知条卡（暗色模式深色卡）。
- [ ] 2. 「我的」页头像下经验条：LV6 显示满格（不再是空轨道）。
- [ ] 3. 用户空间页：经验条可见（满级=满格 + "已达到最高等级"）。
- [ ] 4. 页面内调用（如未加载提示）Toast 仍为 Miuix 样式。

## 四、本轮总结

- 改动面：5 文件（+114/−60）。
- 教训归档：**凡"执行位置可能在样式作用域之上"的调用点**（ScaffoldMessenger、
  全局 Overlay 等），风格解析必须提供全局回退（本轮回退链：maybeOf → notifier）；
  已由回归用例锁定该路径。

## 五、GitHub commit 提交记录

- 补修提交：`77e8696973e1fa6a76ab78b8bbfcd27bc156d831`（[fix](miuix): 复测补修—Toast 无 context 回退（恒 M3 分支）+ 经验条满格两处，5 文件 / +114 −60；按全局开发规定补记）。
- 本 `[docs]` 提交随同推送 `origin/main`。

#ifndef RUNNER_BLACKBOX_H_
#define RUNNER_BLACKBOX_H_

#include <windows.h>

// 启动黑箱（原生侧）— 诊断"偶尔启动白屏"。
//
// 与 Dart 侧 StartupBlackbox（Documents/logs/blackbox_dart.log）配合，
// 本模块写 Documents/logs/blackbox_native.log，两侧时间戳均为本地墙钟，
// 可交叉对齐还原完整启动时间线。
//
// 能力：
// - 毫秒级启动时间线埋点（进程入口 → 建窗 → 引擎创建 → 首帧呈现 → 显示）
// - 首帧看门狗：2.5s 一查，8s 仍未首帧自动截图取证，15s 停止
// - 首帧后白屏扫描：+2s/+6s 截图并统计近白像素比例，输出 SUSPECT 结论
// - DXGI 适配器/显示器信息（定位 GPU 切换、驱动、远程会话问题）
// - 截图自动保留最近 4 张（Documents/logs/blackbox/shot_*.bmp）
//
// 所有 IO 失败静默降级（内存缓冲或丢弃），绝不影响启动主流程。
namespace blackbox {

// 在 wWinMain 最开始调用：解析日志目录、写会话头。幂等。
void Init();

// 记录一条黑箱日志：本地墙钟毫秒 + 进程相对毫秒。Init 前调用进入
// pending 缓冲，Init 后按序补写。
void Log(const char* tag, _Printf_format_string_ const char* fmt, ...);

// 记录 DXGI 适配器/输出信息。需在 CoInitializeEx 之后调用。
void DumpGpuInfo();

// FlutterViewController 创建完成时记录基准（计算首帧延迟）。
void MarkControllerCreated();

// 引擎首帧回调触发时调用：记录首帧延迟、停止看门狗、调度 +2s/+6s 白屏扫描。
void NotifyFirstFrame(HWND hwnd);

// 启动首帧看门狗（在 SetNextFrameCallback 注册后调用）。
void StartPreFrameWatchdog(HWND hwnd);

}  // namespace blackbox

#endif  // RUNNER_BLACKBOX_H_

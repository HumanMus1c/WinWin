import 'dart:ffi';
import 'dart:io' as io;

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/window/native_tray.dart';

/// 应用「真正退出」的统一入口。
///
/// 对齐上游 PiliPlus：先落盘并关闭存储、移除原生托盘图标，再**硬终止**本进程
/// （Windows `TerminateProcess(GetCurrentProcess(), 0)`，其它平台 `exit(0)`），
/// **不调用 `windowManager.destroy()`** ⇒ 不触发 Flutter 引擎 / ANGLE 的 D3D 设备
/// 析构，从而绕开 Intel 核显驱动 `igd10um64xe.DLL` 在析构路径上的崩溃
/// （签名 `0xc0000409`，见局域网测试机诊断记忆）。
///
/// Windows 走硬终止亦是为规避 flutter_inappwebview 已知退出问题（与上游注释同源）。
///
/// 注意：这里终止的是 **WinWin 自身进程**，不是 OfficeAce 宿主。
abstract final class AppExit {
  static bool _exiting = false;

  /// 真正退出应用（幂等；Windows 上调用后不再返回）。
  static Future<void> exit() async {
    if (_exiting) return;
    _exiting = true;

    // 先落盘，避免硬终止丢失未刷写的数据。
    try {
      await GStorage.compact();
      await GStorage.close();
    } catch (_) {}

    // 移除原生托盘图标，避免硬终止后残留「幽灵图标」。
    await NativeTray.instance.setVisible(false);

    if (io.Platform.isWindows) {
      _terminateProcess();
    } else {
      io.exit(0);
    }
  }

  /// Windows 硬终止当前进程（不走引擎优雅析构）。
  static void _terminateProcess() {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess =
        kernel32.lookupFunction<IntPtr Function(), int Function()>(
      'GetCurrentProcess',
    );
    final terminateProcess = kernel32
        .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'TerminateProcess',
    );
    terminateProcess(getCurrentProcess(), 0);
  }
}
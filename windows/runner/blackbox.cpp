#include "blackbox.h"

#include <dwmapi.h>
#include <dxgi.h>
#include <knownfolders.h>
#include <shlobj.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <list>
#include <string>
#include <vector>

// 老 SDK 兜容定义。
#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif
#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 0x00000002
#endif

namespace blackbox {
namespace {

constexpr size_t kMaxLogBytes = 2 * 1024 * 1024;  // 超过则滚动为 .old
constexpr int kKeepShots = 4;                     // 截图保留最近 N 张
constexpr UINT_PTR kWatchdogTimerId = 0xB0B1;
constexpr UINT_PTR kPostFrameTimerId = 0xB0B2;

SRWLOCK g_lock = SRWLOCK_INIT;
HANDLE g_file = INVALID_HANDLE_VALUE;
std::wstring g_dir;       // Documents/logs
std::wstring g_shot_dir;  // Documents/logs/blackbox
bool g_init_tried = false;
std::list<std::string> g_pending;

LARGE_INTEGER g_qpc_freq{};
LARGE_INTEGER g_qpc_t0{};
double g_controller_ms = -1.0;  // FlutterViewController 创建时刻
double g_first_frame_ms = -1.0; // 首帧回调时刻
HWND g_watch_hwnd = nullptr;
bool g_noframe_shot_taken = false;
int g_scan_round = 0;

double QpcMs() {
  if (g_qpc_freq.QuadPart == 0) return 0.0;
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return (now.QuadPart - g_qpc_t0.QuadPart) * 1000.0 /
         g_qpc_freq.QuadPart;
}

void LocalTimestamp(char* buf, size_t cap) {
  SYSTEMTIME st;
  GetLocalTime(&st);
  snprintf(buf, cap, "%04d-%02d-%02d %02d:%02d:%02d.%03d", st.wYear,
           st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
           st.wMilliseconds);
}

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int need = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(),
                                 nullptr, 0, nullptr, nullptr);
  std::string out(need > 0 ? need : 0, '\0');
  if (need > 0) {
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), out.data(),
                        need, nullptr, nullptr);
  }
  return out;
}

// 调用方需持有 g_lock。
void WriteRaw(const std::string& line) {
  if (g_file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(g_file, line.c_str(), (DWORD)line.size(), &written, nullptr);
  FlushFileBuffers(g_file);  // 立即落盘，进程瞬死不丢尾部
}

// ---------- 截图 + 白屏分析 ----------

void PruneShots() {
  if (g_shot_dir.empty()) return;
  std::wstring pattern = g_shot_dir + L"\\shot_*.bmp";
  WIN32_FIND_DATAW fd;
  std::vector<std::wstring> names;
  HANDLE h = FindFirstFileW(pattern.c_str(), &fd);
  if (h == INVALID_HANDLE_VALUE) return;
  do {
    names.push_back(fd.cFileName);
  } while (FindNextFileW(h, &fd));
  FindClose(h);
  // 文件名以零填充时间戳开头，字典序降序 = 新→旧。
  std::sort(names.begin(), names.end(), std::greater<std::wstring>());
  for (size_t i = kKeepShots; i < names.size(); ++i) {
    DeleteFileW((g_shot_dir + L"\\" + names[i]).c_str());
  }
}

// 截取客户区为 24bpp BMP 并做白屏统计分析。
//
// 判定指标（避免加载占位页误报）：
// - nearWhite：RGB 全 ≥245 的像素占比（纯白底）
// - chromatic：存在明显色相差的像素占比（蓝色加载圈/彩色 UI → 非白屏）
// - dark：暗色文字/边框占比
// 近白 ≥95% 且彩色与暗色几乎为零 → SUSPECT。
bool CaptureAndScan(HWND hwnd, const wchar_t* label) {
  if (hwnd == nullptr || !IsWindow(hwnd)) {
    Log("scan", "skip: invalid hwnd");
    return false;
  }
  if (!IsWindowVisible(hwnd)) {
    Log("scan", "skip: window not visible");
    return false;
  }
  RECT rc{};
  GetClientRect(hwnd, &rc);
  const int w = rc.right - rc.left;
  const int h = rc.bottom - rc.top;
  if (w <= 0 || h <= 0) {
    Log("scan", "skip: empty client rect");
    return false;
  }

  HDC wnd_dc = GetDC(hwnd);
  HDC mem_dc = CreateCompatibleDC(wnd_dc);
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = h;  // bottom-up
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 24;
  void* bits = nullptr;
  HBITMAP dib =
      CreateDIBSection(wnd_dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (dib == nullptr || bits == nullptr) {
    if (dib) DeleteObject(dib);
    DeleteDC(mem_dc);
    ReleaseDC(hwnd, wnd_dc);
    Log("scan", "CreateDIBSection failed");
    return false;
  }
  HGDIOBJ old = SelectObject(mem_dc, dib);
  // PrintWindow(PW_RENDERFULLCONTENT) 优先；对 Flutter 加速子窗口它可能
  // 返回全黑（实测如此），此时回退屏幕级 BitBlt 抓 DWM 合成结果。
  const char* source = "n/a";
  BOOL ok = PrintWindow(hwnd, mem_dc, PW_RENDERFULLCONTENT);
  if (!ok) {
    ok = BitBlt(mem_dc, 0, 0, w, h, wnd_dc, 0, 0, SRCCOPY);
    source = "bitblt_client";
  } else {
    source = "printwindow";
  }

  bool suspect = false;
  std::wstring filename;
  if (!ok) {
    Log("scan", "capture failed (PrintWindow+BitBlt), gle=%lu", GetLastError());
  } else {
    const int stride = ((w * 3 + 3) / 4) * 4;
    BYTE* base = (BYTE*)bits;
    auto analyze = [&](double* out) {
      const int step = (w / 320) + 1;
      long total = 0, near_white = 0, chromatic = 0, dark = 0;
      double sr = 0, sg = 0, sb = 0;
      for (int y = 0; y < h; y += step) {
        const BYTE* row = base + (size_t)y * stride;
        for (int x = 0; x < w; x += step) {
          const BYTE* px = row + (size_t)x * 3;  // BGR
          const int b = px[0], g = px[1], r = px[2];
          ++total;
          sr += r; sg += g; sb += b;
          const int mx = std::max(r, std::max(g, b));
          const int mn = std::min(r, std::min(g, b));
          if (r >= 245 && g >= 245 && b >= 245) ++near_white;
          if (mx - mn > 40) ++chromatic;
          if ((r + g + b) / 3 < 100) ++dark;
        }
      }
      if (total <= 0) {
        out[0] = out[1] = out[2] = out[3] = out[4] = out[5] = out[6] = 0;
        return;
      }
      out[0] = 100.0 * near_white / total;  // nearWhite %
      out[1] = 100.0 * chromatic / total;   // chromatic %
      out[2] = 100.0 * dark / total;        // dark %
      out[3] = sr / total;                  // avg r
      out[4] = sg / total;                  // avg g
      out[5] = sb / total;                  // avg b
      out[6] = (double)total;
    };

    double m[7]{};
    analyze(m);
    if (m[2] >= 99.5 && m[3] < 2 && m[4] < 2 && m[5] < 2) {
      // 全黑：PrintWindow 拿不到加速内容 → 屏幕坐标 BitBlt 重抓。
      POINT tl{};
      ClientToScreen(hwnd, &tl);
      HDC screen_dc = GetDC(nullptr);
      if (screen_dc) {
        BitBlt(mem_dc, 0, 0, w, h, screen_dc, tl.x, tl.y,
               SRCCOPY | CAPTUREBLT);
        ReleaseDC(nullptr, screen_dc);
        source = "bitblt_screen";
        analyze(m);
      }
    }

    if (m[6] > 0) {
      const double nw = m[0], ch = m[1], dk = m[2];
      const double ar = m[3], ag = m[4], ab = m[5];
      suspect = nw >= 95.0 && ch < 0.1 && dk < 0.5;

      // 落盘文件名：shot_时间戳_label.bmp（字典序即时间序）。
      SYSTEMTIME st;
      GetLocalTime(&st);
      wchar_t name[64];
      swprintf_s(name, L"shot_%04d%02d%02d_%02d%02d%02d_%03d_%s.bmp",
                 st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
                 st.wSecond, st.wMilliseconds, label);
      filename = name;

      if (!g_shot_dir.empty()) {
        HANDLE f = CreateFileW((g_shot_dir + L"\\" + filename).c_str(),
                               GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0,
                               nullptr);
        if (f != INVALID_HANDLE_VALUE) {
          const DWORD pixels = (DWORD)stride * h;
          BITMAPFILEHEADER fh{};
          fh.bfType = 0x4D42;  // 'BM'
          fh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
          fh.bfSize = fh.bfOffBits + pixels;
          DWORD written = 0;
          WriteFile(f, &fh, sizeof(fh), &written, nullptr);
          WriteFile(f, &bi, sizeof(BITMAPINFOHEADER), &written, nullptr);
          WriteFile(f, bits, pixels, &written, nullptr);
          CloseHandle(f);
          PruneShots();
        } else {
          filename.clear();
        }
      }

      Log("scan",
          "label=%s src=%s size=%dx%d nearWhite=%.1f%% chromatic=%.2f%% "
          "dark=%.2f%% avg=(%d,%d,%d) SUSPECT=%d shot=%s",
          WideToUtf8(label).c_str(), source, w, h, nw, ch, dk, (int)ar,
          (int)ag, (int)ab, suspect ? 1 : 0,
          filename.empty() ? "(save failed)"
                           : WideToUtf8(filename).c_str());
    }
  }

  SelectObject(mem_dc, old);
  DeleteObject(dib);
  DeleteDC(mem_dc);
  ReleaseDC(hwnd, wnd_dc);
  return suspect;
}

// ---------- 看门狗与首帧后扫描 ----------

VOID CALLBACK PreFrameTimerProc(HWND hwnd, UINT msg, UINT_PTR id, DWORD tick) {
  if (g_first_frame_ms >= 0.0 || g_watch_hwnd == nullptr) {
    KillTimer(nullptr, id);
    return;
  }
  const double el = QpcMs();
  BOOL visible = IsWindowVisible(g_watch_hwnd);
  DWORD cloaked = 0;
  DwmGetWindowAttribute(g_watch_hwnd, DWMWA_CLOAKED, &cloaked,
                        sizeof(cloaked));
  RECT rc{};
  GetClientRect(g_watch_hwnd, &rc);
  Log("watchdog",
      "first frame NOT presented after %.0fms (windowVisible=%d "
      "cloaked=%lu clientRect=%ldx%ld)",
      el, visible, cloaked, rc.right - rc.left, rc.bottom - rc.top);
  if (el >= 8000 && !g_noframe_shot_taken) {
    g_noframe_shot_taken = true;
    Log("watchdog", "capturing evidence screenshot (no first frame)");
    CaptureAndScan(g_watch_hwnd, L"no_first_frame");
  }
  if (el >= 15000) {
    Log("watchdog", "watchdog giving up after 15s without first frame");
    KillTimer(nullptr, id);
  }
}

VOID CALLBACK PostFrameTimerProc(HWND hwnd, UINT msg, UINT_PTR id, DWORD tick) {
  KillTimer(nullptr, id);
  const int round = ++g_scan_round;
  if (round > 2) return;
  if (round == 1) {
    // 首帧呈现是启动白屏最核心的证物：画面若白，此截图即为现场。
    CaptureAndScan(g_watch_hwnd, L"post_first_frame_2s");
    SetTimer(nullptr, kPostFrameTimerId, 4000, PostFrameTimerProc);
  } else {
    CaptureAndScan(g_watch_hwnd, L"post_first_frame_6s");
  }
}

}  // namespace

void Init() {
  AcquireSRWLockExclusive(&g_lock);
  if (g_init_tried) {
    ReleaseSRWLockExclusive(&g_lock);
    return;
  }
  g_init_tried = true;
  QueryPerformanceFrequency(&g_qpc_freq);
  QueryPerformanceCounter(&g_qpc_t0);
  ReleaseSRWLockExclusive(&g_lock);

  // 解析 Documents/logs（与 Dart 侧 runtime.log 同目录）。
  PWSTR docs = nullptr;
  wchar_t dir[MAX_PATH] = {};
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &docs))) {
    return;
  }
  swprintf_s(dir, L"%s\\logs", docs);
  CoTaskMemFree(docs);
  CreateDirectoryW(dir, nullptr);
  wchar_t shot[MAX_PATH] = {};
  swprintf_s(shot, L"%s\\blackbox", dir);
  g_shot_dir = shot;
  CreateDirectoryW(g_shot_dir.c_str(), nullptr);

  wchar_t logpath[MAX_PATH] = {};
  swprintf_s(logpath, L"%s\\blackbox_native.log", dir);

  // 滚动：超限则移为 .old。
  HANDLE probe = CreateFileW(logpath, GENERIC_READ,
                             FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                             OPEN_EXISTING, 0, nullptr);
  if (probe != INVALID_HANDLE_VALUE) {
    LARGE_INTEGER sz{};
    if (GetFileSizeEx(probe, &sz) &&
        sz.QuadPart > (LONGLONG)kMaxLogBytes) {
      wchar_t old[MAX_PATH] = {};
      swprintf_s(old, L"%s.old", logpath);
      MoveFileExW(logpath, old, MOVEFILE_REPLACE_EXISTING);
    }
    CloseHandle(probe);
  }

  AcquireSRWLockExclusive(&g_lock);
  g_dir = dir;
  g_file = CreateFileW(logpath, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                       OPEN_ALWAYS, 0, nullptr);
  // 补写 Init 前缓冲的日志（正常情况下为空）。
  for (const auto& l : g_pending) WriteRaw(l);
  g_pending.clear();
  ReleaseSRWLockExclusive(&g_lock);

  // 会话头 + pid + Flutter 版本（跨会话对齐用）。
  char ts[40];
  LocalTimestamp(ts, sizeof(ts));
  Log("blackbox", "==== native session start %s pid=%lu flutter=%s ====",
      ts, GetCurrentProcessId(), FLUTTER_VERSION);

  char deskName[256] = {};
  HDESK hDesk = GetThreadDesktop(GetCurrentThreadId());
  DWORD deskLen = 0;
  if (GetUserObjectInformationA(hDesk, UOI_NAME, deskName, sizeof(deskName), &deskLen)) {
    Log("blackbox", "thread desktop: %s", deskName);
  }
}

void Log(const char* tag, const char* fmt, ...) {
  char msg[1024];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(msg, sizeof(msg), fmt, ap);
  va_end(ap);

  char ts[40];
  LocalTimestamp(ts, sizeof(ts));
  char line[1200];
  snprintf(line, sizeof(line), "%s [%8.1fms] %-10s | %s\n", ts, QpcMs(),
           tag, msg);

  AcquireSRWLockExclusive(&g_lock);
  if (g_file != INVALID_HANDLE_VALUE) {
    WriteRaw(line);
  } else {
    g_pending.push_back(line);
    if (g_pending.size() > 256) g_pending.pop_front();
  }
  ReleaseSRWLockExclusive(&g_lock);
}

void DumpGpuInfo() {
  IDXGIFactory1* factory = nullptr;
  HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    Log("gpu", "CreateDXGIFactory1 failed hr=0x%08lX", (unsigned long)hr);
    return;
  }
  for (UINT i = 0; i < 4; ++i) {
    IDXGIAdapter1* ad = nullptr;
    if (factory->EnumAdapters1(i, &ad) == DXGI_ERROR_NOT_FOUND) break;
    DXGI_ADAPTER_DESC1 d{};
    ad->GetDesc1(&d);
    Log("gpu",
        "adapter[%u] \"%s\" vram=%lluMB sysmem=%lluMB shared=%lluMB "
        "vendorId=0x%04X deviceId=0x%04X",
        i, WideToUtf8(d.Description).c_str(),
        (unsigned long long)(d.DedicatedVideoMemory >> 20),
        (unsigned long long)(d.DedicatedSystemMemory >> 20),
        (unsigned long long)(d.SharedSystemMemory >> 20), d.VendorId,
        d.DeviceId);
    // 该适配器挂载的显示器（多屏/远程会话线索）。
    UINT j = 0;
    IDXGIOutput* out = nullptr;
    while (j < 8 && ad->EnumOutputs(j, &out) != DXGI_ERROR_NOT_FOUND) {
      DXGI_OUTPUT_DESC od{};
      out->GetDesc(&od);
      Log("gpu", "adapter[%u] output[%u] attached=%d desktop=(%ld,%ld)-(%ld,%ld)",
          i, j, od.AttachedToDesktop, od.DesktopCoordinates.left,
          od.DesktopCoordinates.top, od.DesktopCoordinates.right,
          od.DesktopCoordinates.bottom);
      out->Release();
      ++j;
    }
    ad->Release();
  }
  factory->Release();
}

void MarkControllerCreated() {
  g_controller_ms = QpcMs();
  Log("flutter", "FlutterViewController created");
}

void NotifyFirstFrame(HWND hwnd) {
  const double now = QpcMs();
  g_first_frame_ms = now;
  if (g_controller_ms >= 0.0) {
    Log("firstframe", "engine presented first frame (%.1fms after controller)",
        now - g_controller_ms);
  } else {
    Log("firstframe", "engine presented first frame");
  }
  KillTimer(nullptr, kWatchdogTimerId);
  g_watch_hwnd = hwnd;
  SetTimer(nullptr, kPostFrameTimerId, 2000, PostFrameTimerProc);
}

void StartPreFrameWatchdog(HWND hwnd) {
  g_watch_hwnd = hwnd;
  SetTimer(nullptr, kWatchdogTimerId, 2500, PreFrameTimerProc);
  Log("watchdog", "pre-first-frame watchdog armed (2.5s tick)");
}

}  // namespace blackbox

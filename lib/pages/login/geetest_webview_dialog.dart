import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/core/account/account.dart' show NoAccount;
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/ui/components/app_progress.dart';

/// 极验验证码 JS 资源（gt.0.5.0.js 旧版 / fullpage 新版均可）。
const _geetestJsUri =
    'https://static.geetest.com/static/js/fullpage.0.0.0.js';

/// 拼接 Geetest 初始化 JS：注册 success/error/close 回调，onReady 时自动 verify。
String _buildShowJs(String configResponse) =>
    't=Geetest($configResponse).onSuccess(()=>R("success",t.getValidate())).onError(o=>R("error",o)).onClose(o=>R("close",o));t.onReady(()=>t.verify())';

/// 极验验证码 WebView 全屏覆盖层（移植自 PiliPlus
/// `lib/pages/login/geetest/geetest_webview_dialog.dart`）。
///
/// WinWin 仅支持桌面端（Windows），故移除 Linux 的 `desktop_webview_window`
/// 兜底分支，仅保留 `InAppWebView` 实现；承载形态为**半透明覆盖层铺满全窗口**
/// （barrier 压暗 42% + 容器/页面底透明；2026-10-02 四次调整）；
/// 不含关闭按钮：出口 = Esc（AppEscapeScope layer1）或极验页自身关闭回调。
///
/// 流程：
///   1. 通过 `https://api.geetest.com/gettype.php?gt=<gt>` 获取极验配置（JSONP）。
///   2. 拼装 Geetest 初始化 config（含 gt / challenge / product=bind 等）。
///   3. 在 `InAppWebView` 中加载本地 HTML，注入 gt.js + Geetest(config)。
///   4. JS 端通过 `flutter_inappwebview.callHandler('success', validate)` 回传
///      `{geetest_validate, geetest_seccode, geetest_challenge}`。
///   5. 覆盖层通过 `Navigator.pop(result)` 把 Map 返回给调用方。
class GeetestWebviewDialog extends StatefulWidget {
  const GeetestWebviewDialog(this.gt, this.challenge, {super.key});

  final String gt;
  final String challenge;

  @override
  State<GeetestWebviewDialog> createState() => _GeetestWebviewDialogState();

  /// 弹出极验验证全屏覆盖层，返回 `{geetest_validate, geetest_seccode, geetest_challenge}`
  /// 或 null（用户取消 / 验证失败）。
  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    String gt,
    String challenge,
  ) {
    return showAppDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      // 灰蒙层：与 BiliPai `setDimAmount(0.42)` 对齐（登录页透出、压暗）。
      barrierColor: AppColors.black.withValues(alpha: 0.42),
      builder: (_) => GeetestWebviewDialog(gt, challenge),
    );
  }
}

class _GeetestWebviewDialogState extends State<GeetestWebviewDialog> {
  late final Future<LoadingState<String>> _future;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _future = _getConfig(widget.gt, widget.challenge);
  }

  /// 从极验 gettype.php 拉取配置（返回 JSONP `( {...} )`），解析并拼装 config。
  static Future<LoadingState<String>> _getConfig(
    String gt,
    String challenge,
  ) async {
    try {
      final res = await Request().get<String>(
        'https://api.geetest.com/gettype.php',
        queryParameters: {'gt': gt},
        options: Options(
          responseType: ResponseType.plain,
          extra: {'account': const NoAccount()},
        ),
      );
      if (res.data case final String data) {
        if (data.startsWith('(') && data.endsWith(')')) {
          final Map<String, dynamic> config;
          try {
            config = jsonDecode(data.substring(1, data.length - 1));
          } catch (e) {
            return Error(e.toString());
          }
          if (config['status'] == 'success') {
            return Success(
              jsonEncode(
                config['data'] as Map<String, dynamic>..addAll({
                  'gt': gt,
                  'challenge': challenge,
                  'offline': false,
                  'new_captcha': true,
                  'product': 'bind',
                  'width': '100%',
                  'https': true,
                  'protocol': 'https://',
                }),
              ),
            );
          } else {
            return Error(data);
          }
        }
      }
      return Error('geetest 配置获取失败');
    } catch (e) {
      return Error('geetest 配置获取失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 半透明覆盖层铺满全窗口（四次调整）：
    // - 无可见容器底色（透明），由路由 barrier 压暗（42%），登录页整体透出；
    // - 已按需求移除左上角关闭按钮：出口 = Esc（AppEscapeScope layer1）
    //   或极验页自身关闭回调（onClose → Navigator.pop）。
    return SizedBox.expand(
      child: Material(
        color: AppColors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<LoadingState<String>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: AppProgressIndicator());
                }
                final config = snapshot.data!;
                if (config is Error) {
                  return _ErrorView(
                    message: config.errMsg ?? '配置获取失败',
                    onClose: () => Navigator.of(context).pop(),
                  );
                }
                final response = (config as Success<String>).response;
                return _GeetestWebView(
                  response: response,
                  onResult: (data) => Navigator.of(context).pop(data),
                  onCancel: () => Navigator.of(context).pop(),
                  onLoadStop: () {
                    if (mounted) setState(() => _loading = false);
                  },
                );
              },
            ),
            if (_loading)
              const Center(child: AppProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

/// 极验 WebView 主体：加载本地 HTML（含 gt.js + R=callHandler 桥），
/// 页面加载完成后注入 `_buildShowJs(config)` 启动验证。
class _GeetestWebView extends StatefulWidget {
  const _GeetestWebView({
    required this.response,
    required this.onResult,
    required this.onCancel,
    required this.onLoadStop,
  });

  final String response;
  final ValueChanged<Map<String, dynamic>> onResult;
  final VoidCallback onCancel;
  final VoidCallback onLoadStop;

  @override
  State<_GeetestWebView> createState() => _GeetestWebViewState();
}

class _GeetestWebViewState extends State<_GeetestWebView> {
  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useHybridComposition: false,
        algorithmicDarkeningAllowed: true,
        useShouldOverrideUrlLoading: true,
        // 页面底透明（WebView2 DefaultBackgroundColor alpha=0）：消除初始化
        // 白屏闪烁，并让登录页在验证码周围透出。
        transparentBackground: true,
        // 桌面端兼容（避免 MIXED_CONTENT_ALWAYS_ALLOW 等 Android 专属枚举）。
        incognito: true,
        allowFileAccess: false,
        allowContentAccess: false,
        useOnDownloadStart: false,
        thirdPartyCookiesEnabled: false,
        safeBrowsingEnabled: false,
        isFraudulentWebsiteWarningEnabled: false,
        domStorageEnabled: false,
        databaseEnabled: false,
        cacheEnabled: false,
        horizontalScrollBarEnabled: false,
        verticalScrollBarEnabled: false,
      ),
      initialData: InAppWebViewInitialData(
        data:
            '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">'
            '<style>html,body{margin:0;height:100%;background:transparent !important;}</style></head><body>'
            '<script src="$_geetestJsUri"></script>'
            '<script>R=flutter_inappwebview.callHandler</script>'
            '</body></html>',
      ),
      onWebViewCreated: (ctr) {
        ctr
          ..addJavaScriptHandler(
            handlerName: 'success',
            callback: (args) {
              if (args.isNotEmpty) {
                if (args[0] case Map<String, dynamic> data) {
                  widget.onResult(data);
                  return;
                }
              }
              debugPrint('geetest invalid result: $args');
            },
          )
          ..addJavaScriptHandler(
            handlerName: 'error',
            callback: (args) {
              debugPrint('geetest error: $args');
            },
          )
          ..addJavaScriptHandler(
            handlerName: 'close',
            callback: (args) => widget.onCancel(),
          );
      },
      onLoadStop: (ctr, _) async {
        widget.onLoadStop();
        await ctr.evaluateJavascript(
          source: _buildShowJs(widget.response),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.error(), size: 48, color: AppColors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppThemeHost.of(context).text.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onClose, child: const Text('关闭')),
          ],
        ),
      ),
    );
  }
}

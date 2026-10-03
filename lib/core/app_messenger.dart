import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/theme/ui_style_notifier.dart';

/// 应用级 ScaffoldMessenger 句柄（挂载于 `MaterialApp.scaffoldMessengerKey`）。
///
/// 供没有 BuildContext 的异步/深层调用点弹提示使用（例如网络错误 toast）。
/// 取代此前与纯 MaterialApp 架构不兼容、会抛异步异常的 GetX Snackbar。
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 浮层提示卡的最大宽度（含内边距）。
const double _toastMaxWidth = 400;

/// 提示卡内容区水平内边距（单侧）。
const double _toastHorizontalPadding = 20;

/// 提示卡距屏幕两侧的最小总留白（`SnackBar.width` 模式无水平 margin）。
const double _toastScreenInset = 32;

/// 显示一条浮层提示。
///
/// **Miuix**（flutter_miuix）：经 [MiuixToastHost] 渲染——整卡上浮渐显 /
/// 上浮渐隐；反色半透明卡（亮色主题用暗卡、暗色主题用亮卡，统一不透明度
/// 见 [kMiuixSurfaceAlpha]）。
/// **Material 3**：沿用 `SnackBar` 浮动卡（冻结，仅必要修复）。
///
/// - 宽度自适应内容：短消息为紧凑小卡，长消息在 [_toastMaxWidth] 内换行；
/// - 点击卡片任意处立即关闭；同屏仅一条：最新优先。
void showToast(BuildContext context, String message, {Duration? duration}) {
  final style =
      InheritedUiStyle.maybeOf(context) ?? UiStyleNotifier.instance.value;
  if (style == UiStyle.miuix) {
    _presentMiuixToast(message, duration);
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  _presentToast(context, messenger, message, duration: duration);
}

/// 显示一条应用级浮层提示（[showToast] 的无 BuildContext 版本）。
///
/// Miuix 路径完全无 context 依赖（请求经 [miuixToastRequest] 直达宿主）；
/// M3 路径在启动早期 ScaffoldMessenger 尚未挂载时静默忽略。
void showAppSnackBar(String message, {Duration? duration}) {
  if (UiStyleNotifier.instance.value == UiStyle.miuix) {
    _presentMiuixToast(message, duration);
    return;
  }
  final messenger = appScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  _presentToast(messenger.context, messenger, message, duration: duration);
}

// ── Miuix Toast 通道（请求 → MiuixToastHost） ──

int _miuixToastSeq = 0;

/// 最新一条 Miuix Toast 请求（携带自增序号以区分同文案请求）。
final ValueNotifier<MiuixToastRequest?> miuixToastRequest =
    ValueNotifier<MiuixToastRequest?>(null);

/// 一条 Miuix Toast 请求。
@immutable
class MiuixToastRequest {
  const MiuixToastRequest({
    required this.message,
    required this.duration,
    required this.seq,
  });

  final String message;
  final Duration duration;
  final int seq;
}

void _presentMiuixToast(String message, Duration? duration) {
  miuixToastRequest.value = MiuixToastRequest(
    message: message,
    duration: duration ?? const Duration(seconds: 4),
    seq: ++_miuixToastSeq,
  );
}

/// Miuix Toast 宿主：挂在应用根部（`MaterialApp.builder` 的 miuix 分支）。
///
/// 监听 [miuixToastRequest]，以"整卡上浮渐显 / 上浮渐隐"呈现（复测反馈：
/// 替代 `SnackBar` 的横向分展过渡）；卡面为反色半透明材质，点击即关，
/// 同屏仅一条（新请求直接替换并重新上浮）。
class MiuixToastHost extends StatefulWidget {
  const MiuixToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<MiuixToastHost> createState() => _MiuixToastHostState();
}

class _MiuixToastHostState extends State<MiuixToastHost>
    with SingleTickerProviderStateMixin {
  MiuixToastRequest? _request;
  bool _visible = false;
  Timer? _timer;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    miuixToastRequest.addListener(_onRequest);
    _anim.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    miuixToastRequest.removeListener(_onRequest);
    _anim.removeStatusListener(_onStatus);
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_visible && mounted) {
      setState(() => _request = null);
    }
  }

  void _onRequest() {
    final req = miuixToastRequest.value;
    if (req == null || !mounted) return;
    _timer?.cancel();
    setState(() {
      _request = req;
      _visible = true;
    });
    _anim.forward(from: 0);
    _timer = Timer(req.duration, _hide);
  }

  void _hide() {
    if (!_visible) return;
    _timer?.cancel();
    setState(() => _visible = false);
    _anim.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final req = _request;
    // StackFit.expand：宿主按最大约束铺满（否则无定位子级时 Stack 收缩到
    // 内容尺寸，定位的 Toast 卡会被绘制在命中区域之外、无法点击）。
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (req != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 64,
            child: Center(
              child: _MiuixToastCard(
                key: ValueKey(req.seq),
                message: req.message,
                leaving: !_visible,
                animation: _anim,
                onTap: _hide,
              ),
            ),
          ),
      ],
    );
  }
}

class _MiuixToastCard extends StatelessWidget {
  const _MiuixToastCard({
    super.key,
    required this.message,
    required this.leaving,
    required this.animation,
    required this.onTap,
  });

  final String message;
  final bool leaving;
  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayText = _breakLongSegments(message);
    // 反色卡：亮色主题用暗卡（inverseSurface），暗色主题用亮卡；
    // 半透明底（统一不透明度 kMiuixSurfaceAlpha）。
    final textStyle = TextStyle(fontSize: 14, color: cs.onInverseSurface);
    final width = _measureCardWidth(context, displayText, textStyle);
    // 文本基底：覆写 WidgetsApp 的默认"黄绿双下划线"错误样式
    // （根部宿主不在 Material 子树内，Text 合并到该样式）。
    final bodyStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      decoration: TextDecoration.none,
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(animation.value);
        // 进入：自下而上（+24 → 0）渐显；退出：继续上浮（0 → -24）渐隐。
        final dy = (1 - progress) * 24 * (leaving ? -1 : 1);
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      },
      child: DefaultTextStyle(
        style: bodyStyle,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: MiuixSurface(
            cornerRadius: 16,
            color: cs.inverseSurface.withValues(alpha: kMiuixSurfaceAlpha),
            contentColor: cs.onInverseSurface,
            shadowElevation: 8,
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _toastHorizontalPadding,
                  vertical: 15,
                ),
                child: Text(displayText, style: textStyle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── M3 通道（SnackBar；按冻结策略仅保留必要修复） ──

void _presentToast(
  BuildContext context,
  ScaffoldMessengerState messenger,
  String message, {
  Duration? duration,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _buildToast(
        context,
        message,
        () => messenger.hideCurrentSnackBar(),
        duration: duration,
      ),
    );
}

/// 构建统一提示卡：内边距归零让点击区域（[GestureDetector]）铺满整卡，
/// 并按文本测量结果显式指定卡片宽度（自适应内容）。
SnackBar _buildToast(
  BuildContext context,
  String message,
  VoidCallback onDismiss, {
  Duration? duration,
}) {
  final theme = Theme.of(context);
  final displayText = _breakLongSegments(message);
  final textStyle = theme.snackBarTheme.contentTextStyle ??
      theme.textTheme.bodyMedium ??
      const TextStyle(fontSize: 14);
  return SnackBar(
    width: _measureCardWidth(context, displayText, textStyle),
    padding: EdgeInsets.zero,
    duration: duration ?? const Duration(seconds: 4),
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _toastHorizontalPadding,
          vertical: 15,
        ),
        child: Text(displayText),
      ),
    ),
  );
}

/// 按内容测量卡片宽度：取各硬换行段落的最长单行宽，封顶 [_toastMaxWidth]，
/// 并保证不超出屏幕（两侧共留 [_toastScreenInset]）。
///
/// [textStyle] 须与实际渲染文本一致（Miuix / M3 通道分别传入）。
double _measureCardWidth(
  BuildContext context,
  String text,
  TextStyle textStyle,
) {
  final scaler = MediaQuery.textScalerOf(context);

  var naturalWidth = 0.0;
  for (final line in text.split('\n')) {
    final painter = TextPainter(
      text: TextSpan(text: line, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    naturalWidth = math.max(naturalWidth, painter.size.width);
    painter.dispose();
  }

  final contentWidth = math.min(
    naturalWidth,
    _toastMaxWidth - _toastHorizontalPadding * 2,
  );
  final screenLimit = MediaQuery.sizeOf(context).width - _toastScreenInset;
  return math.min(contentWidth + _toastHorizontalPadding * 2, screenLimit);
}

/// 为超长不可断片段（如 URL）插入零宽空格断点：让换行优先落在
/// `/ ? # & = . _ - :` 等分隔符之后，避免 URL 被字符级硬断或整段撑宽。
String _breakLongSegments(String text) {
  final longToken = RegExp(r'\S{24,}');
  final separators = RegExp(r'([/?#&=._\-:]+)');
  return text.replaceAllMapped(
    longToken,
    (token) => token[0]!.replaceAllMapped(separators, (m) => '${m[1]}\u200B'),
  );
}

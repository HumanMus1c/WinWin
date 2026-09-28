import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/login.dart';
import 'package:winwin/models/common/account_type.dart';
import 'package:winwin/pages/login/geetest_webview_dialog.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 登录页（移植自 PiliPlus `lib/pages/login/`）。
///
/// 与 PiliPlus 登录途径一致，提供 4 种登录方式：
///   1. 密码登录（含 RSA 加密 stub + 极验风控）
///   2. 短信验证码登录（含极验风控）
///   3. 扫码登录（TV 端二维码，扫码失败自动刷新 + 手动刷新按钮）
///   4. Cookie 登录
///
/// 不引入 GetX / flutter_smart_dialog / pretty_qr_code：
///   - 用 [Navigator] 替代 GetX 路由
///   - 用 [SnackBar] 替代 SmartDialog.showToast
///   - QR 用在线图片服务渲染
///
/// 极验验证码通过 [GeetestWebviewDialog]（flutter_inappwebview）实现，
/// 密码登录与短信发送遇到风控（code=-105 / recaptcha_url）会弹出滑块验证，
/// 验证通过后递归重试原请求（与 PiliPlus `getCaptcha + 回调` 模式一致）。
///
/// 已知限制（与 PiliPlus 对齐时的 stub）：
///   - RSA 密码加密未实现（需引入 `encrypt` 包），密码以 salt+plaintext 发送
///   - 密码登录返回 status==2（需安全中心手机号验证）的完整流程未实现
Future<void> showLoginPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const LoginPage(),
      fullscreenDialog: true,
    ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /// 当前选中的登录方式索引。
  int _currentTab = 0;

  /// 已访问过的 tab 集合（用于懒初始化 + 状态保留）。
  /// QR tab 在首次访问前不会开始轮询，与原 TabBarView 行为一致。
  final Set<int> _visited = {0};

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 登录成功后统一处理：写入账号 → 激活 buvid → 拉取用户信息 → 关闭页面。
  ///
  /// 注意：onLoginMain() 现在由 Accounts.set() 内部调用（移植自 PiliPlus），
  /// 不需要在此处单独调用。Accounts.set() 会先激活 buvid3，再调 onLoginMain()。
  Future<void> _setAccount(
    Map<String, dynamic> tokenInfo,
    List cookieInfo,
  ) async {
    try {
      final account = LoginAccount(
        BiliCookieJarHelper.fromList(cookieInfo),
        tokenInfo['access_token'] as String?,
        tokenInfo['refresh_token'] as String?,
        {AccountType.main},
      );
      await account.onChange();
      // Accounts.set 会依次执行：保存 → 激活 buvid → onLoginMain（拉取用户信息）
      await Accounts.set(AccountType.main, account);
      _toast('登录成功');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('登录成功但设置账号失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        leading: const AppBackButton(),
      ),
      body: Column(
        children: [
          // ── 风格自适应分段控件：切换 4 种登录方式 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Style.lg,
              Style.sm,
              Style.lg,
              Style.md,
            ),
            child: AppSegmentedControl<int>(
              segments: const [
                (0, '密码'),
                (1, '短信'),
                (2, '扫码'),
                (3, 'Cookie'),
              ],
              value: _currentTab,
              onChanged: (v) => setState(() {
                _currentTab = v;
                _visited.add(v);
              }),
            ),
          ),
          const Divider(height: 1),
          // ── 内容区：懒加载 + 状态保留 ──
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [
                if (_visited.contains(0))
                  _PasswordLoginTab(
                    onToast: _toast,
                    onSetAccount: _setAccount,
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(1))
                  _SmsLoginTab(
                    onToast: _toast,
                    onSetAccount: _setAccount,
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(2))
                  _QRLoginTab(
                    onToast: _toast,
                    onSetAccount: _setAccount,
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(3))
                  _CookieLoginTab(
                    onToast: _toast,
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 1. 密码登录
// ───────────────────────────────────────────────────────────────

class _PasswordLoginTab extends StatefulWidget {
  final void Function(String) onToast;
  final Future<void> Function(Map<String, dynamic>, List) onSetAccount;

  const _PasswordLoginTab({required this.onToast, required this.onSetAccount});

  @override
  State<_PasswordLoginTab> createState() => _PasswordLoginTabState();
}

class _PasswordLoginTabState extends State<_PasswordLoginTab> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;

  /// 极验验证码暂存：从 recaptcha_url 解析的 token，与验证成功后的
  /// {validate, seccode, challenge}。重试登录时一并提交以通过风控。
  String? _recaptchaToken;
  String? _geeValidate;
  String? _geeSeccode;
  String? _geeChallenge;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      widget.onToast('用户名或密码不能为空');
      return;
    }
    setState(() => _loading = true);
    try {
      // 1. 获取 web key（RSA 公钥 + salt）。
      final webKeyRes = await LoginHttp.getWebKey();
      if (webKeyRes['status'] != true) {
        widget.onToast(webKeyRes['msg']?.toString() ?? '获取公钥失败');
        return;
      }
      final salt = webKeyRes['data']['hash'] as String;
      final key = webKeyRes['data']['key'] as String;

      // 2. 调用密码登录接口（RSA 加密为 stub，见 login.dart 注释）。
      final res = await LoginHttp.loginByPwd(
        username: username,
        password: password,
        key: key,
        salt: salt,
        geeChallenge: _geeChallenge,
        geeSeccode: _geeSeccode,
        geeValidate: _geeValidate,
        recaptchaToken: _recaptchaToken,
      );

      if (res['status'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        if (data == null) {
          widget.onToast('登录异常，接口未返回数据：${res["msg"]}');
          return;
        }
        // status==2 表示风控需要短信验证（PiliPlus 在此弹安全中心对话框）。
        if (data['status'] == 2) {
          widget.onToast(
            '本次登录环境存在风险，需手机号验证。安全中心流程暂未实现，请改用扫码或 Cookie 登录。',
          );
          return;
        }
        final tokenInfo = data['token_info'] as Map<String, dynamic>?;
        final cookieInfo = data['cookie_info'] as Map<String, dynamic>?;
        if (tokenInfo == null || cookieInfo == null) {
          widget.onToast('登录异常，接口未返回身份信息，可能因账号风控');
          return;
        }
        await widget.onSetAccount(
          tokenInfo,
          cookieInfo['cookies'] as List,
        );
      } else {
        // 处理错误码：-105 表示需要极验验证码。
        final code = res['code'];
        if (code == -105) {
          // 从返回数据中解析 recaptcha_url，提取 gee_gt / gee_challenge / token。
          final dataMap = res['data'] as Map<String, dynamic>?;
          final captureUrl = dataMap?['url'] as String?;
          if (captureUrl == null || captureUrl.isEmpty) {
            widget.onToast('需要极验验证码，但接口未返回验证地址');
            return;
          }
          final captureUri = Uri.parse(captureUrl);
          _recaptchaToken = captureUri.queryParameters['recaptcha_token'];
          final geeGt = captureUri.queryParameters['gee_gt'];
          final geeChallenge = captureUri.queryParameters['gee_challenge'];
          if (geeGt == null || geeGt.isEmpty ||
              geeChallenge == null || geeChallenge.isEmpty) {
            widget.onToast('极验参数缺失，请改用扫码或 Cookie 登录');
            return;
          }
          // 弹出极验 webview，等待用户完成滑块验证。
          final result = await GeetestWebviewDialog.show(
            context,
            geeGt,
            geeChallenge,
          );
          if (result == null) {
            widget.onToast('已取消验证码');
            return;
          }
          _geeValidate = result['geetest_validate'] as String?;
          _geeSeccode = result['geetest_seccode'] as String?;
          _geeChallenge = result['geetest_challenge'] as String?;
          if (_geeValidate == null || _geeSeccode == null) {
            widget.onToast('验证码结果异常，请重试');
            return;
          }
          // 极验通过后递归调用 _login 重新提交登录请求。
          widget.onToast('验证成功，正在登录...');
          await _login();
        } else {
          widget.onToast(res['msg']?.toString() ?? '登录失败');
        }
      }
    } catch (e) {
      widget.onToast('登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Style.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Style.md),
          Text('使用账号密码登录',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: Style.lg),
          AppTextField(
            controller: _usernameCtrl,
            label: '账号',
            hint: '邮箱/手机号',
            prefix: const Icon(Icons.account_box),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          ),
          const SizedBox(height: Style.md),
          AppTextField(
            controller: _passwordCtrl,
            label: '密码',
            obscureText: !_showPassword,
            keyboardType: TextInputType.visiblePassword,
            prefix: const Icon(Icons.password),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          ),
          Row(
            children: [
              AppSwitch(
                value: _showPassword,
                onChanged: (v) => setState(() => _showPassword = v),
              ),
              const SizedBox(width: Style.sm),
              const Text('显示密码'),
            ],
          ),
          const SizedBox(height: Style.md),
          AppPrimaryButton(
            onPressed: _loading ? null : _login,
            expanded: true,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('登录'),
                    ],
                  ),
          ),
          const SizedBox(height: Style.lg),
          Text(
            '根据 bilibili 官方登录接口规范，密码将在本地加盐、加密后传输。\n'
            '盐与公钥均由官方提供；以 RSA/ECB/PKCS1Padding 方式加密。\n'
            '账号密码仅用于该登录接口，不予保存；本地仅存储登录凭证。\n'
            '当前 RSA 加密为 stub，密码登录可能因风控失败；遇到风控时会弹出极验滑块验证。',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 2. 短信验证码登录
// ───────────────────────────────────────────────────────────────

/// 常用国际冠号（简化版，PiliPlus 使用完整 dial_prefix 数据）。
const _countryCodes = [
  ('86', '中国大陆'),
  ('852', '中国香港'),
  ('853', '中国澳门'),
  ('886', '中国台湾'),
  ('1', '美国/加拿大'),
  ('81', '日本'),
  ('82', '韩国'),
  ('44', '英国'),
];

class _SmsLoginTab extends StatefulWidget {
  final void Function(String) onToast;
  final Future<void> Function(Map<String, dynamic>, List) onSetAccount;

  const _SmsLoginTab({required this.onToast, required this.onSetAccount});

  @override
  State<_SmsLoginTab> createState() => _SmsLoginTabState();
}

class _SmsLoginTabState extends State<_SmsLoginTab> {
  final TextEditingController _telCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  String _countryId = '86';
  String _captchaKey = '';
  int _cooldown = 0;
  Timer? _cooldownTimer;
  bool _loading = false;
  bool _sending = false;

  /// 极验验证码暂存：从 recaptcha_url 解析的 token，与验证成功后的
  /// {validate, seccode, challenge}。重试 sendSms 时一并提交以通过风控。
  /// 参考 PiliPlus `LoginPageController.sendSmsCode` 的递归重试模式。
  String? _recaptchaToken;
  String? _geeValidate;
  String? _geeSeccode;
  String? _geeChallenge;

  @override
  void dispose() {
    _telCtrl.dispose();
    _codeCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// 校验极验参数是否齐全（gt/challenge/token 三者均非空）。
  /// 与 PiliPlus `isGeeArgumentValid` 逻辑一致。
  bool _isGeeArgumentValid(String? gt, String? challenge) {
    return gt != null &&
        gt.isNotEmpty &&
        challenge != null &&
        challenge.isNotEmpty &&
        _recaptchaToken != null &&
        _recaptchaToken!.isNotEmpty;
  }

  Future<void> _sendSms() async {
    final tel = _telCtrl.text.trim();
    if (tel.isEmpty) {
      widget.onToast('手机号不能为空');
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await LoginHttp.sendSmsCode(
        cid: _countryId,
        tel: tel,
        geeChallenge: _geeChallenge,
        geeSeccode: _geeSeccode,
        geeValidate: _geeValidate,
        recaptchaToken: _recaptchaToken,
      );
      if (res['status'] == true) {
        widget.onToast('发送成功');
        _captchaKey = res['data']['captcha_key'] as String? ?? '';
        _cooldown = 60;
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _cooldown = 60 - t.tick);
          if (_cooldown <= 0) t.cancel();
        });
      } else {
        // code==0 但 recaptcha_url 非空，或 code==-105：需要极验验证码。
        // 参考 PiliPlus sendSmsCode 的处理：解析 recaptcha_url → 弹极验 → 递归重试。
        final code = res['code'];
        if (code == 0 || code == -105) {
          final dataMap = res['data'] as Map<String, dynamic>?;
          final captureUrl = dataMap?['recaptcha_url'] as String?;
          String? geeGt;
          String? geeChallenge;
          if (captureUrl != null && captureUrl.isNotEmpty) {
            final captureUri = Uri.parse(captureUrl);
            _recaptchaToken =
                captureUri.queryParameters['recaptcha_token'];
            geeGt = captureUri.queryParameters['gee_gt'];
            geeChallenge = captureUri.queryParameters['gee_challenge'];
          }

          // 若 recaptcha_url 缺失或参数不全，回退到 preCapture 接口获取。
          if (!_isGeeArgumentValid(geeGt, geeChallenge)) {
            final preCaptureRes = await LoginHttp.preCapture();
            if (preCaptureRes['status'] != true ||
                preCaptureRes['data'] == null) {
              widget.onToast(
                '获取验证码失败，请改用扫码或 Cookie 登录\n'
                '(${preCaptureRes['code']}) ${preCaptureRes['msg']}',
              );
              return;
            }
            final preData =
                preCaptureRes['data'] as Map<String, dynamic>;
            geeGt = preData['gee_gt'] as String?;
            geeChallenge = preData['gee_challenge'] as String?;
            _recaptchaToken = preData['recaptcha_token'] as String?;
          }

          if (!_isGeeArgumentValid(geeGt, geeChallenge)) {
            widget.onToast('获取验证码失败，请改用扫码或 Cookie 登录');
            return;
          }

          // 弹出极验 webview，等待用户完成滑块验证。
          final result = await GeetestWebviewDialog.show(
            context,
            geeGt!,
            geeChallenge!,
          );
          if (result == null) {
            widget.onToast('已取消验证码');
            return;
          }
          _geeValidate = result['geetest_validate'] as String?;
          _geeSeccode = result['geetest_seccode'] as String?;
          _geeChallenge = result['geetest_challenge'] as String?;
          if (_geeValidate == null || _geeSeccode == null) {
            widget.onToast('验证码结果异常，请重试');
            return;
          }
          // 极验通过后递归调用 _sendSms 重新提交发送验证码请求。
          widget.onToast('验证成功，正在发送短信...');
          await _sendSms();
        } else {
          widget.onToast(res['msg']?.toString() ?? '发送失败');
        }
      }
    } catch (e) {
      widget.onToast('发送失败：$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    final tel = _telCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (tel.isEmpty) {
      widget.onToast('手机号不能为空');
      return;
    }
    if (_captchaKey.isEmpty) {
      widget.onToast('请先获取验证码');
      return;
    }
    if (code.isEmpty) {
      widget.onToast('验证码不能为空');
      return;
    }
    setState(() => _loading = true);
    try {
      // 短信登录需要 web key 用于 dt 字段 RSA 加密（stub）。
      final webKeyRes = await LoginHttp.getWebKey();
      if (webKeyRes['status'] != true) {
        widget.onToast(webKeyRes['msg']?.toString() ?? '获取公钥失败');
        return;
      }
      final key = webKeyRes['data']['key'] as String;

      final res = await LoginHttp.loginBySms(
        tel: tel,
        code: code,
        captchaKey: _captchaKey,
        cid: _countryId,
        key: key,
      );
      if (res['status'] == true) {
        final data = res['data'] as Map<String, dynamic>;
        await widget.onSetAccount(
          data['token_info'] as Map<String, dynamic>,
          (data['cookie_info'] as Map<String, dynamic>)['cookies'] as List,
        );
      } else {
        widget.onToast(res['msg']?.toString() ?? '登录失败');
      }
    } catch (e) {
      widget.onToast('登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Style.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Style.md),
          Text('使用手机短信验证码登录',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: Style.lg),
          // 手机号：区号选择器作为 prefix 内嵌入自适应输入框
          AppTextField(
            controller: _telCtrl,
            label: '手机号',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            prefix: MenuAnchor(
              menuChildren: [
                for (final item in _countryCodes)
                  MenuItemButton(
                    onPressed: () => setState(() => _countryId = item.$1),
                    leadingIcon: item.$1 == _countryId
                        ? const Icon(Icons.check, size: 18)
                        : const SizedBox(width: 18),
                    child: SizedBox(
                      width: 150,
                      child: Row(
                        children: [
                          Text(item.$2),
                          const Spacer(),
                          Text('+${item.$1}'),
                        ],
                      ),
                    ),
                  ),
              ],
              builder: (context, controller, child) => Tooltip(
                message: '选择国际冠码，当前为+$_countryId',
                child: InkWell(
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('+$_countryId'),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Style.md),
          // 验证码：获取按钮作为 suffix 内嵌入自适应输入框
          AppTextField(
            controller: _codeCtrl,
            label: '验证码',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            prefix: const Icon(Icons.sms_outlined),
            suffix: TextButton.icon(
              onPressed: (_cooldown > 0 || _sending) ? null : _sendSms,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _cooldown > 0 ? '等待$_cooldown秒' : '获取验证码',
              ),
            ),
          ),
          const SizedBox(height: Style.lg),
          AppPrimaryButton(
            onPressed: _loading ? null : _login,
            expanded: true,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('登录'),
                    ],
                  ),
          ),
          const SizedBox(height: Style.lg),
          Text(
            '手机号仅用于 bilibili 官方发送验证码与登录接口，不予保存；\n'
            '本地仅存储登录凭证。\n'
            '遇到风控时会弹出极验滑块验证，验证通过后自动重试。',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 3. 扫码登录（TV 端 QR）
// ───────────────────────────────────────────────────────────────

class _QRLoginTab extends StatefulWidget {
  final void Function(String) onToast;
  final Future<void> Function(Map<String, dynamic>, List) onSetAccount;

  const _QRLoginTab({required this.onToast, required this.onSetAccount});

  @override
  State<_QRLoginTab> createState() => _QRLoginTabState();
}

class _QRLoginTabState extends State<_QRLoginTab> {
  String? _qrUrl;
  String _status = '正在获取二维码...';
  Timer? _pollTimer;
  int _leftTime = 180;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshQR();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshQR() async {
    if (_refreshing) return;
    _refreshing = true;
    setState(() {
      _loading = true;
      _status = '正在获取二维码...';
      _leftTime = 180;
    });
    _pollTimer?.cancel();

    final res = await LoginHttp.getHDcode();
    if (!mounted) {
      _refreshing = false;
      return;
    }

    switch (res) {
      case Success(:final response):
        setState(() {
          _qrUrl = response.url;
          _loading = false;
          _status = '请使用哔哩哔哩手机端扫码';
        });
        _startPolling(response.authCode);
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _status = '获取失败：${errMsg ?? '未知错误'}';
        });
      case Loading():
        // getHDcode 不会返回 Loading，仅为满足 sealed exhaustiveness 检查。
        setState(() {
          _loading = false;
          _status = '加载中...';
        });
    }
    _refreshing = false;
  }

  void _startPolling(String authCode) {
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      _leftTime--;
      if (_leftTime <= 0) {
        t.cancel();
        if (mounted) setState(() => _status = '二维码已过期，请刷新');
        return;
      }

      final result = await LoginHttp.codePoll(authCode);
      if (!mounted) return;

      final code = result['code'];
      // 0=成功 86090=待确认 86038=过期 86039=未扫描
      if (result['status'] == true) {
        t.cancel();
        setState(() => _status = '登录成功');
        // TV QR 返回的 data 本身即为 tokenInfo（含 access_token/refresh_token
        // 顶层字段），cookie_info.cookies 为 cookie 列表。
        // 与 PiliPlus setAccount(value['data'], value['data']['cookie_info']['cookies']) 一致。
        final data = result['data'] as Map<String, dynamic>;
        final cookieInfo = data['cookie_info'] as Map<String, dynamic>;
        await widget.onSetAccount(
          data,
          cookieInfo['cookies'] as List,
        );
      } else if (code == 86090) {
        setState(() => _status = '扫描成功，请在手机端确认');
      } else if (code == 86038) {
        t.cancel();
        setState(() => _status = '二维码已过期，请刷新');
      } else if (code == 86039) {
        // 未扫描，保持当前状态（仅在首次设置时更新文案）
        if (_status == '正在获取二维码...' || _status == '请使用哔哩哔哩手机端扫码') {
          setState(() => _status = '请使用哔哩哔哩手机端扫码');
        }
      } else {
        // 其他 code（如 86092 用户取消确认 / 86091 已扫码但取消 等）：
        // 被扫码但登录失败 → 自动刷新获取新二维码。
        widget.onToast('扫码登录失败（code=$code），正在刷新二维码...');
        t.cancel();
        _refreshQR();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Style.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              CircularProgressIndicator(color: cs.primary)
            else if (_qrUrl != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Style.radiusMd),
                ),
                child: Image.network(
                  'https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${Uri.encodeComponent(_qrUrl!)}',
                  width: 240,
                  height: 240,
                  cacheWidth: 480,
                  cacheHeight: 480,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(
                      child: Icon(Icons.qr_code_2,
                          size: 120, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: Style.lg),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (_leftTime > 0 && !_loading)
              Padding(
                padding: const EdgeInsets.only(top: Style.xs),
                child: Text(
                  '剩余 ${_leftTime}s',
                  style: TextStyle(
                    color: cs.outline,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: Style.lg),
            // 始终显示手动刷新按钮（加载中除外），便于用户在扫码失败/过期时主动刷新。
            if (!_loading)
              AppPrimaryButton(
                onPressed: _refreshQR,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text('刷新二维码'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 4. Cookie 登录
// ───────────────────────────────────────────────────────────────

class _CookieLoginTab extends StatefulWidget {
  final void Function(String) onToast;

  const _CookieLoginTab({required this.onToast});

  @override
  State<_CookieLoginTab> createState() => _CookieLoginTabState();
}

class _CookieLoginTabState extends State<_CookieLoginTab> {
  final TextEditingController _cookieCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _cookieCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final cookieText = _cookieCtrl.text.trim();
    if (cookieText.isEmpty) {
      widget.onToast('Cookie 不能为空');
      return;
    }
    setState(() => _loading = true);
    try {
      // 解析 cookie 字符串（支持 "key=value; key2=value2" 格式）。
      final cookieMap = <String, String>{};
      for (final part in cookieText.split(RegExp(r'[;\n]'))) {
        final p = part.trim();
        if (p.isEmpty) continue;
        final eq = p.indexOf('=');
        if (eq > 0) {
          cookieMap[p.substring(0, eq).trim()] = p.substring(eq + 1).trim();
        }
      }

      if (cookieMap['DedeUserID'] == null || cookieMap['bili_jct'] == null) {
        widget.onToast('Cookie 缺少 DedeUserID 或 bili_jct');
        return;
      }

      // 构造 cookie jar。
      final jar = DefaultCookieJar(ignoreExpires: true);
      jar.domainCookies['bilibili.com'] = {
        '/': {
          for (final entry in cookieMap.entries)
            entry.key: SerializableCookie(
              Cookie(entry.key, entry.value)..setBiliDomain(),
            ),
        },
      };

      // Accounts.set 会依次执行：保存 → 激活 buvid → onLoginMain（拉取用户信息）
      // onLoginMain 失败时会自动删除账号。
      final account = LoginAccount(jar, null, null, {AccountType.main});
      await Accounts.set(AccountType.main, account);

      if (AccountService().isLogin) {
        widget.onToast('登录成功');
        if (mounted) Navigator.of(context).pop();
      } else {
        widget.onToast('Cookie 无效或已过期');
      }
    } catch (e) {
      widget.onToast('登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Style.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Style.md),
          Text(
            '使用 Cookie 登录',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Style.sm),
          Text(
            '从浏览器获取 bilibili.com 的 Cookie，需包含 DedeUserID 和 bili_jct。\n'
            '使用 App 端 Api 实现的功能将不可用。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.primary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: Style.lg),
          AppTextField(
            controller: _cookieCtrl,
            label: 'Cookie',
            minLines: 1,
            maxLines: 8,
            prefix: const Icon(Icons.cookie_outlined),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          ),
          const SizedBox(height: Style.lg),
          AppPrimaryButton(
            onPressed: _loading ? null : _login,
            expanded: true,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('登录'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

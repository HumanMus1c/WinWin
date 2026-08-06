import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/login.dart';
import 'package:winwin/http/user.dart';
import 'package:winwin/models/common/account_type.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 登录页（移植自 PiliPlus `lib/pages/login/`）。
///
/// 与 PiliPlus 登录途径一致，提供 4 种登录方式：
///   1. 密码登录（含 RSA 加密 stub + 极验风控 stub）
///   2. 短信验证码登录（含极验风控 stub）
///   3. 扫码登录（TV 端二维码）
///   4. Cookie 登录
///
/// 不引入 GetX / flutter_smart_dialog / pretty_qr_code：
///   - 用 [Navigator] 替代 GetX 路由
///   - 用 [SnackBar] 替代 SmartDialog.showToast
///   - QR 用在线图片服务渲染
///
/// 已知限制（与 PiliPlus 对齐时的 stub）：
///   - RSA 密码加密未实现（需引入 `encrypt` 包），密码以 salt+plaintext 发送
///   - 极验验证码 webview 未实现，遇到风控（code=-105 或 status=2）会提示
///     "需要验证码但 webview 未实现"，用户需改用扫码/Cookie 登录
void showLoginPage(BuildContext context) {
  Navigator.of(context).push(
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

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 登录成功后统一处理：写入账号 → 拉取用户信息 → 关闭页面。
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
      await Accounts.set(AccountType.main, account);
      await LoginUtils.onLoginMain();
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
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: biliPink,
          unselectedLabelColor:
              Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: biliPink,
          tabs: const [
            Tab(icon: Icon(Icons.password), text: '密码'),
            Tab(icon: Icon(Icons.sms_outlined), text: '短信'),
            Tab(icon: Icon(Icons.qr_code), text: '扫码'),
            Tab(icon: Icon(Icons.cookie_outlined), text: 'Cookie'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PasswordLoginTab(
            onToast: _toast,
            onSetAccount: _setAccount,
          ),
          _SmsLoginTab(
            onToast: _toast,
            onSetAccount: _setAccount,
          ),
          _QRLoginTab(
            onToast: _toast,
            onSetAccount: _setAccount,
          ),
          _CookieLoginTab(
            onToast: _toast,
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
            '本次登录环境存在风险，需手机号验证。极验 webview 未实现，请改用扫码或 Cookie 登录。',
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
          widget.onToast(
            '需要极验验证码，webview 未实现，请改用扫码或 Cookie 登录。',
          );
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
          TextField(
            controller: _usernameCtrl,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.account_box),
              border: UnderlineInputBorder(),
              labelText: '账号',
              hintText: '邮箱/手机号',
            ),
          ),
          const SizedBox(height: Style.md),
          TextField(
            controller: _passwordCtrl,
            obscureText: !_showPassword,
            keyboardType: TextInputType.visiblePassword,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.password),
              border: UnderlineInputBorder(),
              labelText: '密码',
            ),
          ),
          Row(
            children: [
              Checkbox(
                value: _showPassword,
                onChanged: (v) => setState(() => _showPassword = v ?? false),
              ),
              const Text('显示密码'),
            ],
          ),
          const SizedBox(height: Style.md),
          FilledButton.icon(
            onPressed: _loading ? null : _login,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login),
            label: const Text('登录'),
            style: FilledButton.styleFrom(
              backgroundColor: biliPink,
              padding: const EdgeInsets.symmetric(vertical: Style.md),
            ),
          ),
          const SizedBox(height: Style.lg),
          Text(
            '根据 bilibili 官方登录接口规范，密码将在本地加盐、加密后传输。\n'
            '盐与公钥均由官方提供；以 RSA/ECB/PKCS1Padding 方式加密。\n'
            '账号密码仅用于该登录接口，不予保存；本地仅存储登录凭证。\n'
            '当前 RSA 加密为 stub，密码登录可能因风控失败，建议优先使用扫码或 Cookie 登录。',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
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

  @override
  void dispose() {
    _telCtrl.dispose();
    _codeCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
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
        // code==-105 或返回 recaptcha_url 表示需要极验验证码。
        final code = res['code'];
        if (code == -105 || code == 0) {
          widget.onToast(
            '需要极验验证码，webview 未实现，请改用扫码或 Cookie 登录。',
          );
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
          // 区号 + 手机号
          DecoratedBox(
            decoration: UnderlineTabIndicator(
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.4),
              ),
            ),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: '选择国际冠码，当前为+$_countryId',
                  onSelected: (v) => setState(() => _countryId = v),
                  initialValue: _countryId,
                  itemBuilder: (_) => _countryCodes.map((item) {
                    return PopupMenuItem<String>(
                      value: item.$1,
                      child: Row(
                        children: [
                          Text(item.$2),
                          const Spacer(),
                          Text('+${item.$1}'),
                        ],
                      ),
                    );
                  }).toList(),
                  child: Row(
                    children: [
                      Icon(Icons.phone,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('+$_countryId'),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _telCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      labelText: '手机号',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Style.md),
          // 验证码 + 获取按钮
          DecoratedBox(
            decoration: UnderlineTabIndicator(
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.4),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.sms_outlined),
                      border: InputBorder.none,
                      labelText: '验证码',
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: (_cooldown > 0 || _sending) ? null : _sendSms,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _cooldown > 0 ? '等待${_cooldown}秒' : '获取验证码',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Style.lg),
          FilledButton.icon(
            onPressed: _loading ? null : _login,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login),
            label: const Text('登录'),
            style: FilledButton.styleFrom(
              backgroundColor: biliPink,
              padding: const EdgeInsets.symmetric(vertical: Style.md),
            ),
          ),
          const SizedBox(height: Style.lg),
          Text(
            '手机号仅用于 bilibili 官方发送验证码与登录接口，不予保存；\n'
            '本地仅存储登录凭证。\n'
            '当前 dt 字段 RSA 加密为 stub，短信登录可能因风控失败，建议优先使用扫码或 Cookie 登录。',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
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
    setState(() {
      _loading = true;
      _status = '正在获取二维码...';
      _leftTime = 180;
    });
    _pollTimer?.cancel();

    final res = await LoginHttp.getHDcode();
    if (!mounted) return;

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
        final data = result['data'] as Map<String, dynamic>;
        final tokenInfo = data['token_info'] as Map<String, dynamic>;
        final cookieInfo = data['cookie_info'] as Map<String, dynamic>;
        await widget.onSetAccount(
          tokenInfo,
          cookieInfo['cookies'] as List,
        );
      } else if (code == 86090) {
        setState(() => _status = '扫描成功，请在手机端确认');
      } else if (code == 86038) {
        t.cancel();
        setState(() => _status = '二维码已过期，请刷新');
      }
      // 86039=未扫描，保持当前状态
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Style.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              const CircularProgressIndicator(color: biliPink)
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
                  errorBuilder: (_, __, ___) => const SizedBox(
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
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: Style.lg),
            if (_leftTime <= 0 || _status.contains('过期'))
              FilledButton.icon(
                onPressed: _refreshQR,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新二维码'),
                style: FilledButton.styleFrom(backgroundColor: biliPink),
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

      // 先验证 cookie 有效性（拉取用户信息）。
      final account = LoginAccount(jar, null, null, {AccountType.main});
      await Accounts.set(AccountType.main, account);
      final res = await UserHttp.userInfo();

      if (res case Success(:final response)) {
        if (response.isLogin == true) {
          await account.onChange();
          await LoginUtils.onLoginMain();
          widget.onToast('登录成功');
          if (mounted) Navigator.of(context).pop();
        } else {
          await Accounts.deleteAll({account});
          widget.onToast('Cookie 无效或已过期');
        }
      } else if (res case Error(:final errMsg)) {
        await Accounts.deleteAll({account});
        widget.onToast(errMsg ?? '登录失败');
      }
    } catch (e) {
      widget.onToast('登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              color: Theme.of(context).colorScheme.primary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: Style.lg),
          TextField(
            controller: _cookieCtrl,
            minLines: 1,
            maxLines: 8,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.cookie_outlined),
              border: UnderlineInputBorder(),
              labelText: 'Cookie',
            ),
          ),
          const SizedBox(height: Style.lg),
          FilledButton.icon(
            onPressed: _loading ? null : _login,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login),
            label: const Text('登录'),
            style: FilledButton.styleFrom(
              backgroundColor: biliPink,
              padding: const EdgeInsets.symmetric(vertical: Style.md),
            ),
          ),
        ],
      ),
    );
  }
}

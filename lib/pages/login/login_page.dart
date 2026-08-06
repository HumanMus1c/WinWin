import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/login.dart';
import 'package:winwin/http/user.dart';
import 'package:winwin/models/common/account_type.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 登录页（移植自 PiliPlus `lib/pages/login/`）。
///
/// WinWin 精简版：扫码登录（TV 端）+ Cookie 登录两种方式。
/// 不引入 GetX / pretty_qr_code，QR 用在线图片服务渲染。
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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: biliPink,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: biliPink,
            tabs: const [
              Tab(text: '扫码登录'),
              Tab(text: 'Cookie 登录'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _QRLoginTab(),
                _CookieLoginTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 扫码登录 ──

class _QRLoginTab extends StatefulWidget {
  const _QRLoginTab();

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
    }
  }

  void _startPolling(String authCode) {
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      _leftTime--;
      if (_leftTime <= 0) {
        t.cancel();
        if (mounted) {
          setState(() => _status = '二维码已过期，请刷新');
        }
        return;
      }

      final result = await LoginHttp.codePoll(authCode);
      if (!mounted) return;

      final code = result['code'];
      // 0=成功 86090=待确认 86038=过期 86039=未扫描
      if (result['status'] == true) {
        t.cancel();
        await _onLoginSuccess(result['data']);
      } else if (code == 86090) {
        setState(() => _status = '扫描成功，请在手机端确认');
      } else if (code == 86039) {
        // 等待扫描，保持当前状态
      } else if (code == 86038) {
        t.cancel();
        setState(() => _status = '二维码已过期，请刷新');
      }
    });
  }

  Future<void> _onLoginSuccess(Map<String, dynamic> data) async {
    setState(() => _status = '登录成功');
    try {
      final tokenInfo = data['token_info'] as Map<String, dynamic>;
      final cookieInfo = data['cookie_info'] as Map<String, dynamic>;
      final cookies = cookieInfo['cookies'] as List;

      final account = LoginAccount(
        BiliCookieJarHelper.fromList(cookies),
        tokenInfo['access_token'] as String?,
        tokenInfo['refresh_token'] as String?,
        {AccountType.main},
      );
      await account.onChange();
      await Accounts.set(AccountType.main, account);
      await LoginUtils.onLoginMain();
    } catch (e) {
      debugPrint('登录成功但设置账号失败: $e');
    }
    if (mounted) Navigator.of(context).pop();
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
                      child: Icon(Icons.qr_code_2, size: 120, color: Colors.grey),
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

// ── Cookie 登录 ──

class _CookieLoginTab extends StatefulWidget {
  const _CookieLoginTab();

  @override
  State<_CookieLoginTab> createState() => _CookieLoginTabState();
}

class _CookieLoginTabState extends State<_CookieLoginTab> {
  final TextEditingController _cookieController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    final cookieText = _cookieController.text.trim();
    if (cookieText.isEmpty) return;

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
        _toast('Cookie 缺少 DedeUserID 或 bili_jct');
        setState(() => _loading = false);
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
          if (mounted) Navigator.of(context).pop();
        } else {
          await Accounts.deleteAll({account});
          _toast('Cookie 无效或已过期');
        }
      } else if (res case Error(:final errMsg)) {
        await Accounts.deleteAll({account});
        _toast(errMsg ?? '登录失败');
      }
    } catch (e) {
      _toast('登录失败：$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Style.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '粘贴 Cookie 登录',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Style.sm),
          Text(
            '从浏览器获取 bilibili.com 的 Cookie，需包含 DedeUserID 和 bili_jct。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: Style.lg),
          TextField(
            controller: _cookieController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'DedeUserID=12345; bili_jct=abc; SESSDATA=xyz; ...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
            ),
          ),
          const SizedBox(height: Style.lg),
          FilledButton.icon(
            onPressed: _loading ? null : _onLogin,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

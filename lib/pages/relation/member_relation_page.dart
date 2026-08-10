import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/fan.dart';
import 'package:winwin/http/follow.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 关系列表类型：关注列表 / 粉丝列表。
enum RelationType { followings, fans }

/// 推送关系列表页（关注或粉丝）。
void showMemberRelationPage(
  BuildContext context, {
  required RelationType type,
  required int vmid,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MemberRelationPage(type: type, vmid: vmid),
    ),
  );
}

/// 用户关系列表页（关注 / 粉丝）。
///
/// 复用 [FollowHttp.followings] 与 [FanHttp.fans]，二者响应结构一致：
/// `data.list`（每项含 mid/uname/face/sign）+ `data.total`。页码分页。
/// 点击成员跳转 [MemberSpacePage]。
class MemberRelationPage extends StatefulWidget {
  const MemberRelationPage({
    super.key,
    required this.type,
    required this.vmid,
  });

  final RelationType type;
  final int vmid;

  @override
  State<MemberRelationPage> createState() => _MemberRelationPageState();
}

class _MemberRelationPageState extends State<MemberRelationPage> {
  final List<_RelationMember> _items = [];
  int _page = 1;
  int? _total;
  bool _hasMore = true;
  bool _loading = true;
  String? _error;

  String get _title =>
      widget.type == RelationType.followings ? '关注' : '粉丝';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<LoadingState<Map<String, dynamic>>> _fetch() {
    if (widget.type == RelationType.followings) {
      return FollowHttp.followings(vmid: widget.vmid, pn: _page);
    }
    return FanHttp.fans(vmid: widget.vmid, pn: _page);
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore) return;

    if (!Accounts.main.isLogin) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }

    final res = await _fetch();
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        final list = (response['list'] as List?) ?? const [];
        final total = response['total'];
        setState(() {
          _loading = false;
          _error = null;
          _items.addAll(
            list.map((e) => _RelationMember.fromJson(e as Map)),
          );
          if (total is int) _total = total;
          _hasMore = _items.length < (_total ?? 0) && list.isNotEmpty;
          _page++;
        });
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalLabel = _total != null ? ' $_total' : '';
    return Scaffold(
      appBar: AppBar(title: Text('$_title$totalLabel')),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : _error != null && _items.isEmpty
              ? _buildErrorView()
              : RefreshIndicator(
                  color: biliPink,
                  onRefresh: () => _load(refresh: true),
                  child: ListView.builder(
                    itemCount: _items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        if (_hasMore) {
                          _load();
                          return const Padding(
                            padding: EdgeInsets.all(Style.md),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: biliPink,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      return _RelationTile(
                        member: _items[index],
                        onTap: () => _gotoMember(_items[index]),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error ?? '加载失败'),
          const SizedBox(height: Style.md),
          FilledButton(
            onPressed: () => _load(refresh: true),
            style: FilledButton.styleFrom(backgroundColor: biliPink),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  void _gotoMember(_RelationMember m) {
    final mid = m.mid;
    if (mid == null || mid <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberSpacePage(mid: mid)),
    );
  }
}

/// 单个关系成员条目：头像 + 名字 + 签名。
class _RelationTile extends StatelessWidget {
  const _RelationTile({required this.member, required this.onTap});

  final _RelationMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: NetworkImgLayer(
        src: member.face,
        width: 48,
        height: 48,
        type: 'avatar',
      ),
      title: Text(
        member.uname ?? '未知用户',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        (member.sign?.isNotEmpty ?? false) ? member.sign! : '这个人很神秘',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

/// 关系成员数据（关注/粉丝列表项的精简模型）。
///
/// bilibili `/x/relation/followings` 与 `/x/relation/fans` 返回的 list 项
/// 字段名一致：mid / uname / face / sign，但数字字段可能为 String，需安全转换。
class _RelationMember {
  final int? mid;
  final String? uname;
  final String? face;
  final String? sign;

  _RelationMember({this.mid, this.uname, this.face, this.sign});

  factory _RelationMember.fromJson(Map json) {
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    String? toStr(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      return v.toString();
    }

    return _RelationMember(
      mid: toInt(json['mid'] ?? json['vmid']),
      uname: toStr(json['uname'] ?? json['name']),
      face: toStr(json['face']),
      sign: toStr(json['sign']),
    );
  }
}

/// 用户信息模型（对应 `/x/web-interface/nav`）。
///
/// 移植自 PiliPlus `lib/models/user/info.dart`，精简为 WinWin 所需字段。
/// 含会员权限识别字段 [vipStatus] / [vipType]。
///
/// 纯 model（无 Hive 注解），通过 JSON 字符串持久化到 GStorage.localCache。

/// 安全类型转换：bilibili API 返回的数字字段可能是 int / double / String，
/// 直接 `as int?` 会抛异常。此方法统一处理。
int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// 安全转换为 String，兼容 int / double / String。
String? _toStr(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

/// 安全转换为 num，兼容 int / double / String。
num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

/// 安全转换为 bool，兼容 bool / int (0/1)。
bool? _toBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is int) return v != 0;
  return null;
}

class UserInfoModel {
  bool? isLogin;
  int? mid;
  String? name;
  String? face;
  int? level;
  int? silence;
  int? coins;
  num? money;
  String? biliMid;
  int? following;
  int? follower;
  int? dynamicCount;
  EmailPhoneInfo? email;
  EmailPhoneInfo? phone;

  /// 会员到期时间（时间戳秒）。
  int? vipDueDate;

  /// 会员状态：0=非会员，1=月度大会员，2=年度大会员。
  int? vipStatus;

  /// 会员类型：0=无，1=月度，2=年度。
  int? vipType;

  int? vipPayType;
  int? vipThemeType;
  Map? vipLabel;
  int? vipAvatarSub;
  String? vipNicknameColor;
  LevelInfo? levelInfo;

  UserInfoModel({
    this.isLogin,
    this.mid,
    this.name,
    this.face,
    this.level,
    this.silence,
    this.coins,
    this.money,
    this.biliMid,
    this.following,
    this.follower,
    this.dynamicCount,
    this.email,
    this.phone,
    this.vipDueDate,
    this.vipStatus,
    this.vipType,
    this.vipPayType,
    this.vipThemeType,
    this.vipLabel,
    this.vipAvatarSub,
    this.vipNicknameColor,
    this.levelInfo,
  });

  /// 是否会员（vipStatus > 0）。
  bool get isVip => vipStatus != null && vipStatus! > 0;

  /// 是否年度大会员（vipType == 2）。
  bool get isYearVip => isVip && vipType == 2;

  Map<String, dynamic> toJson() => {
        'isLogin': isLogin,
        'mid': mid,
        'name': name,
        'face': face,
        'level': level,
        'silence': silence,
        'coins': coins,
        'money': money,
        'bili_mid': biliMid,
        'following': following,
        'follower': follower,
        'dynamic_count': dynamicCount,
        'email': email?.toJson(),
        'phone': phone?.toJson(),
        'vipDueDate': vipDueDate,
        'vipStatus': vipStatus,
        'vipType': vipType,
        'vip_pay_type': vipPayType,
        'vip_theme_type': vipThemeType,
        'vip_label': vipLabel,
        'vip_avatar_subscript': vipAvatarSub,
        'vip_nickname_color': vipNicknameColor,
        'level_info': levelInfo?.toJson(),
      };

  factory UserInfoModel.fromJson(Map<String, dynamic> json) {
    // `/x/web-interface/nav` 返回的字段名：
    //   uname（用户名）、level_info.current_level（等级）、
    //   money（B币余额）、coins 不存在
    // bilibili API 返回的数字可能是 int/double/String，用安全转换。
    final levelInfoJson = json['level_info'] as Map<String, dynamic>?;
    return UserInfoModel(
      isLogin: _toBool(json['isLogin']),
      mid: _toInt(json['mid']),
      name: _toStr(json['uname'] ?? json['name']),
      face: _toStr(json['face']),
      level: _toInt(json['level'] ?? levelInfoJson?['current_level']),
      silence: _toInt(json['silence']),
      coins: _toInt(json['coins']),
      money: _toNum(json['money']),
      biliMid: _toStr(json['bili_mid'] ?? json['mid']),
      following: _toInt(json['following']),
      follower: _toInt(json['follower']),
      dynamicCount: _toInt(json['dynamic_count']),
      email: json['email'] == null
          ? null
          : EmailPhoneInfo.fromJson(json['email'] as Map<String, dynamic>),
      phone: json['phone'] == null
          ? null
          : EmailPhoneInfo.fromJson(json['phone'] as Map<String, dynamic>),
      vipDueDate: _toInt(json['vipDueDate']),
      vipStatus: _toInt(json['vipStatus']),
      vipType: _toInt(json['vipType']),
      vipPayType: _toInt(json['vip_pay_type']),
      vipThemeType: _toInt(json['vip_theme_type']),
      vipLabel: json['vip_label'] as Map?,
      vipAvatarSub: _toInt(json['vip_avatar_subscript']),
      vipNicknameColor: _toStr(json['vip_nickname_color']),
      levelInfo: levelInfoJson == null
          ? null
          : LevelInfo.fromJson(levelInfoJson),
    );
  }
}

class LevelInfo {
  int? currentLevel;
  int? currentMin;
  int? currentExp;
  String? identity;
  int? nextExp;

  LevelInfo({
    this.currentLevel,
    this.currentMin,
    this.currentExp,
    this.identity,
    this.nextExp,
  });

  Map<String, dynamic> toJson() => {
        'current_level': currentLevel,
        'current_min': currentMin,
        'current_exp': currentExp,
        'identity': identity,
        'next_exp': nextExp,
      };

  factory LevelInfo.fromJson(Map<String, dynamic> json) {
    return LevelInfo(
      currentLevel: _toInt(json['current_level']),
      currentMin: _toInt(json['current_min']),
      currentExp: _toInt(json['current_exp']),
      identity: _toStr(json['identity']),
      nextExp: _toInt(json['next_exp'] ?? json['next_exp_string']),
    );
  }
}

class EmailPhoneInfo {
  String? value;
  bool? status;
  bool? verified;
  String? type;

  EmailPhoneInfo({this.value, this.status, this.verified, this.type});

  Map<String, dynamic> toJson() => {
        'value': value,
        'status': status,
        'verified': verified,
        'type': type,
      };

  factory EmailPhoneInfo.fromJson(Map<String, dynamic> json) {
    return EmailPhoneInfo(
      value: _toStr(json['value']),
      status: _toBool(json['status']),
      verified: _toBool(json['verified']),
      type: _toStr(json['type']),
    );
  }
}

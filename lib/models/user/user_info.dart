/// 用户信息模型（对应 `/x/web-interface/nav`）。
///
/// 移植自 PiliPlus `lib/models/user/info.dart`，精简为 WinWin 所需字段。
/// 含会员权限识别字段 [vipStatus] / [vipType]。
///
/// 纯 model（无 Hive 注解），通过 JSON 字符串持久化到 GStorage.localCache。
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
    // 修正：从 uname 读取用户名，从 level_info.current_level 读取等级
    final levelInfoJson = json['level_info'] as Map<String, dynamic>?;
    return UserInfoModel(
      isLogin: json['isLogin'] as bool?,
      mid: json['mid'] as int?,
      name: (json['uname'] ?? json['name']) as String?,
      face: json['face'] as String?,
      level: (json['level'] ?? levelInfoJson?['current_level']) as int?,
      silence: json['silence'] as int?,
      coins: json['coins'] as int?,
      money: json['money'] as num?,
      biliMid: (json['bili_mid'] ?? json['mid']?.toString()) as String?,
      following: json['following'] as int?,
      follower: json['follower'] as int?,
      dynamicCount: json['dynamic_count'] as int?,
      email: json['email'] == null
          ? null
          : EmailPhoneInfo.fromJson(json['email'] as Map<String, dynamic>),
      phone: json['phone'] == null
          ? null
          : EmailPhoneInfo.fromJson(json['phone'] as Map<String, dynamic>),
      vipDueDate: json['vipDueDate'] as int?,
      vipStatus: json['vipStatus'] as int?,
      vipType: json['vipType'] as int?,
      vipPayType: json['vip_pay_type'] as int?,
      vipThemeType: json['vip_theme_type'] as int?,
      vipLabel: json['vip_label'] as Map?,
      vipAvatarSub: json['vip_avatar_subscript'] as int?,
      vipNicknameColor: json['vip_nickname_color'] as String?,
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
      currentLevel: json['current_level'] as int?,
      currentMin: json['current_min'] as int?,
      currentExp: json['current_exp'] as int?,
      identity: json['identity'] as String?,
      nextExp: json['next_exp'] as int? ?? json['next_exp_string'] as int?,
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
      value: json['value'] as String?,
      status: json['status'] as bool?,
      verified: json['verified'] as bool?,
      type: json['type'] as String?,
    );
  }
}

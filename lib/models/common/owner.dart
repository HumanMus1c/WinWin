/// UP 主 / 用户简要信息（收藏夹、视频列表通用）。
class Owner {
  int? mid;
  String? name;
  String? face;

  Owner({this.mid, this.name, this.face});

  factory Owner.fromJson(Map<String, dynamic> json) => Owner(
        mid: json['mid'] as int?,
        name: json['name'] as String?,
        face: json['face'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'mid': mid,
        'name': name,
        'face': face,
      };
}

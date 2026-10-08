import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/shell/app_theme_host.dart';

/// 官方认证色调类型（个人 / 机构）。
enum OfficialVerifyBadgeTone {
  personal,
  organization,
}

/// 官方认证规格。
class OfficialVerifyBadgeSpec {
  const OfficialVerifyBadgeSpec({
    required this.text,
    required this.contentDescription,
    required this.tone,
  });

  final String text;
  final String contentDescription;
  final OfficialVerifyBadgeTone tone;
}

/// 依据 type 解析官方认证微章。
///
/// 移植自 BiliPai `OfficialVerifyBadgePolicy.kt`：
/// - 0 -> 个人认证 (personal)
/// - 1 -> 机构认证 (organization)
/// - 其余 -> null
OfficialVerifyBadgeSpec? resolveOfficialVerifyBadge(
  int? type, {
  String? title,
  String? desc,
  bool compact = false,
}) {
  final tone = switch (type) {
    0 => OfficialVerifyBadgeTone.personal,
    1 => OfficialVerifyBadgeTone.organization,
    _ => null,
  };
  if (tone == null) return null;
  return _buildOfficialVerifyBadgeSpec(
    tone: tone,
    title: title,
    desc: desc,
    compact: compact,
  );
}

/// 依据 type 与 role 解析官方认证微章（适用于角色扩展接口）。
///
/// 移植自 BiliPai `OfficialVerifyBadgePolicy.kt`：
/// - role in [3, 4, 5, 6] -> 机构认证
/// - 其余合法 type -> 个人认证
OfficialVerifyBadgeSpec? resolveOfficialVerifyBadgeFromRole(
  int? type,
  int? role, {
  String? title,
  String? desc,
  bool compact = false,
}) {
  if (type == null || type < 0) return null;
  final tone = switch (role) {
    3 || 4 || 5 || 6 => OfficialVerifyBadgeTone.organization,
    _ => OfficialVerifyBadgeTone.personal,
  };
  return _buildOfficialVerifyBadgeSpec(
    tone: tone,
    title: title,
    desc: desc,
    compact: compact,
  );
}

OfficialVerifyBadgeSpec _buildOfficialVerifyBadgeSpec({
  required OfficialVerifyBadgeTone tone,
  String? title,
  String? desc,
  bool compact = false,
}) {
  final fullText = (title != null && title.trim().isNotEmpty)
      ? title.trim()
      : (desc != null && desc.trim().isNotEmpty)
          ? desc.trim()
          : switch (tone) {
              OfficialVerifyBadgeTone.personal => '个人认证',
              OfficialVerifyBadgeTone.organization => '机构认证',
            };

  final visibleText = compact
      ? switch (tone) {
          OfficialVerifyBadgeTone.personal => '个人',
          OfficialVerifyBadgeTone.organization => '机构',
        }
      : fullText;

  return OfficialVerifyBadgeSpec(
    text: visibleText,
    contentDescription: fullText,
    tone: tone,
  );
}

/// 官方认证徽章 Widget（支持 Tag 标签与 Avatar 紧凑角标两种形态）。
///
/// 移植自 BiliPai `OfficialVerifyBadgePolicy.kt`：
/// - Tag 模式：
///   - 个人认证：`#FFF3CD` 浅金黄底 + `#7A4B00` 深金褐字
///   - 机构认证：`#DCEBFF` 浅蓝底 + `#174EA6` 深蓝字
///   - 最大宽度 120dp，单行溢出省略
/// - Avatar 模式（[compact] == true 或直接使用 [OfficialVerifyAvatarBadge]）：
///   - 14dp 圆形白底，内嵌个人金黄（`#FFCC00`）或机构亮蓝（`#40C4FF`）闪电微图标。
class OfficialVerifyBadge extends StatelessWidget {
  const OfficialVerifyBadge({
    super.key,
    required this.badge,
    this.compact = false,
  });

  final OfficialVerifyBadgeSpec badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return OfficialVerifyAvatarBadge(badge: badge);
    }

    final shapes = AppThemeHost.of(context).shapes;

    final (containerColor, contentColor) = switch (badge.tone) {
      OfficialVerifyBadgeTone.personal => (
          const Color(0xFFFFF3CD),
          const Color(0xFF7A4B00),
        ),
      OfficialVerifyBadgeTone.organization => (
          const Color(0xFFDCEBFF),
          const Color(0xFF174EA6),
        ),
    };

    return Semantics(
      label: badge.contentDescription,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 120),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: shapes.tinyBorder,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
        child: Text(
          badge.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.0,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: contentColor,
          ),
        ),
      ),
    );
  }
}

/// 头像右下角覆盖的 14dp 官方认证圆形小标。
class OfficialVerifyAvatarBadge extends StatelessWidget {
  const OfficialVerifyAvatarBadge({
    super.key,
    required this.badge,
    this.size = 14.0,
  });

  final OfficialVerifyBadgeSpec badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final iconColor = switch (badge.tone) {
      OfficialVerifyBadgeTone.personal => const Color(0xFFFFCC00),
      OfficialVerifyBadgeTone.organization => const Color(0xFF40C4FF),
    };

    return Semantics(
      label: badge.contentDescription,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tokens.colors.surface,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.bolt,
          size: size - 1.0,
          color: iconColor,
        ),
      ),
    );
  }
}

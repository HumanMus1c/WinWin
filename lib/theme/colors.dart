import 'package:material_ui/material_ui.dart';
import 'package:winwin/theme/app_colors.dart';

// ── Bilibili Brand ──
const Color biliPink = Color(0xFFFA7298);
const Color biliPinkDark = Color(0xFFE45A82);

/// B 站播放器品牌蓝（进度条滑块 / 倍速高亮），对标 BiliPai 播放控件主色。
const Color biliBlue = Color(0xFF00AEEC);

// ── iOS System Colors ──
const Color iosBlue = Color(0xFF007AFF);
const Color iosPink = Color(0xFFFF2D55);
const Color iosGreen = Color(0xFF34C759);
const Color iosOrange = Color(0xFFFF9500);
const Color iosYellow = Color(0xFFFFD60A);
const Color iosRed = Color(0xFFFF3B30);
const Color iosPurple = Color(0xFFAF52DE);
const Color iosTeal = Color(0xFF30B0C7);

// ── iOS Gray Scale (Light) ──
const Color iosSystemGray = Color(0xFF8E8E93);
const Color iosSystemGray2 = Color(0xFFAEAEB2);
const Color iosSystemGray3 = Color(0xFFC7C7CC);
const Color iosSystemGray4 = Color(0xFFD1D1D6);
const Color iosSystemGray5 = Color(0xFFE5E5EA);
const Color iosSystemGray6 = Color(0xFFF2F2F7);

// ── Dark Mode ──
const Color darkBackground = Color(0xFF0D0D0D);
const Color darkSurface = Color(0xFF1A1A1A);
const Color darkSurfaceVariant = Color(0xFF262626);

// ── Light Mode ──
const Color lightBackground = iosSystemGray6;
const Color lightSurface = AppColors.white;

// ── Bottom Bar Color Palette ──
const List<Color> bottomBarColors = [
  iosBlue,    // 0: Home
  iosOrange,  // 1: Dynamic
  iosTeal,    // 2: History
  iosPink,    // 3: Profile
  iosGreen,   // 4: ListenVideo
];

// ── MD3 Color Tokens（Material Design 3 风格专用） ──
// 标准 M3 种子色采用 B 站品牌色衍生，与 iOS 蓝区分以体现风格差异。
const Color md3LightPrimary = Color(0xFF9C4146);      // 品牌粉衍生
const Color md3LightOnPrimary = AppColors.white;
const Color md3LightPrimaryContainer = Color(0xFFFFDADA);
const Color md3LightOnPrimaryContainer = Color(0xFF400012);
const Color md3LightSecondary = Color(0xFF775656);
const Color md3LightOnSecondary = AppColors.white;
const Color md3LightSecondaryContainer = Color(0xFFFFDADA);
const Color md3LightOnSecondaryContainer = Color(0xFF5F1212);
const Color md3LightTertiary = Color(0xFF735C2E);
const Color md3LightOnTertiary = AppColors.white;
const Color md3LightTertiaryContainer = Color(0xFFFFDEA8);
const Color md3LightOnTertiaryContainer = Color(0xFF271900);
const Color md3LightSurface = Color(0xFFFFF8F7);
const Color md3LightSurfaceContainerLowest = AppColors.white;
const Color md3LightSurfaceContainerLow = Color(0xFFF7EFEE);
const Color md3LightSurfaceContainer = Color(0xFFF3EDED);
const Color md3LightSurfaceContainerHigh = Color(0xFFEEE0E0);
const Color md3LightSurfaceContainerHighest = Color(0xFFEDE0E0);
const Color md3LightBackground = Color(0xFFFFF8F7);
const Color md3LightOnSurface = Color(0xFF221919);
const Color md3LightOnSurfaceVariant = Color(0xFF534343);
const Color md3LightOutline = Color(0xFF857373);
const Color md3LightOutlineVariant = Color(0xFFD8C2C2);
const Color md3LightError = Color(0xFFBA1A1A);
const Color md3LightOnError = AppColors.white;
const Color md3LightErrorContainer = Color(0xFFFFDAD6);
const Color md3LightOnErrorContainer = Color(0xFF410E0B);

const Color md3DarkPrimary = Color(0xFFFFB3B5);
const Color md3DarkOnPrimary = Color(0xFF5F131F);
const Color md3DarkPrimaryContainer = Color(0xFF7E2A33);
const Color md3DarkOnPrimaryContainer = Color(0xFFFFDADA);
const Color md3DarkSecondary = Color(0xFFE6BDBD);
const Color md3DarkOnSecondary = AppColors.black;
const Color md3DarkSecondaryContainer = Color(0xFF5D3F3F);
const Color md3DarkOnSecondaryContainer = Color(0xFFFFDADA);
const Color md3DarkTertiary = Color(0xFFE2C28D);
const Color md3DarkOnTertiary = AppColors.black;
const Color md3DarkTertiaryContainer = Color(0xFF594418);
const Color md3DarkOnTertiaryContainer = Color(0xFFFFDEA8);
const Color md3DarkSurface = Color(0xFF1A1111);
const Color md3DarkSurfaceContainerLowest = Color(0xFF0F0909);
const Color md3DarkSurfaceContainerLow = Color(0xFF1A1111);
const Color md3DarkSurfaceContainer = Color(0xFF2D2222);
const Color md3DarkSurfaceContainerHigh = Color(0xFF332626);
const Color md3DarkSurfaceContainerHighest = Color(0xFF3A2C2C);
const Color md3DarkBackground = Color(0xFF1A1111);
const Color md3DarkOnSurface = Color(0xFFF0DEDE);
const Color md3DarkOnSurfaceVariant = Color(0xFFD8C2C2);
const Color md3DarkOutline = Color(0xFFA08C8C);
const Color md3DarkOutlineVariant = Color(0xFF534343);
const Color md3DarkError = Color(0xFFFFB4AB);
const Color md3DarkOnError = AppColors.black;
const Color md3DarkErrorContainer = Color(0xFF93000A);
const Color md3DarkOnErrorContainer = Color(0xFFFFDAD6);

// ── Miuix Color Tokens（扁平、低对比、偏灰） ──
// 参照 BiliPai `BiliMiuixTypography` 的视觉调性：扁平、低 elevation、
// 更"中性"的表面色，与 MD3 的 tonal 区分层级形成可辨识差异。
const Color miuixLightPrimary = Color(0xFFFA7298);     // B 站粉
const Color miuixLightOnPrimary = AppColors.white;
const Color miuixLightPrimaryContainer = Color(0xFFFCE4EC);
const Color miuixLightOnPrimaryContainer = Color(0xFF4A0E22);
const Color miuixLightSecondary = Color(0xFF605B5F);
const Color miuixLightSecondaryContainer = Color(0xFFE8E2E6);
const Color miuixLightTertiary = Color(0xFF5B6354);
const Color miuixLightTertiaryContainer = Color(0xFFDFE8D5);
const Color miuixLightSurface = AppColors.white;
const Color miuixLightSurfaceContainer = Color(0xFFF5F4F5);
const Color miuixLightSurfaceContainerHighest = Color(0xFFEDEDEF);
const Color miuixLightBackground = Color(0xFFFAF9FA);
const Color miuixLightOnSurface = Color(0xFF1C1B1E);
const Color miuixLightOnSurfaceVariant = Color(0xFF46464A);
const Color miuixLightOutline = Color(0xFF77767B);
const Color miuixLightOutlineVariant = Color(0xFFC8C7CC);
const Color miuixLightError = Color(0xFFB3261E);

const Color miuixDarkPrimary = Color(0xFFFFB1C8);
const Color miuixDarkOnPrimary = Color(0xFF5E112F);
const Color miuixDarkPrimaryContainer = Color(0xFF7D2945);
const Color miuixDarkOnPrimaryContainer = Color(0xFFFFD9E2);
const Color miuixDarkSecondary = Color(0xFFCDC6CE);
const Color miuixDarkSecondaryContainer = Color(0xFF48434A);
const Color miuixDarkTertiary = Color(0xFFC2CCB0);
const Color miuixDarkTertiaryContainer = Color(0xFF434B3D);
const Color miuixDarkSurface = Color(0xFF131316);
const Color miuixDarkSurfaceContainer = Color(0xFF1E1E22);
const Color miuixDarkSurfaceContainerHighest = Color(0xFF29292E);
const Color miuixDarkBackground = Color(0xFF131316);
const Color miuixDarkOnSurface = Color(0xFFE5E1E6);
const Color miuixDarkOnSurfaceVariant = Color(0xFFC8C7CC);
const Color miuixDarkOutline = Color(0xFF918E94);
const Color miuixDarkOutlineVariant = Color(0xFF46464A);
const Color miuixDarkError = Color(0xFFF2B8B5);

// ── Cover Placeholder Gradients ──
class GradientPair {
  final Color start;
  final Color end;
  const GradientPair(this.start, this.end);
}

const List<GradientPair> coverGradients = [
  GradientPair(Color(0xFF6C5CE7), Color(0xFFA36EE8)),
  GradientPair(Color(0xFFE17055), Color(0xFFFDCB6E)),
  GradientPair(Color(0xFF00B894), Color(0xFF55EFC4)),
  GradientPair(Color(0xFF0984E3), Color(0xFF74B9FF)),
  GradientPair(Color(0xFFE84393), Color(0xFFFD79A8)),
  GradientPair(Color(0xFFFAB1A0), Color(0xFFE17055)),
  GradientPair(Color(0xFF2D3436), Color(0xFF636E72)),
  GradientPair(Color(0xFF00CEC9), Color(0xFF55EFC4)),
];

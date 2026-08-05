import 'package:flutter/material.dart';

// ── Bilibili Brand ──
const Color biliPink = Color(0xFFFA7298);
const Color biliPinkDark = Color(0xFFE45A82);

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
const Color lightSurface = Colors.white;

// ── Bottom Bar Color Palette ──
const List<Color> bottomBarColors = [
  iosBlue,    // 0: Home
  iosOrange,  // 1: Dynamic
  iosTeal,    // 2: History
  iosPink,    // 3: Profile
  iosGreen,   // 4: ListenVideo
];

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

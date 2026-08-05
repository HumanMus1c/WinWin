import 'package:flutter/material.dart';
import 'colors.dart';
import 'style.dart';

/// App theme — iOS-inspired Material 3 color scheme.
class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: iosBlue,
          onPrimary: Colors.white,
          secondary: iosSystemGray,
          background: lightBackground,
          surface: lightSurface,
          surfaceContainer: iosSystemGray5,
          onSurface: Color(0xFF1C1C1E),
          onSurfaceVariant: iosSystemGray,
          error: iosRed,
        ),
        scaffoldBackgroundColor: lightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: iosBlue,
          onPrimary: Colors.white,
          secondary: iosSystemGray2,
          background: darkBackground,
          surface: darkSurface,
          surfaceContainer: darkSurfaceVariant,
          onSurface: Color(0xFFE8E8E8),
          onSurfaceVariant: Color(0xFFB0B0B0),
          error: iosRed,
        ),
        scaffoldBackgroundColor: darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );
}

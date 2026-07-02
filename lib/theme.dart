import 'package:flutter/material.dart';

/// Central color + theme definitions for SgfScrcpy.
class AppTheme {
  static const Color _seed = Color(0xFF6C5CE7); // violet accent
  static const Color _bg = Color(0xFF0E0F13);
  static const Color _surface = Color(0xFF16181F);
  static const Color _surfaceHigh = Color(0xFF1E212B);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: _surface,
      surfaceContainerHighest: _surfaceHigh,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
      fontFamily: 'Segoe UI',
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

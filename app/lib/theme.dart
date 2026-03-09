import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class YesClaudeTheme {
  // Claude's warm palette
  static const Color ember = Color(0xFFD97757);
  static const Color emberLight = Color(0xFFE8956F);
  static const Color emberGlow = Color(0x33D97757);
  static const Color surface = Color(0xFF131316);
  static const Color surfaceRaised = Color(0xFF1C1C21);
  static const Color surfaceHighest = Color(0xFF26262D);
  static const Color textPrimary = Color(0xFFF0EDE8);
  static const Color textSecondary = Color(0xFF8A8790);
  static const Color deny = Color(0xFFE05252);
  static const Color denySubtle = Color(0x33E05252);
  static const Color success = Color(0xFF4ADE80);
  static const Color successSubtle = Color(0x334ADE80);

  static ThemeData build() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surface,
      colorScheme: const ColorScheme.dark(
        primary: ember,
        onPrimary: Color(0xFF1A1A1A),
        secondary: emberLight,
        surface: surfaceRaised,
        onSurface: textPrimary,
        error: deny,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.5,
          ),
          headlineMedium: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.3,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: textSecondary,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: textSecondary,
          ),
          labelLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ember,
          foregroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: deny,
          side: const BorderSide(color: deny, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ember, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: deny, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: deny, width: 1.5),
        ),
      ),
      useMaterial3: true,
    );
  }

  /// Monospace text style for command display
  static TextStyle monoStyle({double fontSize = 13, Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      color: color ?? textPrimary,
      height: 1.5,
    );
  }
}

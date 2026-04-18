import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Cinematic navy + gold palette
  static const Color primary = Color(0xFFF5C518); // Signature gold
  static const Color secondary = Color(0xFF68D7FF); // Ice blue accent
  static const Color accent = Color(0xFFF97316); // Warm orange accent
  static const Color background = Color(0xFF050B18); // Deep midnight
  static const Color surface = Color(0xFF0D182D); // Elevated navy
  static const Color card = Color(0xFF12203B); // Card navy
  static const Color success = Color(0xFF17C964); // Success
  static const Color warning = Color(0xFFFFB020); // Warning
  static const Color muted = Color(0xFF9CB0D0); // Muted text
  static const Color tertiary = Color(0xFF3B82F6); // Blue highlight

  static const LinearGradient screenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A1630), Color(0xFF081328), Color(0xFF050B18)],
  );

  static ThemeData get darkTheme {
    const baseText = TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        fontFamily: 'Avenir Next',
      ),
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        fontFamily: 'Avenir Next',
      ),
      titleLarge: TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        fontFamily: 'Avenir Next',
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        fontFamily: 'Avenir Next',
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        fontFamily: 'Avenir Next',
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: muted,
        height: 1.45,
        fontFamily: 'Avenir Next',
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: muted,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        fontFamily: 'Avenir Next',
      ),
      labelLarge: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.35,
        fontFamily: 'Avenir Next',
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        tertiary: tertiary,
        onSurface: Colors.white,
        onPrimary: Colors.black,
      ),
      textTheme: baseText.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card.withValues(alpha: 0.72),
        selectedColor: primary.withValues(alpha: 0.2),
        secondarySelectedColor: primary.withValues(alpha: 0.2),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card.withValues(alpha: 0.75),
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary);
          }
          return IconThemeData(color: Colors.white.withValues(alpha: 0.72));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? primary
                : Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          );
        }),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }
}

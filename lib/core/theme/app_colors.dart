import 'package:flutter/material.dart';

/// Local Lekker brand palette.
///
/// Inspired by a "spring daffodil" palette:
///  - Deep ocean blue as the primary brand colour
///  - Mid sky blue for highlights & links
///  - Pale sky blue / cream as soft surface tints
///  - Sun yellow as the accent / call-to-action highlight
///  - Leaf green for success / positive states
///
/// Use these constants instead of hard-coded Material colours so the whole
/// app stays visually consistent.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------------
  // Raw palette (extracted from the colour palette image).
  // ---------------------------------------------------------------------------
  static const Color sunYellow = Color(0xFFF4B400); // 1 - vibrant golden
  static const Color cream = Color(0xFFFAEDA0);     // 2 - pale cream/light yellow
  static const Color skyLight = Color(0xFFBDE3F2);  // 3 - pale sky blue
  static const Color sky = Color(0xFF3DA8DC);       // 4 - medium sky blue
  static const Color oceanDeep = Color(0xFF0E5BA0); // 5 - deep ocean blue
  static const Color leaf = Color(0xFF3C8C44);      // 6 - forest green

  // ---------------------------------------------------------------------------
  // Semantic aliases used across the app.
  // ---------------------------------------------------------------------------
  /// Primary brand colour — used for AppBars, primary buttons, FABs.
  static const Color primary = oceanDeep;

  /// Lighter variant of the primary colour — links, secondary accents.
  static const Color primaryLight = sky;

  /// Very soft tint of the primary colour — chip backgrounds, hovers.
  static const Color primarySoft = skyLight;

  /// Bright accent — promotional badges, highlights, CTAs.
  static const Color accent = sunYellow;

  /// Warm surface tint — info banners, gentle backgrounds.
  static const Color accentSoft = cream;

  /// Success / positive state.
  static const Color success = leaf;

  /// Error / destructive state.
  static const Color error = Color(0xFFD32F2F);

  /// Warning state (kept warm to match the palette).
  static const Color warning = Color(0xFFE69500);

  /// Default surface (cards, sheets, scaffold).
  static const Color surface = Colors.white;

  /// App background — very soft sky tint for a fresh feel.
  static const Color background = Color(0xFFF5FAFD);

  /// Primary text on light surfaces.
  static const Color textPrimary = Color(0xFF0B2540);

  /// Secondary / muted text.
  static const Color textSecondary = Color(0xFF5A6B7B);

  /// Divider / outline.
  static const Color outline = Color(0xFFD8E3EC);

  // ---------------------------------------------------------------------------
  // Convenience gradients.
  // ---------------------------------------------------------------------------
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [oceanDeep, sky],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sunYellow, Color(0xFFFFD24D)],
  );

  static const LinearGradient freshGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sky, leaf],
  );

  /// MaterialColor swatch built from the primary brand blue. Useful for
  /// widgets that still require a `MaterialColor` (e.g. `primarySwatch`).
  static const MaterialColor primarySwatch = MaterialColor(
    0xFF0E5BA0,
    <int, Color>{
      50: Color(0xFFE3EFF8),
      100: Color(0xFFBAD7ED),
      200: Color(0xFF8DBDE1),
      300: Color(0xFF5FA2D5),
      400: Color(0xFF3D8ECB),
      500: Color(0xFF0E5BA0), // base
      600: Color(0xFF0C5395),
      700: Color(0xFF094988),
      800: Color(0xFF073F7B),
      900: Color(0xFF032E63),
    },
  );
}

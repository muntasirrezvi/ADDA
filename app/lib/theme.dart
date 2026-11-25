import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const bg = Color(0xFF0C0A09);
  static const panel = Color(0xFF151210);
  static const card = Color(0xFF1B1714);
  static const line = Color(0xFF2C2620);
  static const text = Color(0xFFF4EDE1);
  static const mute = Color(0xFFA39886);
  static const gold = Color(0xFFD8B77A);
  static const gold2 = Color(0xFFB8924F);
  static const emerald = Color(0xFF2A9D7F);
  static const ruby = Color(0xFFC9506C);
  static const goldGrad = LinearGradient(colors: [Color(0xFFF0D9A6), Color(0xFFB8924F)], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

TextStyle serif(double size, {Color color = C.text, FontWeight weight = FontWeight.w700}) =>
    GoogleFonts.bodoniModa(fontSize: size, color: color, fontWeight: weight);

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: C.text, displayColor: C.text);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    textTheme: text,
    colorScheme: const ColorScheme.dark(primary: C.gold, secondary: C.emerald, error: C.ruby, surface: C.panel, onPrimary: Color(0xFF1A1206)),
    appBarTheme: AppBarTheme(backgroundColor: C.bg, elevation: 0, centerTitle: false, titleTextStyle: serif(22), foregroundColor: C.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF100D0B),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.gold)),
      labelStyle: const TextStyle(color: C.mute),
      hintStyle: const TextStyle(color: C.mute),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.panel, showDragHandle: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
    dialogTheme: DialogThemeData(backgroundColor: C.panel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: C.card, contentTextStyle: TextStyle(color: C.text)),
    dividerColor: C.line,
    chipTheme: base.chipTheme.copyWith(backgroundColor: C.card, selectedColor: const Color(0xFF3A2E17), side: const BorderSide(color: C.line), labelStyle: const TextStyle(color: C.text)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.panel,
      indicatorColor: const Color(0xFF3A2E17),
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.plusJakartaSans(fontSize: 11, color: C.mute)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.gold : C.mute)),
    ),
    tabBarTheme: const TabBarThemeData(labelColor: C.gold, unselectedLabelColor: C.mute, indicatorColor: C.gold, dividerColor: Colors.transparent),
  );
}

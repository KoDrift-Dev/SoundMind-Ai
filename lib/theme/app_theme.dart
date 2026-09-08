import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light = ThemeData(
    brightness: Brightness.light,
    primaryColor: const Color(0xFF0A84FF),
    scaffoldBackgroundColor: const Color(0xFFF2F5FA),
    canvasColor: Colors.transparent,
    textTheme: TextTheme(
      displayLarge: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
      titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black87),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: Colors.black87),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
    ),
    iconTheme: const IconThemeData(color: Colors.black87),
    appBarTheme: const AppBarTheme(elevation: 0, backgroundColor: Colors.transparent),
  );

  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    primaryColor: const Color(0xFF0A84FF),
    scaffoldBackgroundColor: const Color(0xFF030712),
    canvasColor: Colors.transparent,
    textTheme: TextTheme(
      displayLarge: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white70),
      titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white70),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: Colors.white70),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: Colors.white60),
    ),
    iconTheme: const IconThemeData(color: Colors.white70),
    appBarTheme: const AppBarTheme(elevation: 0, backgroundColor: Colors.transparent),
  );
}

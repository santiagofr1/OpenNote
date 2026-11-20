import 'package:flutter/material.dart';

/// Tema común: esquinas redondeadas parejas (10 / 14 / 18 / 26) en todo lo que flota.
ThemeData appTheme(ColorScheme cs) {
  RoundedRectangleBorder r(double v) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(v));
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    popupMenuTheme: PopupMenuThemeData(
      shape: r(18),
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black45,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      textStyle: TextStyle(fontSize: 15, color: cs.onSurface),
    ),
    dialogTheme: DialogThemeData(
      shape: r(26),
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: cs.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 1.5)),
    ),
    snackBarTheme: SnackBarThemeData(shape: r(14), behavior: SnackBarBehavior.floating),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(10)),
      textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(26))),
    ),
    chipTheme: ChipThemeData(shape: r(10)),
    // el slider 2024 (el default sigue siendo el viejo); se va cuando Flutter cambie el default
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );
}

import 'package:flutter/material.dart';

const double kPaperRadius = 12;
const double kTitleBarHeight = 38;

/// Bảng màu kiểu giấy note. Có bản sáng và bản tối; widget đọc bản đúng theo
/// brightness hiện tại bằng `context.paper` nên không cần biết themeMode.
@immutable
class PaperColors {
  const PaperColors({
    required this.bg,
    required this.bgTop,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.done,
    required this.danger,
  });

  /// Giấy vàng nhạt.
  static const PaperColors light = PaperColors(
    bg: Color(0xFFFDF6DC),
    bgTop: Color(0xFFFFFBEC),
    surface: Color(0xFFFFFDF3),
    ink: Color(0xFF3A3226),
    inkSoft: Color(0xFF7A7060),
    inkFaint: Color(0xFFA79C86),
    line: Color(0xFFE8DCB8),
    accent: Color(0xFFE8A838),
    done: Color(0xFF6E9E62),
    danger: Color(0xFFC4664F),
  );

  /// Giấy nâu tối — giữ tông ấm để vẫn ra dáng sticky note, không xám xanh.
  static const PaperColors dark = PaperColors(
    bg: Color(0xFF211E18),
    bgTop: Color(0xFF2A261E),
    surface: Color(0xFF332E25),
    ink: Color(0xFFEDE4D0),
    inkSoft: Color(0xFFB5AA94),
    inkFaint: Color(0xFF7E7566),
    line: Color(0xFF453E31),
    accent: Color(0xFFE8A838),
    done: Color(0xFF7FB06F),
    danger: Color(0xFFD97B62),
  );

  final Color bg;
  final Color bgTop;
  final Color surface;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color line;
  final Color accent;
  final Color done;
  final Color danger;

  static PaperColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

extension PaperContext on BuildContext {
  /// Bảng màu khớp với brightness đang hiệu lực (kể cả khi themeMode = system).
  PaperColors get paper => PaperColors.of(Theme.of(this).brightness);
}

ThemeData buildStickyTheme(Brightness brightness) {
  final paper = PaperColors.of(brightness);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: paper.accent,
      brightness: brightness,
      surface: paper.surface,
    ),
    scaffoldBackgroundColor: Colors.transparent,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: paper.ink,
      displayColor: paper.ink,
    ),
    splashFactory: NoSplash.splashFactory,
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

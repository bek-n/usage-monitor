import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.background,
    required this.card,
    required this.border,
    required this.text,
    required this.muted,
    required this.track,
    required this.meter,
    required this.warn,
    required this.critical,
    required this.accent,
    required this.accentSoft,
  });

  final Color background;
  final Color card;
  final Color border;
  final Color text;
  final Color muted;
  final Color track;
  final Color meter;
  final Color warn;
  final Color critical;
  final Color accent;
  final Color accentSoft;

  static const light = Palette(
    background: Color(0xFFF5F4F0),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE6E3DC),
    text: Color(0xFF1F1E1C),
    muted: Color(0xFF77736B),
    track: Color(0xFFECE9E2),
    meter: Color(0xFF2E2D2A),
    warn: Color(0xFFD9901A),
    critical: Color(0xFFD93F3F),
    accent: Color(0xFFC2603A),
    accentSoft: Color(0xFFF7E6DE),
  );

  static const dark = Palette(
    background: Color(0xFF1B1A19),
    card: Color(0xFF252422),
    border: Color(0xFF34322F),
    text: Color(0xFFEDEBE6),
    muted: Color(0xFF9D9890),
    track: Color(0xFF383632),
    meter: Color(0xFFE9E6DF),
    warn: Color(0xFFF0AB3C),
    critical: Color(0xFFF26161),
    accent: Color(0xFFE08360),
    accentSoft: Color(0xFF3D2A22),
  );

  static const avatarColors = [
    Color(0xFFC2603A),
    Color(0xFF3E7CB1),
    Color(0xFF4C9A6A),
    Color(0xFF8E6BBF),
    Color(0xFFB8862B),
    Color(0xFF3B9696),
  ];

  Color meterColor(double percent) => percent >= 90
      ? critical
      : percent >= 75
          ? warn
          : meter;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness,
  ).copyWith(
    primary: palette.accent,
    surface: palette.card,
    onSurface: palette.text,
    outline: palette.border,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    extensions: [palette],
    visualDensity: VisualDensity.compact,
    textTheme: Typography.material2021(platform: defaultTargetPlatform)
        .black
        .apply(bodyColor: palette.text, displayColor: palette.text),
    dividerTheme: DividerThemeData(color: palette.border, space: 1, thickness: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: palette.border),
      ),
      textStyle: TextStyle(fontSize: 13, color: palette.text),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: palette.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.border),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.pending,
    required this.inProgress,
    required this.accident,
    required this.normal,
    required this.vidange,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color pending;
  final Color inProgress;
  final Color accident;
  final Color normal;
  final Color vidange;

  Color tint(Color color) => color.withValues(alpha: 0.11);

  Color statusColor(String key) => switch (key) {
        'pending' || 'قيد الانتظار' => pending,
        'in_progress' || 'قيد التصليح' => inProgress,
        'accident' || 'حادث' => accident,
        'vidange' || 'Vidange' => vidange,
        'fixed' || 'تم الإصلاح' || 'normal' || 'سليمة' => normal,
        _ => textSecondary,
      };

  static const light = AppColors(
    background: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF1F5),
    border: Color(0xFFE2E6EC),
    textPrimary: Color(0xFF101828),
    textSecondary: Color(0xFF475467),
    primary: Color(0xFF0A5FD6),
    pending: Color(0xFFC5271C),
    inProgress: Color(0xFFB54708),
    accident: Color(0xFF6941C6),
    normal: Color(0xFF067647),
    vidange: Color(0xFF0E7490),
  );

  static const dark = AppColors(
    background: Color(0xFF0B0F14),
    surface: Color(0xFF151B23),
    surfaceAlt: Color(0xFF1D252F),
    border: Color(0xFF2A3441),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFF98A2B3),
    primary: Color(0xFF5B9DFF),
    pending: Color(0xFFF97066),
    inProgress: Color(0xFFFDA14A),
    accident: Color(0xFFA48BFA),
    normal: Color(0xFF47CD89),
    vidange: Color(0xFF5CC8E0),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
    Color? pending,
    Color? inProgress,
    Color? accident,
    Color? normal,
    Color? vidange,
  }) =>
      AppColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        primary: primary ?? this.primary,
        pending: pending ?? this.pending,
        inProgress: inProgress ?? this.inProgress,
        accident: accident ?? this.accident,
        normal: normal ?? this.normal,
        vidange: vidange ?? this.vidange,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      inProgress: Color.lerp(inProgress, other.inProgress, t)!,
      accident: Color.lerp(accident, other.accident, t)!,
      normal: Color.lerp(normal, other.normal, t)!,
      vidange: Color.lerp(vidange, other.vidange, t)!,
    );
  }
}

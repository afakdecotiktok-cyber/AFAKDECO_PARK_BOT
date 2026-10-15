import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';

class StatusIcons extends StatelessWidget {
  final List<dynamic> icons;
  const StatusIcons({super.key, required this.icons});

  static const Map<String, int> _priority = {
    'accident': 0,
    'pending': 1,
    'vidange': 1,
    'in_progress': 2,
    'normal': 3,
  };

  static const Map<String, IconData> _glyphs = {
    'accident': Icons.warning_rounded,
    'pending': Icons.hourglass_top_rounded,
    'in_progress': Icons.build_circle_rounded,
    'vidange': Icons.handyman_rounded,
    'normal': Icons.check_circle_rounded,
  };

  static String labelFor(String status) => switch (status) {
        'accident' => AppStrings.accident,
        'pending' => AppStrings.waiting,
        'in_progress' => AppStrings.inProgress,
        'vidange' => AppStrings.vidange,
        _ => 'سليمة',
      };

  static Color colorFor(BuildContext context, String status) =>
      AppColors.of(context).statusColor(status);

  @override
  Widget build(BuildContext context) {
    final supplied = icons.map((item) => '$item').toList();
    final visible = supplied.where((item) => item != 'normal').toSet().toList();
    if (visible.isEmpty) visible.add('normal');
    visible.sort((a, b) =>
        (_priority[a] ?? 99).compareTo(_priority[b] ?? 99));

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 4,
      children: visible.map((status) {
        final glyph = _glyphs[status] ?? _glyphs['normal']!;
        final label = labelFor(status);
        final color = colorFor(context, status);
        return Semantics(
          label: 'الحالة: $label',
          child: Tooltip(
            message: label,
            child: Icon(glyph, color: color, size: 21),
          ),
        );
      }).toList(),
    );
  }
}

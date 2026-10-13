import 'package:flutter/material.dart';

class StatusIcons extends StatelessWidget {
  final List<dynamic> icons;
  const StatusIcons({super.key, required this.icons});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: icons.map((item) {
          final value = '$item';
          final data = switch (value) {
            'accident' => (Icons.warning_rounded, const Color(0xFF7B3FF2)),
            'pending' => (Icons.hourglass_top_rounded, const Color(0xFFE53935)),
            'in_progress' => (Icons.build_circle_rounded, const Color(0xFFF28C28)),
            'vidange' => (Icons.handyman_rounded, const Color(0xFF6D4C41)),
            _ => (Icons.check_circle_rounded, const Color(0xFF2E7D32)),
          };
          return Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Icon(data.$1, color: data.$2, size: 21),
          );
        }).toList(),
      );
}

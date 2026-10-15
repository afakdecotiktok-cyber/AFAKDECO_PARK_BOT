import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afakdeco_admin/widgets/status_icons.dart';

void main() {
  testWidgets('renders accident before pending and keeps both indicators', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusIcons(icons: ['pending', 'accident']),
        ),
      ),
    );

    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byTooltip('حادث'), findsOneWidget);
    expect(find.byTooltip('قيد الانتظار'), findsOneWidget);
  });

  testWidgets('does not show normal indicator alongside an active status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusIcons(icons: ['normal', 'pending', 'vidange']),
        ),
      ),
    );

    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byIcon(Icons.handyman_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  testWidgets('light and dark themes both render status indicators', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
            body: StatusIcons(icons: ['accident', 'in_progress', 'vidange']),
          ),
        ),
      );
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
      expect(find.byIcon(Icons.build_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.handyman_rounded), findsOneWidget);
    }
  });
}
